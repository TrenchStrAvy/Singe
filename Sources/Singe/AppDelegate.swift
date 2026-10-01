import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private let appState = AppState()
    private var controller: SingeController!
    private var statusItem: NSStatusItem!
    private let menuPopover = NSPopover()
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        controller = SingeController(store: store)
        appState.onHoldDelay = { [weak self] in self?.controller.setHoldDelay($0) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Icons.menuBar()
            button.toolTip = "Singe: highlight a term and hold Left ⌃"
            button.target = self
            button.action = #selector(toggleMenu)
        }
        menuPopover.behavior = .transient
        menuPopover.contentViewController = NSHostingController(rootView: MenuView(
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
        startWhenTrusted(prompt: true)
    }

    /// The Control-key listener needs Accessibility access. Ask once, then keep checking
    /// quietly so Singe starts working the moment it is granted.
    private func startWhenTrusted(prompt: Bool) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        appState.trusted = trusted
        if trusted && controller.monitor.start() {
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

    @objc private func toggleMenu() {
        guard let button = statusItem.button else { return }
        if menuPopover.isShown {
            menuPopover.performClose(nil)
        } else {
            store.refresh()
            NSApp.activate(ignoringOtherApps: true)
            menuPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func export() {
        menuPopover.performClose(nil)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Singe Glossary.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.message = "Save your Singed terms as Markdown (drop it into your Obsidian vault)."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.markdown().write(to: url, atomically: true, encoding: .utf8)
    }
}
