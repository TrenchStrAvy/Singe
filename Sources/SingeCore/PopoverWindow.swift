import AppKit
import SwiftUI

/// Hosting view that answers the first click even though Singe never becomes active,
/// so the star and the meanings work while you are still holding Control.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The native-looking popover panel: system popover material, clipped to a
/// rounded rectangle with an arrow pointing at the term.
final class PopoverWindow: NSPanel {
    let model = LookupModel()
    private let effect = NSVisualEffectView()
    private var hosting: FirstClickHostingView<PopoverView>!

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 360, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false

        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        hosting = FirstClickHostingView(rootView: PopoverView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        effect.addSubview(hosting)
        contentView = effect
    }

    override var canBecomeKey: Bool { model.pinned }

    /// Lays the popover out above the term (or below when there is no room) and points
    /// the arrow at the term's centre. `anchor` is in AppKit screen coordinates.
    func present(anchor: CGRect) {
        layout(anchor: anchor)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            animator().alphaValue = 1
        }
    }

    private var lastAnchor: CGRect = .zero

    /// Re-run after the content changes height (results arriving, a meaning expanding).
    func relayout() {
        guard isVisible else { return }
        layout(anchor: lastAnchor)
    }

    /// The SwiftUI content as an image (for `Singe --demo`).
    func contentSnapshot() -> NSBitmapImageRep? {
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    private func layout(anchor: CGRect) {
        lastAnchor = anchor
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap: CGFloat = 6
        hosting.invalidateIntrinsicContentSize()
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.height > 0 else { return }
        let above = anchor.maxY + gap + size.height <= visible.maxY
        model.arrowUp = !above
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = above ? anchor.maxY + gap : anchor.minY - gap - size.height
        model.arrowX = anchor.midX - x
        let frame = CGRect(x: x, y: max(visible.minY, y), width: size.width, height: size.height)
        setFrame(frame, display: true)
        hosting.frame = CGRect(origin: .zero, size: size)
        effect.maskImage = Self.mask(size: size, arrowX: model.arrowX, arrowUp: model.arrowUp)
        invalidateShadow()
    }

    private static func mask(size: CGSize, arrowX: CGFloat, arrowUp: Bool) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            let path = PopoverShape(arrowX: arrowX, arrowUp: arrowUp).path(in: rect)
            NSColor.black.setFill()
            let ns = NSBezierPath()
            path.forEach { el in
                switch el {
                case .move(let p): ns.move(to: p)
                case .line(let p): ns.line(to: p)
                case .quadCurve(let p, let c): ns.curve(to: p, controlPoint1: c, controlPoint2: c)
                case .curve(let p, let c1, let c2): ns.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                case .closeSubpath: ns.close()
                }
            }
            ns.fill()
            return true
        }
    }

    func dismiss() {
        model.pinned = false
        orderOut(nil)
    }
}
