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
    let rect: CGRect?          // AppKit screen coordinates (bottom-left origin)
    let font: NSFont?
    let appName: String
}

/// Reads the highlighted text through the Accessibility API. Web views (Chrome,
/// Electron, Safari) expose it as a text-marker range; native apps as a plain range.
/// When neither works, it copies the selection with ⌘C and restores the clipboard.
enum SelectionReader {
    static func read() -> Selection? {
        if let sel = readOnce(allowCopy: false) { return sel }
        // Chrome / Electron may still be building their accessibility tree: try once more.
        Thread.sleep(forTimeInterval: 0.15)
        return readOnce(allowCopy: true)
    }

    /// Chrome, Electron and Safari build their accessibility tree only when asked. Asking
    /// as soon as an app comes to the front means the tree is ready by the time you hold ⌃.
    static func prepare(_ app: NSRunningApplication?) {
        guard let pid = app?.processIdentifier else { return }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        enableWebAccessibility(axApp)
    }

    private static func readOnce(allowCopy: Bool) -> Selection? {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "Unknown"
        guard let pid = app?.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        enableWebAccessibility(axApp)

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.3)
        let focused: AXUIElement? = attribute(axApp, kAXFocusedUIElementAttribute)
            ?? attribute(systemWide, kAXFocusedUIElementAttribute)
        if focused == nil { singeLog.notice("no focused element in \(appName)") }
        if let el = focused, ProcessInfo.processInfo.environment["SINGE_FORCE_COPY"] == nil {
            if let sel = fromTextMarkers(el, appName: appName) {
                singeLog.notice("selection via text markers in \(appName): \(sel.text.count) chars, rect \(sel.rect != nil)")
                return verified(sel)
            }
            if let sel = fromRange(el, appName: appName) {
                singeLog.notice("selection via AX range in \(appName): \(sel.text.count) chars, rect \(sel.rect != nil)")
                return sel
            }
            // Web content: the focused element may be a container; try its web area.
            var node: AXUIElement? = el
            for _ in 0..<6 {
                guard let n = node, let parent: AXUIElement = attribute(n, kAXParentAttribute) else { break }
                if let sel = fromTextMarkers(parent, appName: appName) {
                    singeLog.notice("selection via parent text markers in \(appName)")
                    return verified(sel)
                }
                node = parent
            }
        }
        // Chrome often reports no focused element for a page; find its web area instead.
        if ProcessInfo.processInfo.environment["SINGE_FORCE_COPY"] == nil {
            let window: AXUIElement? = attribute(axApp, kAXFocusedWindowAttribute) ?? attribute(axApp, kAXMainWindowAttribute)
            let web = window.flatMap(findWebArea)
            if let web, let sel = fromTextMarkers(web, appName: appName) {
                singeLog.notice("selection via web area in \(appName): \(sel.text.count) chars, rect \(sel.rect != nil)")
                return verified(sel)
            }
            singeLog.notice("web area search in \(appName): window \(window != nil), web area \(web != nil)")
        }
        let forceCopy = ProcessInfo.processInfo.environment["SINGE_FORCE_COPY"] != nil
        if !allowCopy && !forceCopy { return nil }
        if let text = copySelection(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            singeLog.notice("selection via ⌘C in \(appName): \(text.count) chars")
            return Selection(text: text, rect: caretRect(focused), font: nil, appName: appName)
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
        return Selection(text: text, rect: rect, font: font, appName: appName)
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
        return Selection(text: text, rect: rect, font: font, appName: appName)
    }

    /// Chrome and Electron build their accessibility tree only when asked.
    private static func enableWebAccessibility(_ axApp: AXUIElement) {
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
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

    /// Breadth-first search for the page's AXWebArea, a few levels deep.
    private static func findWebArea(in root: AXUIElement) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty && visited < 400 {
            let (el, depth) = queue.removeFirst()
            visited += 1
            if (attribute(el, kAXRoleAttribute) as String?) == "AXWebArea" { return el }
            guard depth < 10, let kids: [AXUIElement] = attribute(el, kAXChildrenAttribute) else { continue }
            queue.append(contentsOf: kids.map { ($0, depth + 1) })
        }
        return nil
    }

    /// Web pages can misreport their selection: text inside an aria-hidden section is missing
    /// from the accessibility tree, so the browser reports the nearest accessible text instead
    /// (on sorph.me, selecting "Get Sorph" reported the footer). When the reported selection
    /// looks implausible (no position, a huge area, or far from the pointer you just selected
    /// with), confirm it with a copy; if the two disagree, the copy is the truth.
    private static func verified(_ sel: Selection) -> Selection {
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
        return Selection(text: copied, rect: nil, font: nil, appName: sel.appName)
    }

    /// Marks Singe's own synthetic ⌘C so the hold monitor ignores it.
    static let syntheticTag: Int64 = 0x53494E4745   // "SINGE"

    /// Where the text cursor is, when the app tells us; used to place the popover after ⌘C.
    private static func caretRect(_ el: AXUIElement?) -> CGRect? {
        guard let el, let range: AXValue = attribute(el, kAXSelectedTextRangeAttribute) else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                         range, &bounds) == .success,
              let b = bounds, CFGetTypeID(b) == AXValueGetTypeID() else { return nil }
        var r = CGRect.zero
        guard AXValueGetValue(b as! AXValue, .cgRect, &r), r.width > 1, r.height > 1 else { return nil }
        return flip(r)
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
