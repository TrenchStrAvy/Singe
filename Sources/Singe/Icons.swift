import AppKit

/// The Singe mark is the glass bar itself. Icons are rendered from the same shader.
enum Icons {
    /// Menu bar icon: a small glass bar, in colour like Sorph's sphere.
    static func menuBar() -> NSImage {
        let size = CGSize(width: 22, height: 11)
        let scale: CGFloat = 2
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let cg = GlassRenderer.shared.image(pixelSize: CGSize(width: size.width * scale, height: size.height * scale),
                                                  scale: scale, t: 3.1, dark: true, radius: 3.5) else {
            let img = NSImage(systemSymbolName: "rectangle.roundedtop", accessibilityDescription: "Singe")!
            img.isTemplate = true
            return img
        }
        _ = dark
        let img = NSImage(cgImage: cg, size: size)
        img.accessibilityDescription = "Singe"
        return img
    }

    /// The app icon: the glass bar on a dark macOS squircle, 1024 × 1024.
    static func appIcon(px: CGFloat = 1024) -> CGImage? {
        let s = px / 1024
        let barW = 700 * s, barH = 270 * s
        guard let bar = GlassRenderer.shared.image(pixelSize: CGSize(width: barW, height: barH), scale: 4 * s,
                                                   t: 7.4, dark: true, radius: 17) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: Int(px), height: Int(px), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // macOS icon grid: 824 pt body inset 100 pt, continuous corners.
        let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let path = CGPath(roundedRect: body, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(NSColor(srgbRed: 0.05, green: 0.055, blue: 0.075, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let grad = CGGradient(colorsSpace: space, colors: [
            NSColor(srgbRed: 0.13, green: 0.14, blue: 0.19, alpha: 1).cgColor,
            NSColor(srgbRed: 0.03, green: 0.035, blue: 0.05, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.minY), options: [])
        // A soft glow under the bar, in the ribbon hues.
        let c = Ribbon.colors()
        let glow = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: CGFloat(c[0].x), green: CGFloat(c[0].y), blue: CGFloat(c[0].z), alpha: 0.28),
            CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: body.midX, y: body.midY), startRadius: 0,
                               endCenter: CGPoint(x: body.midX, y: body.midY), endRadius: 420 * s, options: [])
        ctx.restoreGState()
        // Inner rim highlight.
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        ctx.setLineWidth(3 * s)
        ctx.strokePath()
        ctx.draw(bar, in: CGRect(x: body.midX - barW / 2, y: body.midY - barH / 2, width: barW, height: barH))
        return ctx.makeImage()
    }

    static func writePNG(_ image: CGImage, to path: String) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
