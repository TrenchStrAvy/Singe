import AppKit
import SwiftUI

/// Offscreen render of the highlight and popover for a term, for checking a build
/// without granting permissions or holding keys.
enum Snapshot {
    static func render(to path: String, term: String, dark: Bool) {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let store = Store(path: NSTemporaryDirectory() + "singe-snapshot.sqlite")
        let ranked = Ranker.rank(TermIndex().candidates(for: term), profile: store.profile())
        let model = LookupModel()
        model.term = term
        model.senses = Array(ranked.prefix(3))
        model.selected = model.senses.first?.id
        model.arrowX = 180

        let view = PopoverView(model: model)
            .background(PopoverShape(arrowX: 180, arrowUp: false).fill(Color(nsColor: dark
                ? NSColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)
                : NSColor(srgbRed: 0.965, green: 0.965, blue: 0.965, alpha: 1))))
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: view)
        let popSize = host.fittingSize
        host.frame = CGRect(origin: .zero, size: popSize)

        let font = NSFont.systemFont(ofSize: 19, weight: .semibold)
        let textSize = (term as NSString).size(withAttributes: [.font: font])
        let bar = CGSize(width: ceil(textSize.width) + HighlightWindow.padX * 2, height: ceil(textSize.height) + HighlightWindow.padY * 2)
        let W = max(popSize.width + 80, 520), H = popSize.height + bar.height + 90
        let scale: CGFloat = 2

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = CGSize(width: W, height: H)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (dark ? NSColor(white: 0.04, alpha: 1) : NSColor.white).setFill()
        CGRect(x: 0, y: 0, width: W, height: H).fill()

        // the line of text with the glass bar over the term
        let barRect = CGRect(x: (W - bar.width) / 2, y: 40, width: bar.width, height: bar.height)
        if let glass = GlassRenderer.shared.image(pixelSize: CGSize(width: bar.width * scale, height: bar.height * scale),
                                                  scale: scale, t: 5.2, dark: dark, radius: min(9, bar.height * 0.3),
                                                  calm: dark ? 0.55 : 0.8) {
            NSGraphicsContext.current?.cgContext.draw(glass, in: barRect)
        }
        let ink = dark ? NSColor(white: 0.985, alpha: 1) : NSColor(srgbRed: 0.06, green: 0.065, blue: 0.09, alpha: 1)
        (term as NSString).draw(at: CGPoint(x: barRect.midX - textSize.width / 2, y: barRect.midY - textSize.height / 2),
                                withAttributes: [.font: font, .foregroundColor: ink])
        let soft: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 19, weight: .medium),
                                                   .foregroundColor: dark ? NSColor(white: 0.55, alpha: 1) : NSColor(white: 0.45, alpha: 1)]
        ("study the Level 2" as NSString).draw(at: CGPoint(x: barRect.minX - 170, y: barRect.midY - textSize.height / 2), withAttributes: soft)
        ("structure → study" as NSString).draw(at: CGPoint(x: barRect.maxX + 8, y: barRect.midY - textSize.height / 2), withAttributes: soft)

        // the popover above it
        let popOrigin = CGPoint(x: barRect.midX - 180, y: barRect.maxY + 8)
        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: bitmap)
            bitmap.draw(in: CGRect(origin: popOrigin, size: popSize))
        }
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
