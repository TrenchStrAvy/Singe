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

    /// The app icon: the glass bar filling a white macOS squircle, like Sorph's orb, 1024 × 1024.
    static func appIcon(px: CGFloat = 1024) -> CGImage? {
        let s = px / 1024
        let barW = 680 * s, barH = 295 * s           // picked side by side with Sorph's 588 px orb
        guard let bar = GlassRenderer.shared.image(pixelSize: CGSize(width: barW, height: barH), scale: 4 * s,
                                                   t: 7.4, dark: true, radius: 24, calm: 1.25, pulse: 0.55) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: Int(px), height: Int(px), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // macOS icon grid: 824 pt body inset 100 pt.
        let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let path = CGPath(roundedRect: body, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.22).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let grad = CGGradient(colorsSpace: space, colors: [
            NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).cgColor,
            NSColor(srgbRed: 0.95, green: 0.955, blue: 0.97, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: body.midX, y: body.maxY), end: CGPoint(x: body.midX, y: body.minY), options: [])
        ctx.restoreGState()
        // the bar, with a soft contact shadow so it sits on the white like the orb
        let barRect = CGRect(x: body.midX - barW / 2, y: body.midY - barH / 2, width: barW, height: barH)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 30 * s, color: NSColor(srgbRed: 0.08, green: 0.09, blue: 0.2, alpha: 0.35).cgColor)
        // a deep navy body under the glass, so it reads like Sorph's orb on white
        let inset = barRect.insetBy(dx: 4 * s, dy: 4 * s)
        let radius = min(96 * s, inset.height / 2)
        ctx.addPath(CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(NSColor(srgbRed: 0.09, green: 0.10, blue: 0.17, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
        ctx.draw(bar, in: barRect)
        return ctx.makeImage()
    }

    /// Just the icon's glass bar with its navy body, transparent around it (for the icon
    /// size picker in mockups/icon-match). Same look as in appIcon.
    static func iconBar(width: CGFloat, height: CGFloat) -> CGImage? {
        let s = width / 760
        guard let bar = GlassRenderer.shared.image(pixelSize: CGSize(width: width, height: height), scale: 4 * s,
                                                   t: 7.4, dark: true, radius: 24, calm: 1.25, pulse: 0.55) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let inset = CGRect(x: 0, y: 0, width: width, height: height).insetBy(dx: 4 * s, dy: 4 * s)
        let radius = min(96 * s, inset.height / 2)
        ctx.addPath(CGPath(roundedRect: inset, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(NSColor(srgbRed: 0.09, green: 0.10, blue: 0.17, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.draw(bar, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    static func writePNG(_ image: CGImage, to path: String) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
