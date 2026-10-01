import AppKit
import ApplicationServices

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
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "Unknown"
        guard let pid = app?.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        enableWebAccessibility(axApp)

        if let el: AXUIElement = attribute(axApp, kAXFocusedUIElementAttribute) {
            if let sel = fromTextMarkers(el, appName: appName) ?? fromRange(el, appName: appName) {
                return sel
            }
            // Web content: the focused element may be a container; try its web area.
            var node: AXUIElement? = el
            for _ in 0..<6 {
                guard let n = node, let parent: AXUIElement = attribute(n, kAXParentAttribute) else { break }
                if let sel = fromTextMarkers(parent, appName: appName) { return sel }
                node = parent
            }
        }
        if let text = copySelection(), !text.isEmpty {
            return Selection(text: text, rect: nil, font: nil, appName: appName)
        }
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
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)   // C
        let up = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand            // ⌘ only, even though ⌃ is physically held
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        let deadline = Date().addingTimeInterval(0.25)
        while pb.changeCount == before && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
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
