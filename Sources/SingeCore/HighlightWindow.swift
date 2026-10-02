import AppKit

/// The Singe highlight: a glass bar laid exactly over the selected term, with the term
/// redrawn clean on top. Click-through, never takes focus.
final class HighlightWindow: NSPanel {
    /// Space around the term, picked with the slider in the mock-up (size 9 → 9 × 3 pt).
    static let padX: CGFloat = 9
    static let padY: CGFloat = 3

    let glass = GlassView(frame: .zero)
    private let label = NSTextField(labelWithString: "")
    private let container = NSView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        container.wantsLayer = true
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.22
        container.layer?.shadowRadius = 6
        container.layer?.shadowOffset = CGSize(width: 0, height: -3)
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.drawsBackground = false
        label.isBezeled = false
        container.addSubview(glass)
        container.addSubview(label)
        contentView = container
    }

    /// `rect` is the selection in AppKit screen coordinates.
    func show(text: String, over rect: CGRect, font: NSFont?, dark: Bool) {
        let frame = rect.insetBy(dx: -Self.padX, dy: -Self.padY).integral
        let margin: CGFloat = 12                     // room for the shadow and the open overshoot
        setFrame(frame.insetBy(dx: -margin, dy: -margin), display: false)
        container.frame = CGRect(origin: .zero, size: self.frame.size)
        let bar = CGRect(x: margin, y: margin, width: frame.width, height: frame.height)
        glass.frame = bar
        glass.dark = dark
        glass.calm = dark ? 0.55 : 0.8
        glass.radius = min(9, bar.height * 0.3)

        // Redraw the term in its own font if we know it, sized to sit inside the bar.
        var f = font ?? NSFont.systemFont(ofSize: max(10, min(40, rect.height / 1.25)), weight: .semibold)
        // as wide as the word was on the page, never wider than the bar (the label adds ~4 pt)
        let maxWidth = min(rect.width + 2, bar.width - 10)
        var attrs: [NSAttributedString.Key: Any] = [.font: f]
        while (text as NSString).size(withAttributes: attrs).width > maxWidth && f.pointSize > 8 {
            f = NSFont(descriptor: f.fontDescriptor, size: f.pointSize - 0.5) ?? f
            attrs[.font] = f
        }
        let ink = dark ? NSColor(white: 0.985, alpha: 1) : NSColor(srgbRed: 0.06, green: 0.065, blue: 0.09, alpha: 1)
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        label.attributedStringValue = NSAttributedString(string: text, attributes: [.font: f, .foregroundColor: ink,
                                                                                     .paragraphStyle: centred])
        label.sizeToFit()
        label.frame = CGRect(x: bar.minX - 4, y: bar.midY - label.frame.height / 2, width: bar.width + 8, height: label.frame.height)

        alphaValue = 0
        orderFrontRegardless()
        glass.stir()
        animateOpen(bar)
    }

    private func animateOpen(_ bar: CGRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().alphaValue = 1
        }
        // A small overshoot, like the orb settling.
        guard let layer = container.layer else { return }
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = CATransform3DMakeScale(0.92, 0.82, 1)
        spring.toValue = CATransform3DIdentity
        spring.damping = 11
        spring.stiffness = 260
        spring.mass = 0.9
        spring.duration = spring.settlingDuration
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
        layer.add(spring, forKey: "open")
    }

    func hide() {
        glass.stop()
        orderOut(nil)
    }
}
