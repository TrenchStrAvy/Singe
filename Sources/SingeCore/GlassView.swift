import AppKit
import Metal
import QuartzCore

/// Sorph's ribbon hues (degrees), at the saturation the mock-up settled on.
enum Ribbon {
    static let hues: [Double] = [236, 184, 290]
    static let saturation = 0.40
    static let lightness = 0.62

    static func colors() -> [SIMD3<Float>] {
        hues.map { hsl($0, saturation, lightness) }
    }

    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> SIMD3<Float> {
        func f(_ n: Double) -> Float {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            let a = s * min(l, 1 - l)
            return Float(l - a * max(-1, min(k - 3, min(9 - k, 1))))
        }
        return SIMD3(f(0), f(8), f(4))
    }
}

struct GlassUniforms {
    var res: SIMD2<Float>
    var scale: Float
    var t: Float
    var flow: Float
    var dark: Float
    var pulse: Float
    var radius: Float
    var calm: Float
    var c1: SIMD3<Float>
    var c2: SIMD3<Float>
    var c3: SIMD3<Float>
}

struct OrbUniforms {
    var res: SIMD2<Float>
    var t: Float
    var flow: Float
    var pulse: Float
    var calm: Float
    var curve: Float
    var rimK: Float
    var specK: Float
    var depthK: Float
    var widthK: Float
    var tilt: Float
    var c1: SIMD3<Float>
    var c2: SIMD3<Float>
    var c3: SIMD3<Float>
}

/// One Metal pipeline shared by every glass surface (highlight, logo, menu bar icon).
final class GlassRenderer {
    static let shared = GlassRenderer()

    let device: MTLDevice?
    let queue: MTLCommandQueue?
    let pipeline: MTLRenderPipelineState?

