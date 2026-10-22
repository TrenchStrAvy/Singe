import AppKit

/// Checks that Singe can read the selection, and place the highlight, in real apps
/// without taking over the screen: apps are launched hidden in the background, the term is
/// selected through Accessibility (or by the page itself), and Singe reads each app by its
/// process ID. No clicks, no key presses, no ⌘C, no clipboard; your frontmost app keeps focus.
///
///     Singe --selftest                    apps not already running
///     Singe --selftest --include-running  also open a test window, behind yours, in apps you
///                                         have open (Safari …); it is closed afterwards
///     Singe --selftest --visible          also try Chromium/Electron apps behind your windows
///                                         (unreliable there: they want to be in front)
///     Singe --selftest --only textedit,"google chrome"
///     Singe --probe Safari                read what is selected in a running app, in the background
enum SelfTest {
    static let term = "Kerberos"
    static let sentence = "Configure \(term) on the domain controller before RADIUS."

    struct Case {
        let name: String
        let bundle: String
        let file: String            // fixture extension
        /// Launch arguments for a separate instance with its own profile, so the test never
        /// touches your windows ({profile} and {url} are filled in). nil: open the file normally.
        var isolated: [String]? = nil
        /// Chromium and Electron build their page tree reliably only for the window in front:
        /// hidden, minimized or covered by yours, they often report nothing. Test these where
        /// they can be in front (a VM, docs/TESTING.md); --visible tries anyway, behind yours.
        var needsWindow = false
    }

    static let cases: [Case] = [
        Case(name: "TextEdit", bundle: "com.apple.TextEdit", file: "txt"),
        Case(name: "Safari", bundle: "com.apple.Safari", file: "html"),
        Case(name: "Google Chrome", bundle: "com.google.Chrome", file: "html", isolated: ["--user-data-dir={profile}", "--no-first-run", "--no-default-browser-check", "{url}"], needsWindow: true),
        Case(name: "Microsoft Edge", bundle: "com.microsoft.edgemac", file: "html", isolated: ["--user-data-dir={profile}", "--no-first-run", "--no-default-browser-check", "{url}"], needsWindow: true),
        Case(name: "Brave Browser", bundle: "com.brave.Browser", file: "html", isolated: ["--user-data-dir={profile}", "--no-first-run", "--no-default-browser-check", "{url}"], needsWindow: true),
        Case(name: "Firefox", bundle: "org.mozilla.firefox", file: "html",
             isolated: ["-profile", "{profile}", "-no-remote", "-new-instance", "{url}"], needsWindow: true),
        Case(name: "Visual Studio Code", bundle: "com.microsoft.VSCode", file: "md", needsWindow: true),
        Case(name: "Cursor", bundle: "com.todesktop.230313mzl4w4u92", file: "md", needsWindow: true),
        Case(name: "Xcode", bundle: "com.apple.dt.Xcode", file: "swift"),
        Case(name: "Preview", bundle: "com.apple.Preview", file: "pdf"),
        Case(name: "Pages", bundle: "com.apple.iWork.Pages", file: "rtf"),
    ]

    struct Result {
        let app: String
        let outcome: String
        let detail: String
    }

    // MARK: --selftest

