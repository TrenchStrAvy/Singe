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
        let ranked = Ranker.rank(TermIndex().candidates(for: term), profile: store.profile())
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
        Thread.sleep(forTimeInterval: wait)
        if let sel = SelectionReader.read() {
            print("app: \(sel.appName)\ntext: \(sel.text)\nrect: \(sel.rect.map { "\($0)" } ?? "none")\nfont: \(sel.font?.fontName ?? "none")")
        } else {
            print("nothing selected")
        }
        exit(0)
    }

    if let i = args.firstIndex(of: "--snapshot"), i + 2 < args.count {
        _ = NSApplication.shared
        Snapshot.render(to: args[i + 1], term: args[i + 2], dark: args.contains("--dark"))
        exit(0)
    }

    // Singe --demo "TERM": open the real highlight + popover over a fixed spot, then report
    // the popover's size and save its content to /tmp/singe-demo.png.
    if let i = args.firstIndex(of: "--demo"), i + 1 < args.count {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = SingeController(store: Store(path: NSTemporaryDirectory() + "singe-demo.sqlite"))
        let rect = CGRect(x: 600, y: 400, width: 70, height: 22)
        DispatchQueue.main.async {
            controller.open(Selection(text: args[i + 1], rect: rect, font: nil, appName: "Demo"))
            print("t=0.0 popover \(controller.popover.frame.size)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let m = controller.popover.model
            print("t=1.5 popover \(controller.popover.frame.size), senses \(m.senses.count), loading \(m.loading)")
            if let rep = controller.popover.contentSnapshot() {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/singe-demo.png"))
            }
            exit(0)
        }
        app.run()
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    return 0
}