    private init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        var state: MTLRenderPipelineState?
        if let device {
            do {
                let lib = try device.makeLibrary(source: GlassShader.source, options: nil)
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = lib.makeFunction(name: "glass_vertex")
                desc.fragmentFunction = lib.makeFunction(name: "glass_fragment")
                let att = desc.colorAttachments[0]!
                att.pixelFormat = .bgra8Unorm
                att.isBlendingEnabled = true
                att.rgbBlendOperation = .add
                att.alphaBlendOperation = .add
                att.sourceRGBBlendFactor = .one          // premultiplied output
                att.sourceAlphaBlendFactor = .one
                att.destinationRGBBlendFactor = .oneMinusSourceAlpha
                att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                state = try device.makeRenderPipelineState(descriptor: desc)
            } catch {
                NSLog("Singe: glass shader failed: \(error)")
            }
        }
        pipeline = state
    }

    /// Sorph's orb in Singe's glass (variant B from mockups/sorph-logo), rendered offscreen.
    /// t = 4.55 is the frozen moment picked in the variant page.
    func orbImage(pixels: Int, t: Float = 4.55) -> CGImage? {
        guard let device, let queue,
              let lib = try? device.makeLibrary(source: GlassShader.source, options: nil) else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "glass_vertex")
        desc.fragmentFunction = lib.makeFunction(name: "orb_fragment")
        let att = desc.colorAttachments[0]!
        att.pixelFormat = .bgra8Unorm
        att.isBlendingEnabled = true
        att.sourceRGBBlendFactor = .one; att.sourceAlphaBlendFactor = .one
        att.destinationRGBBlendFactor = .oneMinusSourceAlpha; att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let state = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        let tdesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: pixels, height: pixels, mipmapped: false)
        tdesc.usage = [.renderTarget, .shaderRead]
        tdesc.storageMode = .managed
        guard let tex = device.makeTexture(descriptor: tdesc), let cmd = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let c = Ribbon.colors()
        // variant B: one ribbon sweeping across the middle, with a glint
        var u = OrbUniforms(res: SIMD2(Float(pixels), Float(pixels)), t: t, flow: t * 0.9, pulse: 0.55, calm: 1.2,
                            curve: 0.55, rimK: 1.0, specK: 1.0, depthK: 0.6, widthK: 1.0, tilt: -0.45,
                            c1: c[0], c2: c[1], c3: c[2])
        enc.setRenderPipelineState(state)
        enc.setFragmentBytes(&u, length: MemoryLayout<OrbUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        if let blit = cmd.makeBlitCommandEncoder() { blit.synchronize(resource: tex); blit.endEncoding() }
        cmd.commit(); cmd.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
        tex.getBytes(&bytes, bytesPerRow: pixels * 4, from: MTLRegionMake2D(0, 0, pixels, pixels), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    func encode(_ enc: MTLRenderCommandEncoder, uniforms: GlassUniforms) {
        guard let pipeline else { return }
        var u = uniforms
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<GlassUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    static func uniforms(size: CGSize, scale: CGFloat, t: Double, flow: Double, dark: Bool,
                         pulse: Double, radius: CGFloat, calm: Float) -> GlassUniforms {
        let c = Ribbon.colors()
        return GlassUniforms(res: SIMD2(Float(size.width), Float(size.height)), scale: Float(scale),
                             t: Float(t), flow: Float(flow), dark: dark ? 1 : 0, pulse: Float(pulse),
                             radius: Float(radius), calm: calm, c1: c[0], c2: c[1], c3: c[2])
    }

    /// Renders one frame offscreen: used for the app icon and the menu bar icon.
    func image(pixelSize: CGSize, scale: CGFloat, t: Double, dark: Bool, radius: CGFloat,
               calm: Float = 1, pulse: Double = 0, flow: Double? = nil) -> CGImage? {
        guard let device, let queue, pipeline != nil else { return nil }
        let w = Int(pixelSize.width), h = Int(pixelSize.height)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .managed
        guard let tex = device.makeTexture(descriptor: desc),
              let cmd = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = tex
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encode(enc, uniforms: Self.uniforms(size: pixelSize, scale: scale, t: t, flow: flow ?? t * 0.9, dark: dark,
                                            pulse: pulse, radius: radius, calm: calm))
        enc.endEncoding()
        if let blit = cmd.makeBlitCommandEncoder() { blit.synchronize(resource: tex); blit.endEncoding() }
        cmd.commit()
        cmd.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// A live glass bar. Each frame is rendered offscreen by the shared Metal pipeline and
/// shown as the layer's image: the same path as the icon and the snapshot check, which
/// works in every window (an MTKView inside the click-through overlay stayed invisible).
final class GlassView: NSView {
    var dark = true
    var calm: Float = 1
    var radius: CGFloat = 8
    private var pulse = 0.0
    private var flow = Double.random(in: 0...20)
    private let phase = Double.random(in: 0...20)
    private var last = CACurrentMediaTime()
    private var timer: Timer?
    private(set) var drawCount = 0
    private let imageLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
        imageLayer.contentsGravity = .resize
        imageLayer.isOpaque = false
        layer?.addSublayer(imageLayer)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        CATransaction.commit()
    }

    override var frame: NSRect {
        didSet { imageLayer.frame = bounds }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var isAnimating: Bool { timer != nil }

    /// The stir of opening: ribbons speed up and swell, then settle over about a second.
    func stir() {
        pulse = 1
        last = CACurrentMediaTime()
        render()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.render() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func render() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - last)
        last = now
        pulse *= pow(0.18, dt)
        flow += dt * (0.9 + 2.2 * pulse)           // integrated like Sorph: speed changes, phase never jumps
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let px = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        guard px.width >= 2, px.height >= 2,
              let image = GlassRenderer.shared.image(pixelSize: px, scale: scale, t: now + phase, dark: dark,
                                                     radius: radius, calm: calm, pulse: pulse, flow: flow + phase)
        else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        imageLayer.contents = image
        imageLayer.contentsScale = scale
        CATransaction.commit()
        drawCount += 1
    }

    /// The image currently shown (for `Singe --demo`).
    var currentImage: CGImage? { (imageLayer.contents as AnyObject?).map { $0 as! CGImage } }
}
