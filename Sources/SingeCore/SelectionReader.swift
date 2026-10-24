import AppKit
import ApplicationServices
import os

let singeLogger = Logger(subsystem: "app.singe.Singe", category: "lookup")

/// Logs to the unified log, and to stderr when SINGE_DEBUG is set.
enum singeLog {
    static func notice(_ message: String) {
        singeLogger.notice("\(message, privacy: .public)")
        if ProcessInfo.processInfo.environment["SINGE_DEBUG"] != nil {
            FileHandle.standardError.write("[singe] \(message)\n".data(using: .utf8)!)
        }
    }
}

/// What is highlighted in the frontmost app, and where it sits on screen.
struct Selection {
    let text: String
    var rect: CGRect?          // AppKit screen coordinates (bottom-left origin)
    let font: NSFont?
    var appName: String
    /// The text field or page the selection is in, for placing the popover when `rect` is unknown.
    var field: CGRect? = nil
    var bundleID: String? = nil
    /// How it was read ("AX range", "text markers", "⌘C" …), for `Singe --probe`.
    var via: String = ""
}

/// Reads the highlighted text through the Accessibility API. Web views (Chrome,
/// Electron, Safari) expose it as a text-marker range; native apps as a plain range.
/// When neither works, it copies the selection with ⌘C and restores the clipboard.
///
/// Whether the highlight can be drawn depends on the app saying *where* the text is.
/// Most apps do; some (Chrome) only do once their full accessibility mode is on. When a
/// lookup comes back without a position and the app's Highlight switch is on (menu → Apps),
/// Singe turns that mode on once, waits for it, and remembers the app needs it. No app is
/// special-cased in code.
enum SelectionReader {
    /// `app` defaults to the frontmost app. A named app is read without ⌘C, so
    /// `Singe --probe` can test an app in the background without touching your clipboard.
    static func read(app target: NSRunningApplication? = nil) -> Selection? {
        guard let app = target ?? NSWorkspace.shared.frontmostApplication else { return nil }
        // ⌘C lands in whichever app has focus, so a read aimed at a named app (the self-test,
        // --probe) never copies: it could land in the app you are working in.
        let canCopy = target == nil
        let access = AppAccess.shared
        let allowed = access.highlightAllowed(app.bundleIdentifier)

        var sel = readOnce(app, allowCopy: false, canCopy: canCopy, wake: allowed)
        if sel == nil {
            // the app may still be building its accessibility tree: try once more
            Thread.sleep(forTimeInterval: 0.15)
            sel = readOnce(app, allowCopy: false, canCopy: canCopy, wake: allowed)
        }
        if sel?.rect != nil, settle(app.processIdentifier) {
            // the full mode was still being built after the first lookup; it works now
            access.markDeep(bundle: app.bundleIdentifier, name: app.localizedName ?? "")
        }
        // No position: if the highlight is wanted here, turn on the app's full accessibility
        // mode once and give it a moment to build its tree. Waiting beats a ⌘C, which has no
        // position and so no highlight.
        if allowed, sel?.rect == nil, !access.needsDeep(app.bundleIdentifier), firstTry(app.processIdentifier) {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.3)
            enableDeep(axApp)
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 0.2)
                if let again = readOnce(app, allowCopy: false, canCopy: canCopy, wake: true), again.rect != nil {
                    singeLog.notice("\(again.appName) reports positions in its full accessibility mode; remembered")
                    access.markDeep(bundle: app.bundleIdentifier, name: again.appName)
                    return again
                }
            }
            // Chrome can take several seconds to build its tree the first time: leave the mode on,
            // look again shortly, and keep it only if the app then says where its text is
            markPending(app.processIdentifier)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
                guard isPending(app.processIdentifier), !app.isTerminated else { return }
                let later = readOnce(app, allowCopy: false, canCopy: false, wake: false)
                if later?.rect != nil, settle(app.processIdentifier) {
                    access.markDeep(bundle: app.bundleIdentifier, name: app.localizedName ?? "")
                } else if later != nil, settle(app.processIdentifier) {
                    singeLog.notice("\(app.localizedName ?? "") gives no positions even in its full accessibility mode")
                    disableDeep(axApp)          // it did not help; put the app back the way it was
                }
                // nothing selected by then: undecided, the next lookup settles it
            }
        }
        return sel ?? readOnce(app, allowCopy: true, canCopy: canCopy, wake: allowed)
    }

    private static var pending: Set<pid_t> = []

    private static func markPending(_ pid: pid_t) {
        triedLock.lock(); defer { triedLock.unlock() }
        pending.insert(pid)
    }

    private static func isPending(_ pid: pid_t) -> Bool {
        triedLock.lock(); defer { triedLock.unlock() }
        return pending.contains(pid)
    }

    /// True once for a process whose full mode was left on undecided.
    private static func settle(_ pid: pid_t) -> Bool {
        triedLock.lock(); defer { triedLock.unlock() }
        return pending.remove(pid) != nil
    }

    private static var tried: Set<pid_t> = []
    private static let triedLock = NSLock()

    /// The full mode is tried once per launch of an app: one that still gives no position
    /// with it on must not cost a wait on every lookup.
    private static func firstTry(_ pid: pid_t) -> Bool {
        triedLock.lock(); defer { triedLock.unlock() }
        return tried.insert(pid).inserted
    }

    /// Chrome, Electron and Safari build their accessibility tree only when asked. Asking
    /// as soon as an app comes to the front means the tree is ready by the time you hold ⌃.
    static func prepare(_ app: NSRunningApplication?) {
        guard let app, AppAccess.shared.highlightAllowed(app.bundleIdentifier) else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        // an app that is still launching cannot answer yet; ask again for a few seconds
        for _ in 0..<6 where wakeUp(axApp, app: app) == .cannotComplete {
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// The Highlight switch went off: turn the app's accessibility modes back off.
    static func release(_ app: NSRunningApplication) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanFalse)
        disableDeep(axApp)
    }

    private static func readOnce(_ app: NSRunningApplication, allowCopy: Bool, canCopy: Bool, wake: Bool) -> Selection? {
        guard var sel = readElements(app, allowCopy: allowCopy, canCopy: canCopy, wake: wake) else { return nil }
        sel.bundleID = app.bundleIdentifier
        return sel
    }

    private static func readElements(_ app: NSRunningApplication, allowCopy: Bool, canCopy: Bool, wake: Bool) -> Selection? {
        let appName = app.localizedName ?? "Unknown"
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        if wake { wakeUp(axApp, app: app) }
        let forceCopy = ProcessInfo.processInfo.environment["SINGE_FORCE_COPY"] != nil

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.3)
        // the system-wide focus belongs to the frontmost app; only ask it when that is the target
        let focused: AXUIElement? = attribute(axApp, kAXFocusedUIElementAttribute)
            ?? (canCopy ? attribute(systemWide, kAXFocusedUIElementAttribute) : nil)
        if focused == nil { singeLog.notice("no focused element in \(appName)") }
        if let el = focused, !forceCopy {
            if let sel = fromTextMarkers(el, appName: appName) {
                singeLog.notice("selection via text markers in \(appName): \(sel.text.count) chars, rect \(sel.rect != nil)")
                return verified(sel, via: "text markers", canCopy: canCopy)
            }
            if var sel = fromRange(el, appName: appName) {
                singeLog.notice("selection via AX range in \(appName): \(sel.text.count) chars, rect \(sel.rect != nil)")
                sel.via = "AX range"
                return sel
            }
            // Web content: the focused element may be a container; try its web area.
            var node: AXUIElement? = el
            for _ in 0..<6 {
                guard let n = node, let parent: AXUIElement = attribute(n, kAXParentAttribute) else { break }
                if let sel = fromTextMarkers(parent, appName: appName) {
                    singeLog.notice("selection via parent text markers in \(appName)")
                    return verified(sel, via: "parent text markers", canCopy: canCopy)
                }
                node = parent
            }
        }
        // Chrome often reports no focused element for a page; find its web area instead.
        if !forceCopy {
            let windows: [AXUIElement] = attribute(axApp, kAXWindowsAttribute) ?? []
            let window: AXUIElement? = attribute(axApp, kAXFocusedWindowAttribute) ?? attribute(axApp, kAXMainWindowAttribute)
                ?? windows.first
            let web = window.flatMap(findWebArea)
            if let web, let sel = fromTextMarkers(web, appName: appName) {
                singeLog.notice("selection via web area in \(appName): \(sel.text.count) chars, rect \(sel.rect != nil)")
                return verified(sel, via: "web area", canCopy: canCopy)
            }
            singeLog.notice("web area search in \(appName): window \(window != nil), web area \(web != nil)")
            if let web, ProcessInfo.processInfo.environment["SINGE_DEBUG"] != nil { describeWebArea(web, appName: appName) }
            // some apps report no focus, or focus on a toolbar; the text holding the selection is
            // still in the window
            if let window, let el = findSelectedText(in: window), var sel = fromRange(el, appName: appName) {
                singeLog.notice("selection via window search in \(appName): \(sel.text.count) chars, rect \(sel.rect != nil)")
                sel.via = "AX range (window search)"
                return sel
            }
        }
        // ⌘C goes to the frontmost app, so it is only used when that is the app being read
        guard canCopy, allowCopy || forceCopy else { return nil }
        if let text = copySelection(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            singeLog.notice("selection via ⌘C in \(appName): \(text.count) chars")
            return Selection(text: text, rect: focused.flatMap { checked(caretRect($0), in: $0) }, font: nil,
                             appName: appName, field: focused.flatMap(fieldFrame), via: "⌘C")
        }
        singeLog.notice("nothing selected in \(appName)")
        return nil
    }

    // MARK: native text (NSTextView, Notes, Mail, Pages …)

    private static func fromRange(_ el: AXUIElement, appName: String) -> Selection? {
        guard let text: String = attribute(el, kAXSelectedTextAttribute),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var rect: CGRect?
        var font: NSFont?
        if let rangeValue: AXValue = attribute(el, kAXSelectedTextRangeAttribute) {
            var bounds: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                          rangeValue, &bounds) == .success,
               let b = bounds, CFGetTypeID(b) == AXValueGetTypeID() {
                var r = CGRect.zero
                if AXValueGetValue(b as! AXValue, .cgRect, &r) { rect = flip(r) }
            }
            var attributed: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(el, kAXAttributedStringForRangeParameterizedAttribute as CFString,
                                                          rangeValue, &attributed) == .success,
               let a = attributed as? NSAttributedString, a.length > 0 {
                font = fontFrom(a)
            }
        }
        return Selection(text: text, rect: checked(rect, in: el), font: font, appName: appName, field: fieldFrame(el))
    }

    // MARK: web content (Chrome, Safari, Electron)

    private static func fromTextMarkers(_ el: AXUIElement, appName: String) -> Selection? {
        var marker: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXSelectedTextMarkerRange" as CFString, &marker) == .success,
              let range = marker else { return nil }
        var str: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, "AXStringForTextMarkerRange" as CFString, range, &str) == .success,
              let text = str as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var rect: CGRect?
        var bounds: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(el, "AXBoundsForTextMarkerRange" as CFString, range, &bounds) == .success,
           let b = bounds, CFGetTypeID(b) == AXValueGetTypeID() {
            var r = CGRect.zero
            if AXValueGetValue(b as! AXValue, .cgRect, &r), r.width > 0, r.height > 0 { rect = flip(r) }
        }
        var font: NSFont?
        var attributed: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(el, "AXAttributedStringForTextMarkerRange" as CFString, range, &attributed) == .success,
           let a = attributed as? NSAttributedString, a.length > 0 {
            font = fontFrom(a)
        }
        return Selection(text: text, rect: checked(rect, in: el), font: font, appName: appName, field: fieldFrame(el))
    }

    /// Debug only: why a web area gave no selection (which attributes it offers, what the
    /// selected-marker call answered), for browsers that read differently from Safari and Chrome.
    private static func describeWebArea(_ web: AXUIElement, appName: String) {
        var names: CFArray?
        AXUIElementCopyAttributeNames(web, &names)
        var marker: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(web, "AXSelectedTextMarkerRange" as CFString, &marker)
        let selected: String = attribute(web, kAXSelectedTextAttribute) ?? "-"
        singeLog.notice("web area in \(appName): AXSelectedTextMarkerRange \(err.rawValue), selected text \"\(selected.prefix(40))\", "
                        + "attributes \((names as? [String] ?? []).joined(separator: " "))")
    }

    /// Asks the app to build its accessibility tree. Electron answers AXManualAccessibility;
    /// apps that remembered needing it (menu → Apps) also get their full accessibility mode.
    @discardableResult
    private static func wakeUp(_ axApp: AXUIElement, app: NSRunningApplication) -> AXError {
        let manual = AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard AppAccess.shared.needsDeep(app.bundleIdentifier) else { return manual }
        return enableDeep(axApp)
    }

    /// AXEnhancedUserInterface: the switch VoiceOver uses. Chrome 155 ignores the quieter
    /// AXManualAccessibility and only builds its page tree for this one (and reports "not
    /// implemented" while doing so). It can also change how an app animates its windows,
    /// which is why it is only sent to apps that need it to report positions.
    @discardableResult
    private static func enableDeep(_ axApp: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private static func disableDeep(_ axApp: AXUIElement) {
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
    }

    private static func fontFrom(_ a: NSAttributedString) -> NSFont? {
        let attrs = a.attributes(at: 0, effectiveRange: nil)
        if let f = attrs[.font] as? NSFont { return f }
        if let dict = attrs[NSAttributedString.Key("AXFont")] as? [String: Any] {
            let size = (dict["AXFontSize"] as? CGFloat) ?? 13
            let name = dict["AXFontName"] as? String
            return name.flatMap { NSFont(name: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
        }
        return nil
    }

    // MARK: clipboard fallback

    private static func copySelection() -> String? {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item -> [(NSPasteboard.PasteboardType, Data)] in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        } ?? []
        let before = pb.changeCount
        // A private source keeps the physically held Control key out of the event:
        // with the combined session state the app would receive ⌃⌘C and copy nothing.
        let src = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)   // C
        let up = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        up?.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        let deadline = Date().addingTimeInterval(0.45)
        while pb.changeCount == before && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard pb.changeCount != before else { return nil }
        let text = pb.string(forType: .string)
        pb.clearContents()
        let items = saved.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, d) in pairs { item.setData(d, forType: t) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
        return text
    }

    /// Breadth-first search for the page's AXWebArea, a few levels deep. Toolbars are skipped:
    /// a full bookmarks bar, tab groups and extension buttons used up the whole budget before
    /// the search reached Chrome's page, so Chrome always fell back to ⌘C (no highlight).
    private static let notPage: Set<String> = ["AXToolbar", "AXTabGroup", "AXMenuBar", "AXMenu", "AXButton",
                                                "AXPopUpButton", "AXMenuButton", "AXTextField", "AXRadioButton"]

    private static func findWebArea(in root: AXUIElement) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty && visited < 600 {
            let (el, depth) = queue.removeFirst()
            visited += 1
            let role: String? = attribute(el, kAXRoleAttribute)
            if role == "AXWebArea" { return el }
            if let role, notPage.contains(role) { continue }
            guard depth < 12, let kids: [AXUIElement] = attribute(el, kAXChildrenAttribute) else { continue }
            queue.append(contentsOf: kids.map { ($0, depth + 1) })
        }
        return nil
    }

    /// Breadth-first search for a text element with a non-empty selection.
    private static func findSelectedText(in root: AXUIElement) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var visited = 0
        while !queue.isEmpty && visited < 600 {
            let el = queue.removeFirst()
            visited += 1
            if let text: String = attribute(el, kAXSelectedTextAttribute),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return el }
            if let kids: [AXUIElement] = attribute(el, kAXChildrenAttribute) { queue += kids }
        }
        return nil
    }

    /// Web pages can misreport their selection: text inside an aria-hidden section is missing
    /// from the accessibility tree, so the browser reports the nearest accessible text instead
    /// (on sorph.me, selecting "Get Sorph" reported the footer). When the reported selection
    /// looks implausible (no position, a huge area, or far from the pointer you just selected
    /// with), confirm it with a copy; if the two disagree, the copy is the truth.
    private static func verified(_ sel: Selection, via: String, canCopy: Bool) -> Selection {
        var sel = sel
        sel.via = via
        guard canCopy else { return sel }
        let mouse = NSEvent.mouseLocation
        var suspicious = true
        if let r = sel.rect {
            let dx = max(r.minX - mouse.x, 0, mouse.x - r.maxX)
            let dy = max(r.minY - mouse.y, 0, mouse.y - r.maxY)
            suspicious = r.height > 80 || hypot(dx, dy) > 240
        }
        guard suspicious, let copied = copySelection() else { return sel }
        let a = TermIndex.normalize(copied), b = TermIndex.normalize(sel.text)
        guard !a.isEmpty, a != b else { return sel }
        singeLog.notice("selection reported by accessibility did not match the copy; using the copy (\(a.count) chars)")
        return Selection(text: copied, rect: nil, font: nil, appName: sel.appName, field: sel.field, via: "⌘C (\(via) disagreed)")
    }

    /// Marks Singe's own synthetic ⌘C so the hold monitor ignores it.
    static let syntheticTag: Int64 = 0x53494E4745   // "SINGE"

    /// Where the text cursor is, when the app tells us; used to place the popover after ⌘C.
    private static func caretRect(_ el: AXUIElement) -> CGRect? {
        guard let range: AXValue = attribute(el, kAXSelectedTextRangeAttribute) else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &bounds) == .success,
              let b = bounds, CFGetTypeID(b) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        guard AXValueGetValue(b as! AXValue, .cgRect, &r), r.width > 1, r.height > 1 else { return nil }
        return flip(r)
    }

    /// Some apps (alfaview and other Qt apps) report selection bounds that are nowhere near
    /// the text, so the highlight and popover appeared far from the word. Bounds must lie on
    /// a screen and inside the element that holds the text; otherwise they are dropped.
    private static func checked(_ rect: CGRect?, in el: AXUIElement) -> CGRect? {
        guard let r = rect, r.width > 0, r.height > 0 else { return nil }
        let onScreen = NSScreen.screens.contains { $0.frame.intersects(r) }
        let inside = fieldFrame(el).map { $0.insetBy(dx: -8, dy: -8).contains(CGPoint(x: r.midX, y: r.midY)) } ?? true
        if !onScreen || !inside {
            singeLog.notice("dropped selection bounds \(r) outside \(fieldFrame(el).map { "\($0)" } ?? "the screen")")
            return nil
        }
        return r
    }

    /// The element's frame in AppKit screen coordinates.
    private static func fieldFrame(_ el: AXUIElement) -> CGRect? {
        guard let p: AXValue = attribute(el, kAXPositionAttribute), let s: AXValue = attribute(el, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p, .cgPoint, &origin), AXValueGetValue(s, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return flip(CGRect(origin: origin, size: size))
    }

    // MARK: helpers

    private static func attribute<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Accessibility uses a top-left origin on the primary screen; AppKit a bottom-left one.
    private static func flip(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }
}
