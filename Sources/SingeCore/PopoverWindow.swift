import AppKit
import SwiftUI

/// Hosting view that answers the first click even though Singe never becomes active,
/// so the star and the meanings work while you are still holding Control.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A view whose layer is masked to the popover outline. The mask is a nine-slice image
/// (corners and arrow fixed, middle stretched), so it follows the window while it animates.
private class ShapedView: NSView {
    let shapeMask = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.mask = shapeMask
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.frame = bounds
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.frame = bounds
        CATransaction.commit()
    }
}

/// The rim: the highlight's own glass, drawn only along the outline. Never takes clicks.
private final class RimView: ShapedView {
    let glass = GlassView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        glass.autoresizingMask = [.width, .height]
        glass.dark = true
        glass.calm = 0.8
        glass.radius = PopoverShape.radius
        glass.edge = 16                   // the shader skips the inside; only the ring is shown
        glass.fps = 30
        addSubview(glass)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The glass behind Singe's panels, variant B of mockups/popover-refresh: the system blur,
/// 87% white over it, and a 1.5 pt rim of the highlight's glass on top, all clipped to a
/// rounded rectangle with an arrow. Content goes between the white and the rim.
final class GlassChrome: NSView {
    /// Picked with the sliders in the mock-up.
    static let whiteness: CGFloat = 0.87
    static let rimWidth: CGFloat = 1.5

    private let effect = NSVisualEffectView()
    private let fill = ShapedView()
    private let rim = RimView()
    private var maskKey = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        fill.layer?.backgroundColor = NSColor(white: 1, alpha: Self.whiteness).cgColor
        for v in [effect, fill, rim] as [NSView] {
            v.frame = bounds
            v.autoresizingMask = [.width, .height]
            addSubview(v)
        }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Adds the panel's content above the white and below the rim.
    func install(_ content: NSView) {
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content, positioned: .below, relativeTo: rim)
    }

    func start() { rim.glass.stir() }
    func stop() { rim.glass.stop() }

    /// Redraws the outline masks when the width or the arrow changes; height changes are free.
    func shape(width: CGFloat, arrowX: CGFloat, arrowUp: Bool, scale: CGFloat) {
        let key = "\(width)|\(arrowX)|\(arrowUp)|\(scale)"
        guard key != maskKey else { return }
        maskKey = key
        let cap = PopoverShape.radius + PopoverShape.arrow + 2
        let h = cap * 2 + 2
        let shape = PopoverShape(arrowX: arrowX, arrowUp: arrowUp)
        let inset = Self.rimWidth / 2
        // same caps above and below, so the stretch band is the middle row whichever way the image is read
        let centre = CGRect(x: 0, y: cap / h, width: 1, height: 2 / h)

        if let solid = Self.image(width: width, height: h, scale: scale, draw: { ctx in
            ctx.addPath(shape.path(in: CGRect(x: 0, y: 0, width: width, height: h)).cgPath)
            ctx.fillPath()
        }) {
            let ns = NSImage(cgImage: solid, size: CGSize(width: width, height: h))
            ns.capInsets = NSEdgeInsets(top: cap, left: width / 2 - 1, bottom: cap, right: width / 2 - 1)
            ns.resizingMode = .stretch
            effect.maskImage = ns
            fill.shapeMask.contents = solid
            fill.shapeMask.contentsScale = scale
            fill.shapeMask.contentsCenter = centre
        }
        if let ring = Self.image(width: width, height: h, scale: scale, draw: { ctx in
            let r = CGRect(x: inset, y: inset, width: width - inset * 2, height: h - inset * 2)
            ctx.addPath(PopoverShape(arrowX: arrowX - inset, arrowUp: arrowUp).path(in: r).cgPath)
            ctx.setLineWidth(Self.rimWidth)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        }) {
            rim.shapeMask.contents = ring
            rim.shapeMask.contentsScale = scale
            rim.shapeMask.contentsCenter = centre
        }
    }

    /// Draws in top-left-origin points (like SwiftUI shapes) into an upright image.
    private static func image(width: CGFloat, height: CGFloat, scale: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
        let w = Int(ceil(width * scale)), h = Int(ceil(height * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)
        draw(ctx)
        return ctx.makeImage()
    }
}

/// The lookup popover: the glass chrome with the meanings, pointing at the term.
final class PopoverWindow: NSPanel {
    let model = LookupModel()
    private let chrome = GlassChrome()
    private var hosting: FirstClickHostingView<AnyView>!

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: PopoverView.width, height: 200),
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
        appearance = NSAppearance(named: .aqua)     // white glass in light and dark mode alike

