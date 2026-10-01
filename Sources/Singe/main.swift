import AppKit
import SwiftUI

// Command-line helpers (used by install.sh and for checking a build):
//   Singe --lookup "RTS/ITS"          print the ranked meanings
//   Singe --render-icon icon.png      render the app icon (1024 px)
//   Singe --snapshot out.png "TERM"   render the highlight + popover offscreen
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

if let i = args.firstIndex(of: "--snapshot"), i + 2 < args.count {
    _ = NSApplication.shared
    Snapshot.render(to: args[i + 1], term: args[i + 2], dark: args.contains("--dark"))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
