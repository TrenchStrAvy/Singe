import AppKit
import Metal
import MetalKit
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
               calm: Float = 1) -> CGImage? {
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
        encode(enc, uniforms: Self.uniforms(size: pixelSize, scale: scale, t: t, flow: t * 0.9, dark: dark,
                                            pulse: 0, radius: radius, calm: calm))
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

/// A live glass bar. Animates only while it is on screen.
final class GlassView: MTKView, MTKViewDelegate {
    var dark = true
    var calm: Float = 1
    var radius: CGFloat = 8
    private var pulse = 0.0
    private var flow = Double.random(in: 0...20)
    private let phase = Double.random(in: 0...20)
    private var last = CACurrentMediaTime()

    init(frame: CGRect) {
        super.init(frame: frame, device: GlassRenderer.shared.device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        layer?.isOpaque = false
        preferredFramesPerSecond = 60
        delegate = self
        isPaused = true
        enableSetNeedsDisplay = false
    }

    required init(coder: NSCoder) { fatalError("not used") }

    /// The stir of opening: ribbons speed up and swell, then settle over about a second.
    func stir() {
        pulse = 1
        last = CACurrentMediaTime()
        isPaused = false
    }

    func stop() { isPaused = true }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - last)
        last = now
        pulse *= pow(0.18, dt)
        flow += dt * (0.9 + 2.2 * pulse)           // integrated like Sorph: speed changes, phase never jumps
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let cmd = GlassRenderer.shared.queue?.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        let scale = window?.backingScaleFactor ?? 2
        GlassRenderer.shared.encode(enc, uniforms: GlassRenderer.uniforms(
            size: drawableSize, scale: scale, t: now + phase, flow: flow + phase, dark: dark,
            pulse: pulse, radius: radius, calm: calm))
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}
