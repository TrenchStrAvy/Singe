import AppKit

/// Startup splash, the same as Sorph's: a title, a caption and a thin progress bar
/// floating in the middle of the screen while Singe loads, then a short "ready" and a fade.
/// White ink with a dark shadow so it reads on any wallpaper. Main thread only.
final class SplashWindow: NSWindow {
    private static let cardW: CGFloat = 320, cardH: CGFloat = 112, pad: CGFloat = 28
    private static let barW: CGFloat = 240, barH: CGFloat = 4

    private let view = SplashView()
    private let glass = GlassView(frame: .zero)
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var doneAt: CFTimeInterval?
    private var fadeStart: CFTimeInterval?

    init() {
        let rect = CGRect(x: 0, y: 0, width: Self.cardW + 2 * Self.pad, height: Self.cardH + 2 * Self.pad)
        super.init(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isReleasedWhenClosed = false
        view.frame = rect
        contentView = view
        // the Singe mark beside the title: a small live glass bar
        glass.frame = CGRect(x: 0, y: 0, width: 30, height: 13)
        glass.radius = 4
        view.addSubview(glass)
        if let screen = NSScreen.main {
            let f = screen.frame
            setFrameOrigin(CGPoint(x: f.midX - rect.width / 2, y: f.midY - rect.height / 2 + 40))
        }
    }

    func present() {
        alphaValue = 0
        orderFrontRegardless()
        glass.stir()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Updates the caption and the point the bar should move towards (0–1).
    func stage(_ caption: String, _ target: Double) {
        view.caption = caption
        view.target = max(view.target, target)
        view.needsDisplay = true
    }

    /// Fills the bar, holds briefly on the ready caption, fades out and closes.
    func finish(_ caption: String) {
        view.caption = caption
        view.target = 1
        doneAt = CACurrentMediaTime()
        view.needsDisplay = true
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - last)
        last = now
        let gap = view.target - view.progress
        if let done = doneAt {
            view.progress = min(1, view.progress + max(gap * 8, 1.2) * dt)
            if view.progress >= 1, now - done > 0.9, fadeStart == nil { fadeStart = now }
        } else {
            // ease towards the stage target, and creep so the bar never looks frozen
            view.progress += gap > 0 ? gap * min(1, 4 * dt) : 0.06 * dt * (1 - view.progress)
        }
        if let fade = fadeStart {
            let a = 1 - (now - fade) / 0.35
            if a <= 0 {
                timer?.invalidate()
                glass.stop()
                orderOut(nil)
                return
            }
            alphaValue = a
        } else {
            alphaValue = min(1, alphaValue + dt / 0.25)
        }
        let title = view.titleRect
        glass.frame.origin = CGPoint(x: title.minX - 38, y: title.midY - 6.5)
        view.needsDisplay = true
    }
}

private final class SplashView: NSView {
    var progress = 0.0
    var target = 0.08
    var caption = "starting…"

    private let ink = NSColor(white: 0.97, alpha: 1)
    private var titleAttrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: ink]
    }
    /// The title, offset right to leave room for the glass mark on its left.
    var titleRect: CGRect {
        let ts = ("Singe" as NSString).size(withAttributes: titleAttrs)
        return CGRect(x: 28 + (320 - ts.width) / 2 + 19, y: 28 + 112 - 22 - ts.height / 2 - 6, width: ts.width, height: ts.height)
    }

    override func draw(_ dirty: NSRect) {
        let W: CGFloat = 320, H: CGFloat = 112, pad: CGFloat = 28
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.7)
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = CGSize(width: 0, height: -2)
        shadow.set()

        ("Singe" as NSString).draw(at: titleRect.origin, withAttributes: titleAttrs)
        _ = H

        let capAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5),
                                                       .foregroundColor: ink.withAlphaComponent(0.75)]
        let cap = caption as NSString
        let cs = cap.size(withAttributes: capAttrs)
        cap.draw(at: CGPoint(x: pad + (W - cs.width) / 2, y: pad + 46 - cs.height / 2), withAttributes: capAttrs)

        let barW: CGFloat = 240, barH: CGFloat = 4
        let x0 = pad + (W - barW) / 2, y0 = pad + 22
        ink.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: CGRect(x: x0, y: y0, width: barW, height: barH), xRadius: barH / 2, yRadius: barH / 2).fill()
        let fw = max(barH, barW * min(1, progress))
        ink.setFill()
        NSBezierPath(roundedRect: CGRect(x: x0, y: y0, width: fw, height: barH), xRadius: barH / 2, yRadius: barH / 2).fill()
    }
}