        // the content keeps to the arrow's side while the window grows or shrinks around it
        hosting = FirstClickHostingView(rootView: AnyView(PopoverAnchored(model: model)))
        hosting.sizingOptions = []
        chrome.install(hosting)
        contentView = chrome
    }

    override var canBecomeKey: Bool { model.pinned }

    /// Lays the popover out above the term (or below when there is no room) and points
    /// the arrow at the term's centre. `anchor` is in AppKit screen coordinates.
    func present(anchor: CGRect) {
        layout(anchor: anchor, animated: false)
        alphaValue = 0
        orderFrontRegardless()
        chrome.start()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            animator().alphaValue = 1
        }
    }

    private var lastAnchor: CGRect = .zero

    /// Re-run after the content changes height (results arriving, a meaning expanding).
    /// The window flows to its new size on the same curve as the content.
    func relayout() {
        guard isVisible else { return }
        layout(anchor: lastAnchor, animated: true)
    }

    /// The SwiftUI content as an image (for `Singe --demo`).
    func contentSnapshot() -> NSBitmapImageRep? {
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
    }

    private func layout(anchor: CGRect, animated: Bool) {
        lastAnchor = anchor
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap: CGFloat = 6
        let size = measure()
        guard size.height > 0 else { return }
        let above = anchor.maxY + gap + size.height <= visible.maxY
        if model.arrowUp == above { model.arrowUp = !above }
        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = above ? anchor.maxY + gap : anchor.minY - gap - size.height
        let arrowX = (anchor.midX - x).rounded()
        if model.arrowX != arrowX { model.arrowX = arrowX }
        let frame = CGRect(x: x, y: max(visible.minY, y), width: size.width, height: size.height).integral
        chrome.shape(width: frame.width, arrowX: arrowX, arrowUp: model.arrowUp, scale: screen.backingScaleFactor)

        if animated && frame != self.frame {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.42
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.9, 0.25, 1)
                animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in self?.invalidateShadow() }
        } else {
            setFrame(frame, display: true)
            chrome.frame = CGRect(origin: .zero, size: frame.size)
            invalidateShadow()
        }
    }

    /// The content's natural size, measured off-window so the live view is never squeezed.
    private lazy var measurer = NSHostingController(rootView: PopoverView(model: model))

    private func measure() -> CGSize {
        let s = measurer.sizeThatFits(in: CGSize(width: PopoverView.width, height: 4000))
        return CGSize(width: PopoverView.width, height: ceil(s.height))
    }

    func dismiss() {
        model.pinned = false
        model.saving = nil
        chrome.stop()
        orderOut(nil)
    }
}

/// The menu bar panel in the same glass, hanging from the Singe icon.
final class MenuPanel: NSPanel {
    private let chrome = GlassChrome()
    private let hosting: NSHostingView<AnyView>
    private var monitor: Any?
    static let width: CGFloat = 360

    init<V: View>(content: V) {
        hosting = NSHostingView(rootView: AnyView(content.frame(width: Self.width).padding(.top, PopoverShape.arrow)
            .environment(\.colorScheme, .light)))
        super.init(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 500),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .aqua)
        chrome.install(hosting)
        contentView = chrome
    }

    override var canBecomeKey: Bool { true }     // the search field

    /// Opens under the status item button, arrow on its centre.
    func show(under button: NSStatusBarButton) {
        guard let bw = button.window else { return }
        show(under: bw.convertToScreen(button.convert(button.bounds, to: nil)), on: bw.screen)
    }

    /// `b` is the icon's rect in screen coordinates.
    func show(under b: CGRect, on screen: NSScreen?) {
        let screen = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let size = CGSize(width: Self.width, height: ceil(hosting.fittingSize.height))
        var x = (b.midX - size.width / 2).rounded()
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        let frame = CGRect(x: x, y: b.minY - 4 - size.height, width: size.width, height: size.height)
        chrome.shape(width: size.width, arrowX: (b.midX - x).rounded(), arrowUp: true, scale: screen.backingScaleFactor)
        setFrame(frame, display: true)
        chrome.frame = CGRect(origin: .zero, size: size)
        invalidateShadow()
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        chrome.start()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.14; animator().alphaValue = 1 }
        // close on a click anywhere else, like the system popover did
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    /// When it last closed: a click on the Singe icon closes the panel first, and must not reopen it.
    private(set) var closedAt = Date.distantPast

    override func close() {
        if isVisible { closedAt = Date() }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        chrome.stop()
        orderOut(nil)
    }
}

/// The popover content pinned to the arrow's edge of the window.
private struct PopoverAnchored: View {
    @ObservedObject var model: LookupModel
    var body: some View {
        PopoverView(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.arrowUp ? .top : .bottom)
    }
}
