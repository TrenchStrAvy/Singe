import AppKit
import CoreGraphics

/// Watches for Left Control held on its own. Pressing any other key or clicking
/// outside Singe during the hold cancels it, so ⌃-shortcuts and ⌃-click (right-click)
/// keep working everywhere. While Singe is open, a ⌃-click inside its windows has
/// the Control flag removed so it acts as a plain click.
final class HoldKeyMonitor {
    var holdDelay: TimeInterval = 0.35
    var onHold: (() -> Void)?
    var onRelease: (() -> Void)?
    var onEscape: (() -> Bool)?                      // return true to swallow
    var onClick: ((CGPoint) -> Void)?                // AppKit coordinates, any click while open
    var isInsideSinge: ((CGPoint) -> Bool)?          // AppKit coordinates
    var isOpen: (() -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: DispatchWorkItem?
    private var leftControlDown = false

    private static let leftControl: Int64 = 59
    private static let escape: Int64 = 53

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.otherMouseDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                          callback: { _, type, event, refcon in
            let me = Unmanaged<HoldKeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type, event)
        }, userInfo: refcon) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            if code == Self.leftControl {
                // each Left-Control flagsChanged toggles its state
                if !leftControlDown && flags.contains(.maskControl) {
                    leftControlDown = true
                    let others: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift]
                    if flags.intersection(others).isEmpty { schedule() }
                } else if leftControlDown {
                    leftControlDown = false
                    cancel()
                    DispatchQueue.main.async { self.onRelease?() }
                }
            } else if pending != nil {
                cancel()                                  // ⌃ with another modifier: a shortcut
            }

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if pending != nil { cancel() }                // ⌃ + key: a shortcut, not Singe
            if code == Self.escape, isOpen?() == true {
                if onEscape?() == true { return nil }     // the tap runs on the main run loop
            }

        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp:
            let p = Self.appKitPoint(event.location)
            let inside = isInsideSinge?(p) ?? false
            if pending != nil && !inside && type != .leftMouseUp { cancel() }   // ⌃-click elsewhere is a right-click
            if isOpen?() == true {
                if inside && event.flags.contains(.maskControl) {
                    event.flags.remove(.maskControl)      // a plain click on Singe's buttons
                }
                if type == .leftMouseDown || type == .rightMouseDown {
                    DispatchQueue.main.async { self.onClick?(p) }
                }
            }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func schedule() {
        cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.leftControlDown else { return }
            self.pending = nil
            self.onHold?()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: work)
    }

    private func cancel() {
        pending?.cancel()
        pending = nil
    }

    private static func appKitPoint(_ p: CGPoint) -> CGPoint {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: h - p.y)
    }
}