    static func run(includeRunning: Bool, visible: Bool, only: Set<String>? = nil) -> Int32 {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("singe-selftest-\(getpid())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        writeFixtures(in: dir)

        print("Singe self-test: \"\(term)\" selected in each app, read in the background\n")
        var results: [Result] = []
        for c in cases where only.map({ $0.contains(c.name.lowercased()) }) ?? true {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: c.bundle) else { continue }
            if c.needsWindow && !visible {
                results.append(Result(app: c.name, outcome: "skipped", detail: "must be the front app to build its page tree: test in a VM (docs/TESTING.md)"))
                continue
            }
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: c.bundle).isEmpty
            if running && c.isolated == nil && !includeRunning {
                results.append(Result(app: c.name, outcome: "skipped", detail: "open in your session (--include-running tests it behind your windows)"))
                continue
            }
            let r = test(c, appURL: url, fixture: dir.appendingPathComponent("term.\(c.file)"), dir: dir, wasRunning: running)
            print(String(format: "  %-20@ %-9@ %@", c.name as NSString, r.outcome as NSString, r.detail as NSString))
            results.append(r)
        }
        for r in results where r.outcome == "skipped" {
            print(String(format: "  %-20@ %-9@ %@", r.app as NSString, r.outcome as NSString, r.detail as NSString))
        }
        let failed = results.filter { $0.outcome == "FAIL" }.count
        let passed = results.filter { $0.outcome == "highlight" }.count
        print("\n\(passed) highlighted, \(results.filter { $0.outcome == "text only" }.count) text only, \(failed) failed, \(results.filter { $0.outcome == "skipped" || $0.outcome == "n/a" }.count) skipped")
        return failed == 0 ? 0 : 1
    }

    private static func test(_ c: Case, appURL: URL, fixture: URL, dir: URL, wasRunning: Bool) -> Result {
        // launch hidden and in the background; a separate instance for isolated browsers
        let profile = dir.appendingPathComponent("profile-\(c.bundle)")
        var args = ["-g"]
        if !wasRunning && !c.needsWindow { args.append("-j") }   // hidden; only for apps we start
        if let template = c.isolated {
            try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            // Firefox: no welcome pages in a fresh profile
            try? """
                user_pref("browser.aboutwelcome.enabled", false);
                user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
                user_pref("browser.startup.homepage_override.mstone", "ignore");
                user_pref("browser.shell.checkDefaultBrowser", false);
                """.write(to: profile.appendingPathComponent("user.js"), atomically: true, encoding: .utf8)
            args += ["-n", "-a", appURL.path, "--args"] + template.map {
                $0.replacingOccurrences(of: "{profile}", with: profile.path)
                  .replacingOccurrences(of: "{url}", with: fixture.absoluteString)
            }
        } else {
            args += ["-a", appURL.path, fixture.path]
        }
        let before = Set(NSRunningApplication.runningApplications(withBundleIdentifier: c.bundle).map(\.processIdentifier))
        shell("/usr/bin/open", args)

        // the instance under test: the new process, or the one already running
        var app: NSRunningApplication?
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let all = NSRunningApplication.runningApplications(withBundleIdentifier: c.bundle)
            app = c.isolated != nil || !wasRunning ? all.first { !before.contains($0.processIdentifier) } : all.first
            if let app, windowCount(app) > 0 { break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        guard let app else { return Result(app: c.name, outcome: "n/a", detail: "did not start") }
        defer { cleanUp(app, c: c, fixture: fixture, wasRunning: wasRunning, profile: profile) }
        guard windowCount(app) > 0 else { return Result(app: c.name, outcome: "n/a", detail: "no window to test (needs a first-run setup?)") }

        SelectionReader.prepare(app)
        Thread.sleep(forTimeInterval: c.file == "html" ? 2.5 : 1)   // pages select the term themselves
        if c.file != "html" && !selectTerm(in: app) {
            return Result(app: c.name, outcome: "n/a", detail: "harness could not select the term in this app")
        }
        var sel = SelectionReader.read(app: app)
        if SingeController.highlightRect(for: sel ?? Selection(text: "", rect: nil, font: nil, appName: "")) == nil {
            // an app switching on its full accessibility mode can take a few seconds the first
            // time; the second lookup is the one that counts
            Thread.sleep(forTimeInterval: 5)
            sel = SelectionReader.read(app: app) ?? sel
        }
        return judge(c.name, sel, app: app)
    }

    /// The verdict for one app: the term read back, and a position that lies in its window.
    static func judge(_ name: String, _ sel: Selection?, app: NSRunningApplication) -> Result {
        guard let sel else { return Result(app: name, outcome: "FAIL", detail: "nothing read") }
        let text = TermIndex.normalize(sel.text)
        guard text.lowercased().contains(term.lowercased()) else {
            return Result(app: name, outcome: "FAIL", detail: "read \"\(text.prefix(40))\" via \(sel.via)")
        }
        let deep = AppAccess.shared.needsDeep(app.bundleIdentifier) ? ", full accessibility mode" : ""
        guard let rect = SingeController.highlightRect(for: sel) else {
            return Result(app: name, outcome: "text only", detail: "via \(sel.via): no position from the app\(deep)")
        }
        let inWindow = windowFrames(app).contains { $0.insetBy(dx: -8, dy: -8).intersects(rect) }
        guard inWindow else {
            return Result(app: name, outcome: "FAIL", detail: "position \(rect) is outside the app's windows")
        }
        return Result(app: name, outcome: "highlight",
                      detail: "via \(sel.via), \(Int(rect.width))×\(Int(rect.height)) pt\(deep)")
    }

    // MARK: --probe

    static func probe(_ target: String) -> Int32 {
        let apps = NSWorkspace.shared.runningApplications
        let app = Int32(target).flatMap { pid in apps.first { $0.processIdentifier == pid } }
            ?? apps.first { $0.bundleIdentifier == target }
            ?? apps.first { $0.localizedName?.caseInsensitiveCompare(target) == .orderedSame }
        guard let app else { print("no running app matches \"\(target)\""); return 1 }
        SelectionReader.prepare(app)
        let sel = SelectionReader.read(app: app)
        print("app: \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?"), pid \(app.processIdentifier))")
        guard let sel else { print("nothing read"); return 1 }
        print("text: \(sel.text)\nvia: \(sel.via)\nrect: \(sel.rect.map { "\($0)" } ?? "none")")
        print("highlight: \(SingeController.highlightRect(for: sel) != nil ? "yes" : "no")"
              + (AppAccess.shared.needsDeep(app.bundleIdentifier) ? " (full accessibility mode)" : ""))
        return 0
    }

    // MARK: fixtures

    private static func writeFixtures(in dir: URL) {
        func write(_ name: String, _ text: String) {
            try? text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        write("term.txt", sentence)
        write("term.md", sentence)
        write("term.swift", "// \(sentence)\n")
        write("term.rtf", "{\\rtf1\\ansi {\\fonttbl\\f0 Helvetica;}\\f0\\fs28 \(sentence)}")
        // the page selects the term itself, so nothing has to click into it
        write("term.html", """
            <html><body style="font:18px -apple-system,sans-serif;padding:60px">
            <p>Configure <span id="t">\(term)</span> on the domain controller before RADIUS.</p>
            <script>const r = document.createRange(); r.selectNodeContents(document.getElementById('t'));
            getSelection().removeAllRanges(); getSelection().addRange(r);</script></body></html>
            """)
        // a one-page PDF with the sentence as real text
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 200)
        if let consumer = CGDataConsumer(data: data), let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) {
            ctx.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: sentence,
                attributes: [.font: NSFont.systemFont(ofSize: 18)]))
            ctx.textPosition = CGPoint(x: 40, y: 120)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            data.write(to: dir.appendingPathComponent("term.pdf"), atomically: true)
        }
    }

    // MARK: Accessibility helpers

    /// Selects the term in the first text element that contains it (a text view, an editor).
    private static func selectTerm(in app: NSRunningApplication) -> Bool {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.5)
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            for el in elements(of: ax, limit: 1500) {
                guard let value: String = attr(el, kAXValueAttribute),
                      let r = value.range(of: term) else { continue }
                var range = CFRange(location: value.utf16.distance(from: value.startIndex, to: r.lowerBound), length: term.utf16.count)
                guard let v = AXValueCreate(.cfRange, &range),
                      AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, v) == .success else { continue }
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private static func elements(of ax: AXUIElement, limit: Int) -> [AXUIElement] {
        var out: [AXUIElement] = []
        var queue: [AXUIElement] = attr(ax, kAXWindowsAttribute) ?? []
        while !queue.isEmpty && out.count < limit {
            let el = queue.removeFirst()
            out.append(el)
            if let kids: [AXUIElement] = attr(el, kAXChildrenAttribute) { queue += kids }
        }
        return out
    }

    private static func windowCount(_ app: NSRunningApplication) -> Int {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.5)
        return (attr(ax, kAXWindowsAttribute) as [AXUIElement]?)?.count ?? 0
    }

    /// The app's windows in AppKit screen coordinates.
    private static func windowFrames(_ app: NSRunningApplication) -> [CGRect] {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        let h = NSScreen.screens.first?.frame.height ?? 0
        return ((attr(ax, kAXWindowsAttribute) as [AXUIElement]?) ?? []).compactMap { w in
            guard let p: AXValue = attr(w, kAXPositionAttribute), let s: AXValue = attr(w, kAXSizeAttribute) else { return nil }
            var o = CGPoint.zero, z = CGSize.zero
            AXValueGetValue(p, .cgPoint, &o); AXValueGetValue(s, .cgSize, &z)
            return CGRect(x: o.x, y: h - o.y - z.height, width: z.width, height: z.height)
        }
    }

    /// Quits what the test started; in an app you had open, closes only the test window.
    private static func cleanUp(_ app: NSRunningApplication, c: Case, fixture: URL, wasRunning: Bool, profile: URL) {
        if c.isolated != nil || !wasRunning {
            app.terminate()
            let deadline = Date().addingTimeInterval(3)
            while !app.isTerminated && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            if !app.isTerminated { app.forceTerminate() }
            return
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        for w in (attr(ax, kAXWindowsAttribute) as [AXUIElement]?) ?? [] {
            let title: String = attr(w, kAXTitleAttribute) ?? ""
            let doc: String = attr(w, kAXDocumentAttribute) ?? ""
            guard title.contains("term.") || doc.contains(fixture.lastPathComponent),
                  let close: AXUIElement = attr(w, kAXCloseButtonAttribute) else { continue }
            AXUIElementPerformAction(close, kAXPressAction as CFString)
        }
    }

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    @discardableResult
    private static func shell(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
