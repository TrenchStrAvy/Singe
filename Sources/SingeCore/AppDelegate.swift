import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private let appState = AppState()
    private var controller: SingeController!
    private var statusItem: NSStatusItem!
    private var menuPanel: MenuPanel!
    private var trustTimer: Timer?

    private let splash = SplashWindow()

    func applicationDidFinishLaunching(_ note: Notification) {
        installMainMenu()
        // The Dock shows the current icon even when the launcher bundle (which keeps the
        // Accessibility permission) still carries an older .icns.
        if let icon = Icons.appIcon(px: 512) { NSApp.applicationIconImage = NSImage(cgImage: icon, size: NSSize(width: 512, height: 512)) }
        splash.present()
        splash.stage("warming the glass…", 0.25)
        controller = SingeController(store: store)
        appState.onHoldDelay = { [weak self] in self?.controller.setHoldDelay($0) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Icons.menuBar()
            button.toolTip = "Singe: highlight a term and hold Left ⌃"
            button.target = self
            button.action = #selector(toggleMenu)
        }
        menuPanel = MenuPanel(content: MenuView(
            store: store, app: appState,
            onExport: { [weak self] in self?.export() },
            onQuit: { NSApp.terminate(nil) }))

        // Like Sorph, start at login by default; the menu has the switch to turn it off.
        if !UserDefaults.standard.bool(forKey: "didFirstRun") {
            UserDefaults.standard.set(true, forKey: "didFirstRun")
            if Bundle.main.bundlePath.hasSuffix(".app") { appState.launchAtLogin = true }
        }
        if !controller.index.hasIndex {
            NSLog("Singe: term index not found; using the glossary, macOS Dictionary and the local model only")
        }
        loadStages()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: nil) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            DispatchQueue.global(qos: .utility).async { SelectionReader.prepare(app) }
        }
        DispatchQueue.global(qos: .utility).async { SelectionReader.prepare(NSWorkspace.shared.frontmostApplication) }
    }

    /// The splash stages: real work, in order, then ready (or what is still missing).
    private func loadStages() {
        let index = controller.index
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = GlassRenderer.shared.pipeline                       // compile the glass shader
            DispatchQueue.main.async { self?.splash.stage("opening the term index…", 0.5) }
            _ = index.candidates(for: "singe")                      // first query pages the index in
            DispatchQueue.main.async { self?.splash.stage("checking the local model…", 0.75) }
            let model = LocalModel.isAvailable()
            DispatchQueue.main.async {
                guard let self else { return }
                self.splash.stage("checking Accessibility…", 0.9)
                self.startWhenTrusted(prompt: true)
                let base = index.hasIndex ? "" : " (no term index)"
                if self.appState.trusted {
                    self.splash.finish("ready — highlight a term and hold Left ⌃" + base)
                } else {
                    self.splash.finish("turn on Singe in Settings → Accessibility" + base)
                    // take you straight to the switch
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
                if model { LocalModel.warmUp() }
            }
        }
    }

    /// The Control-key listener needs Accessibility access. Ask once, then keep checking
    /// quietly so Singe starts working the moment it is granted.
    private func startWhenTrusted(prompt: Bool) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        appState.trusted = trusted
        let listening = trusted && controller.monitor.start()
        writeStatus(trusted: trusted, listening: listening)
        if listening {
            trustTimer?.invalidate()
            trustTimer = nil
            return
        }
        if trustTimer == nil {
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.startWhenTrusted(prompt: false)
            }
        }
    }

    /// A small status file for troubleshooting: ~/Library/Application Support/Singe/status.json
    private func writeStatus(trusted: Bool, listening: Bool) {
        let status: [String: Any] = [
            "version": (try? String(contentsOf: Store.supportDir.appendingPathComponent("version"))
                .trimmingCharacters(in: .whitespacesAndNewlines)) ?? "dev",
            "pid": ProcessInfo.processInfo.processIdentifier,
            "accessibility": trusted,
            "listening": listening,
            "termIndex": controller.index.hasIndex,
            "updated": ISO8601DateFormatter().string(from: Date()),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Store.supportDir.appendingPathComponent("status.json"))
        }
    }

    // MARK: Dock

    /// Clicking the Dock icon opens the History panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !menuPanel.isVisible { toggleMenu() }
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "History & Lists", action: #selector(toggleMenu), keyEquivalent: "").target = self
        return menu
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "History & Lists", action: #selector(toggleMenu), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Singe", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Singe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }

    @objc private func toggleMenu() {
        guard let button = statusItem.button else { return }
        if menuPanel.isVisible {
            menuPanel.close()
        } else if menuPanel.closedAt.timeIntervalSinceNow < -0.3 {
            store.refresh()
            NSApp.activate(ignoringOtherApps: true)
            menuPanel.show(under: button)
        }
    }

    private func export() {
        menuPanel.close()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Singe Glossary.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.message = "Save your Singed terms as Markdown (drop it into your Obsidian vault)."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.markdown().write(to: url, atomically: true, encoding: .utf8)
    }
}
