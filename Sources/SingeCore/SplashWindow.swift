import AppKit

/// Startup card, in the style of macOS "About This Mac": a white rounded card with the
/// Singe glass bar on top, the name, a caption and a thin progress bar, all in black.
/// Sized like a small Terminal window (410 × 202 pt). Shows while Singe loads, holds on
/// "ready" briefly, then fades. Sorph's splash is the same card with its orb.
final class SplashWindow: NSWindow {
    static let cardSize = CGSize(width: 410, height: 202)
    private static let margin: CGFloat = 30          // room for the card's shadow

    private let view = SplashCard()
    private let glass = GlassView(frame: .zero)
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var doneAt: CFTimeInterval?
    private var fadeStart: CFTimeInterval?

    init() {
        let m = Self.margin
        let rect = CGRect(x: 0, y: 0, width: Self.cardSize.width + 2 * m, height: Self.cardSize.height + 2 * m)
        super.init(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                             // the card draws its own, softer shadow
        level = .statusBar
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isReleasedWhenClosed = false
        view.frame = rect
        contentView = view
        // the Singe mark: a live glass bar, dark glass like the app icon
        let card = CGRect(x: m, y: m, width: Self.cardSize.width, height: Self.cardSize.height)
        glass.frame = CGRect(x: card.midX - 56, y: SplashCard.logoY(card), width: 112, height: 40)
        glass.dark = true
        glass.radius = 12
        glass.calm = 1.1
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
        let t = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
            if view.progress >= 1, now - done > 1.1, fadeStart == nil { fadeStart = now }
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
        view.needsDisplay = true
    }
}

/// The card: white, rounded like a macOS window, hairline border, soft shadow.
private final class SplashCard: NSView {
    var progress = 0.0
    var target = 0.08
    var caption = "starting…"

    // vertical rhythm inside the 202 pt card: logo 40, gap 14, title 27, gap 4,
    // caption 16, gap 20, bar 4, centred
    static func logoY(_ card: CGRect) -> CGFloat { card.maxY - 38 - 40 }

    override func draw(_ dirty: NSRect) {
        let m: CGFloat = 30
        let card = CGRect(x: m, y: m, width: bounds.width - 2 * m, height: bounds.height - 2 * m)
        let shape = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = CGSize(width: 0, height: -8)
        shadow.set()
        NSColor.white.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0, alpha: 0.12).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        let ink = NSColor(srgbRed: 0.07, green: 0.075, blue: 0.09, alpha: 1)
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: ink]
        let title = "Singe" as NSString
        let ts = title.size(withAttributes: titleAttrs)
        let titleY = Self.logoY(card) - 14 - ts.height
        title.draw(at: CGPoint(x: card.midX - ts.width / 2, y: titleY), withAttributes: titleAttrs)

        let capAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: ink.withAlphaComponent(0.55)]
        let cap = caption as NSString
        let cs = cap.size(withAttributes: capAttrs)
        let capY = titleY - 4 - cs.height
        cap.draw(at: CGPoint(x: card.midX - cs.width / 2, y: capY), withAttributes: capAttrs)

        let barW: CGFloat = 240, barH: CGFloat = 4
        let x0 = card.midX - barW / 2, y0 = capY - 20 - barH
        ink.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: CGRect(x: x0, y: y0, width: barW, height: barH), xRadius: barH / 2, yRadius: barH / 2).fill()
        ink.setFill()
        let fw = max(barH, barW * min(1, progress))
        NSBezierPath(roundedRect: CGRect(x: x0, y: y0, width: fw, height: barH), xRadius: barH / 2, yRadius: barH / 2).fill()
    }
}
