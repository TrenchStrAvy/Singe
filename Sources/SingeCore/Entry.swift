import AppKit
import SwiftUI

// Entry point, called by the launcher (Sources/SingeLauncher) through dlopen.
// Command-line helpers (used by install.sh and for checking a build):
//   Singe --lookup "RTS/ITS"          print the ranked meanings
//   Singe --render-icon icon.png      render the app icon (1024 px)
//   Singe --snapshot out.png "TERM"   render the highlight + popover offscreen
/// The launcher stays the same across updates, so macOS keeps Singe's Accessibility
/// permission; everything else lives in this library and can change freely.
@_cdecl("singe_main")
public func singeMain() -> Int32 {
    let args = CommandLine.arguments

    if let i = args.firstIndex(of: "--lookup"), i + 1 < args.count {
        let term = args[i + 1]
        let store = Store()
        let index = TermIndex()
        let found = index.candidates(for: term, profile: store.profile())
        let phrase = term.contains(" ") && !index.knowsWhole(term)
        let ranked = phrase ? found : Ranker.rank(found, profile: store.profile(), query: term)
        if phrase { print("(phrase: shown by its parts; the local model adds a one-sentence explanation)") }
        print("Singe · \(term)")
        if ranked.isEmpty { print("  (no meaning in the local index)") }
        for (n, s) in ranked.prefix(6).enumerated() {
            print("  \(n + 1). \(s.name)  [\(s.label) · \(s.source.rawValue)]\n     \(s.gloss)")
        }
        exit(0)
    }

    if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
        _ = NSApplication.shared
        let size = args.count > i + 2 ? CGFloat(Double(args[i + 2]) ?? 1024) : 1024
        guard let img = Icons.appIcon(px: size), Icons.writePNG(img, to: args[i + 1]) else {
            FileHandle.standardError.write("icon render failed\n".data(using: .utf8)!)
            exit(1)
        }
        exit(0)
    }

    // Singe --read-selection 3: wait, then print what Singe reads as the selection.
    if let i = args.firstIndex(of: "--read-selection") {
        _ = NSApplication.shared
        let wait = i + 1 < args.count ? Double(args[i + 1]) ?? 2 : 2
        // spin the run loop so NSWorkspace reports the real frontmost app (it is stale otherwise)
        RunLoop.current.run(until: Date().addingTimeInterval(max(wait, 0.3)))
        if let sel = SelectionReader.read() {
            print("app: \(sel.appName)\ntext: \(sel.text)\nrect: \(sel.rect.map { "\($0)" } ?? "none")\nfont: \(sel.font?.fontName ?? "none")")
        } else {
            print("nothing selected")
        }
        exit(0)
    }

    // Singe --render-orb out.png [px]: Sorph's logo in Singe's glass (used by Sorph's icon script)
    if let i = args.firstIndex(of: "--render-orb"), i + 1 < args.count {
        _ = NSApplication.shared
        let px = args.count > i + 2 ? Int(args[i + 2]) ?? 1200 : 1200
        guard let img = GlassRenderer.shared.orbImage(pixels: px), Icons.writePNG(img, to: args[i + 1]) else { exit(1) }
        exit(0)
    }

    if let i = args.firstIndex(of: "--render-bar"), i + 1 < args.count {
        _ = NSApplication.shared
        guard let img = Icons.iconBar(width: 1520, height: 660), Icons.writePNG(img, to: args[i + 1]) else { exit(1) }
        exit(0)
    }

    if let i = args.firstIndex(of: "--snapshot"), i + 2 < args.count {
        _ = NSApplication.shared
        Snapshot.render(to: args[i + 1], term: args[i + 2], dark: args.contains("--dark"))
        exit(0)
    }

    // Singe --splash-demo: show the startup card and capture it to /tmp/singe-splash.png
    if args.contains("--splash-demo") {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let splash = SplashWindow()
        DispatchQueue.main.async {
            splash.present()
            splash.stage("opening the term index…", 0.55)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            let wid = CGWindowID(splash.windowNumber)
            if let shot = CGWindowListCreateImage(.null, .optionIncludingWindow, wid, [.boundsIgnoreFraming, .bestResolution]) {
                _ = Icons.writePNG(shot, to: "/tmp/singe-splash.png")
                print("splash capture: \(shot.width)x\(shot.height)")
            }
            exit(0)
        }
        app.run()
    }

    // Singe --menu-demo: open the menu bar panel under a fake icon, capture it, then open
    // the first collection and capture again (/tmp/singe-menu-*.png).
    if args.contains("--menu-demo") {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let store = Store(), state = AppState()
        state.trusted = true
        let panel = MenuPanel(content: MenuView(store: store, app: state, onExport: {}, onQuit: {}, startTab: .lists))
        func capture(_ name: String) {
            if let shot = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(panel.windowNumber),
                                                  [.boundsIgnoreFraming, .bestResolution]) {
                _ = Icons.writePNG(shot, to: "/tmp/singe-menu-\(name).png")
                print("menu \(name): \(panel.frame.size) → /tmp/singe-menu-\(name).png")
            }
        }
        DispatchQueue.main.async {
            let s = NSScreen.main!.frame
            panel.show(under: CGRect(x: s.midX, y: s.maxY - 30, width: 24, height: 22), on: NSScreen.main)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            capture("lists")
            NotificationCenter.default.post(name: MenuView.openFirstForDemo, object: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { capture("collection"); exit(0) }
        app.run()
    }

    // Singe --demo "TERM": open the real highlight + popover over a fixed spot, then report
    // the popover's size and save its content to /tmp/singe-demo.png.
    if let i = args.firstIndex(of: "--demo"), i + 1 < args.count {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = SingeController(store: Store(path: NSTemporaryDirectory() + "singe-demo.sqlite"))
        let word = args[i + 1] as NSString
    let w = word.size(withAttributes: [.font: NSFont.systemFont(ofSize: 18)]).width
    let rect = CGRect(x: 600, y: 400, width: ceil(w), height: 22)    // like a word on a page
        DispatchQueue.main.async {
            controller.open(Selection(text: args[i + 1], rect: rect, font: nil, appName: "Demo"))
            print("t=0.0 popover \(controller.popover.frame.size)")
        }
        let wait = Double(ProcessInfo.processInfo.environment["SINGE_DEMO_WAIT"] ?? "") ?? 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            let m = controller.popover.model
            print("t=1.5 popover \(controller.popover.frame.size), senses \(m.senses.count), loading \(m.loading)")
        let g = controller.highlight.glass
        var center = "none"
        if let img = g.currentImage, let data = img.dataProvider?.data, let p = CFDataGetBytePtr(data) {
            let o = (img.height / 2) * img.bytesPerRow + (img.width / 2) * 4
            center = "rgba \(p[o + 2]) \(p[o + 1]) \(p[o]) \(p[o + 3])"
        }
        print("glass: window visible \(controller.highlight.isVisible), alpha \(controller.highlight.alphaValue), frame \(g.frame), frames \(g.drawCount), image \(g.currentImage.map { "\($0.width)x\($0.height)" } ?? "none"), centre pixel \(center)")
        // what is really on screen: an app may capture its own windows without Screen Recording
        let wid = CGWindowID(controller.highlight.windowNumber)
        if let shot = CGWindowListCreateImage(.null, .optionIncludingWindow, wid, [.boundsIgnoreFraming, .bestResolution]) {
            _ = Icons.writePNG(shot, to: "/tmp/singe-glass.png")
            print("window capture: \(shot.width)x\(shot.height) → /tmp/singe-glass.png")
        }
        if let rep = controller.popover.contentSnapshot() {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/singe-demo.png"))
            }
            // the popover window as composited (glass, white, rim), then mid-way and after
            // switching to the second meaning, to check the window flows with its content
            func capture(_ name: String) {
                let pid = CGWindowID(controller.popover.windowNumber)
                if let shot = CGWindowListCreateImage(.null, .optionIncludingWindow, pid, [.boundsIgnoreFraming, .bestResolution]) {
                    _ = Icons.writePNG(shot, to: "/tmp/singe-popover-\(name).png")
                    print("popover \(name): \(controller.popover.frame.size) → /tmp/singe-popover-\(name).png")
                }
            }
            capture("open")
            guard m.senses.count > 1 else { exit(0) }
            let next = m.senses[1]
            withAnimation(PopoverView.flow) { m.selected = next.id }
            m.onSelect?(next)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { capture("mid") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                capture("switched")
                m.onCreate?(next, "Security+")
                withAnimation(PopoverView.flow) { m.saving = next.id }
                m.onSelect?(next)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { capture("save"); exit(0) }
        }
        app.run()
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)        // a Dock icon with the running dot
    app.run()
    return 0
}
