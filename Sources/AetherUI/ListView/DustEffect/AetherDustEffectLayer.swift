import Foundation
import UIKit
import Metal
import MetalKit
import QuartzCore

/// Telegram's "Vanish on Delete" dust burst, ported from
/// `submodules/TelegramUI/Components/DustEffect/Sources/DustEffectLayer.swift`.
///
/// This is a UIView host wrapping a `CAMetalLayer` (via `layerClass`).
/// The Metal layer needs UIKit-managed parenting to actually render —
/// adding a raw `CAMetalLayer` as an orphan sublayer of another view's
/// layer leaves it without a backing drawable surface, so the burst
/// never makes it to the screen.
///
/// Visual algorithm (identical to Telegram's):
///   • One particle per source pixel (width × height particles).
///   • Each particle gets a random angle + velocity at init.
///   • A horizontal "wave" (window 0.8 wide in `phase` space) sweeps
///     the leading → trailing edge. Particles outside the window
///     stay fixed; in-window they ease in.
///   • Lifetime 0.7…1.5s; alpha = lifetime / 0.3 (clamped).
public final class AetherDustEffectView: UIView {

    public override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }

    public var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }

    private final class Item {
        let frame: CGRect
        let texture: MTLTexture
        let tileSize: CGFloat
        var phase: Float = 0
        var particleBufferIsInitialized = false
        var particleBuffer: MTLBuffer?

        init(frame: CGRect, texture: MTLTexture, tileSize: CGFloat) {
            self.frame = frame
            self.texture = texture
            self.tileSize = tileSize
        }
    }

    // MARK: - Metal resources

    private let metalDevice: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let initParticlePSO: MTLComputePipelineState?
    private let updateParticlePSO: MTLComputePipelineState?
    private let renderPSO: MTLRenderPipelineState?

    public let isReady: Bool

    // MARK: - Animation driver

    private var displayLink: CADisplayLink?
    private var lastTickTimestamp: CFTimeInterval?
    private var items: [Item] = []

    // MARK: - Public knobs

    public var animationSpeed: Float = 1.0
    public var animateDown: Bool = false
    public var becameEmpty: (() -> Void)?

    // MARK: - Init

    public override init(frame: CGRect) {
        let device = MTLCreateSystemDefaultDevice()
        let queue = device?.makeCommandQueue()

        let library: MTLLibrary? = {
            guard let device = device else { return nil }
            if let lib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
                return lib
            }
            return device.makeDefaultLibrary()
        }()

        let initFn = library?.makeFunction(name: "dustEffectInitializeParticle")
        let updateFn = library?.makeFunction(name: "dustEffectUpdateParticle")
        let vertexFn = library?.makeFunction(name: "dustEffectVertex")
        let fragmentFn = library?.makeFunction(name: "dustEffectFragment")

        let initPSO: MTLComputePipelineState? = {
            guard let device = device, let fn = initFn else { return nil }
            return try? device.makeComputePipelineState(function: fn)
        }()
        let updatePSO: MTLComputePipelineState? = {
            guard let device = device, let fn = updateFn else { return nil }
            return try? device.makeComputePipelineState(function: fn)
        }()
        let renderPSO: MTLRenderPipelineState? = {
            guard let device = device, let vfn = vertexFn, let ffn = fragmentFn else { return nil }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].rgbBlendOperation = .add
            desc.colorAttachments[0].alphaBlendOperation = .add
            desc.colorAttachments[0].sourceRGBBlendFactor = .one
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].destinationAlphaBlendFactor = .one
            return try? device.makeRenderPipelineState(descriptor: desc)
        }()

        self.metalDevice = device
        self.commandQueue = queue
        self.initParticlePSO = initPSO
        self.updateParticlePSO = updatePSO
        self.renderPSO = renderPSO
        self.isReady = (device != nil && queue != nil
                        && library != nil
                        && initPSO != nil && updatePSO != nil
                        && renderPSO != nil)

        super.init(frame: frame)

        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false

        let metalLayer = self.metalLayer
        if let device = device {
            metalLayer.device = device
        }
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = false
        metalLayer.contentsScale = UIScreen.main.scale
        // Presentations-with-transactions makes drawables behave more
        // predictably under explicit commit() — without this the
        // first present sometimes drops on iOS 17/18 simulators.
        metalLayer.presentsWithTransaction = false

        if !isReady {
            NSLog("[AetherDustEffectView] Metal init failed — device=%@ queue=%@ library=%@ initFn=%@ updateFn=%@ vertexFn=%@ fragmentFn=%@ initPSO=%@ updatePSO=%@ renderPSO=%@",
                  String(describing: device != nil),
                  String(describing: queue != nil),
                  String(describing: library != nil),
                  String(describing: initFn != nil),
                  String(describing: updateFn != nil),
                  String(describing: vertexFn != nil),
                  String(describing: fragmentFn != nil),
                  String(describing: initPSO != nil),
                  String(describing: updatePSO != nil),
                  String(describing: renderPSO != nil))
        } else {
            preheat()
        }
    }

    /// Force the driver to upload the compute and render pipelines
    /// before the first user-visible burst. `makeComputePipelineState`
    /// returns a cached PSO synchronously, but the GPU/driver still
    /// lazily uploads kernel + descriptor state on first dispatch —
    /// that one-shot upload is what shows up as a 30-80ms freeze on
    /// the very first delete. We dispatch a tiny throwaway pass and
    /// commit *without* `waitUntilCompleted` so the GPU runs in
    /// parallel with everything else the caller is doing.
    public func preheat() {
        guard isReady,
              let device = metalDevice,
              let queue = commandQueue,
              let initPSO = initParticlePSO,
              let updatePSO = updateParticlePSO,
              let renderPSO = renderPSO else { return }

        let dummyCount = 32
        guard let particleBuf = device.makeBuffer(length: dummyCount * 20, options: [.storageModeShared]),
              let cmd = queue.makeCommandBuffer() else { return }

        if let enc = cmd.makeComputeCommandEncoder() {
            var verticalDirection: Float = 1.0
            let tg = MTLSize(width: 32, height: 1, depth: 1)
            let tgs = MTLSize(width: 1, height: 1, depth: 1)

            enc.setBuffer(particleBuf, offset: 0, index: 0)
            enc.setComputePipelineState(initPSO)
            enc.setBytes(&verticalDirection, length: 4, index: 1)
            enc.dispatchThreadgroups(tgs, threadsPerThreadgroup: tg)

            var size = SIMD2<UInt32>(8, 4)
            var phase: Float = 0
            var timeStep: Float = 0.016
            enc.setComputePipelineState(updatePSO)
            enc.setBytes(&size, length: 8, index: 1)
            enc.setBytes(&phase, length: 4, index: 2)
            enc.setBytes(&timeStep, length: 4, index: 3)
            enc.setBytes(&verticalDirection, length: 4, index: 4)
            enc.dispatchThreadgroups(tgs, threadsPerThreadgroup: tg)

            enc.endEncoding()
        }

        let scratchDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 8,
            height: 8,
            mipmapped: false
        )
        scratchDesc.usage = [.renderTarget, .shaderRead]
        scratchDesc.storageMode = .private

        let srcDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        srcDesc.usage = [.shaderRead]
        srcDesc.storageMode = .shared

        if let scratchTex = device.makeTexture(descriptor: scratchDesc),
           let dummySrc = device.makeTexture(descriptor: srcDesc) {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = scratchTex
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store

            if let renc = cmd.makeRenderCommandEncoder(descriptor: pass) {
                renc.setRenderPipelineState(renderPSO)
                var rect = SIMD4<Float>(0, 0, 1, 1)
                renc.setVertexBytes(&rect, length: 16, index: 0)
                var sz = SIMD2<Float>(8, 4)
                renc.setVertexBytes(&sz, length: 8, index: 1)
                var resolution = SIMD2<UInt32>(8, 4)
                renc.setVertexBytes(&resolution, length: 8, index: 2)
                renc.setVertexBuffer(particleBuf, offset: 0, index: 3)
                renc.setFragmentTexture(dummySrc, index: 0)
                renc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: dummyCount)
                renc.endEncoding()
            }
        }

        cmd.commit()
        // Intentionally no waitUntilCompleted — the upload happens
        // on the GPU in parallel with subsequent CPU work.
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    /// Spawn a dust burst at `frame` (in this view's coordinate space)
    /// using `image` as the source texture. `tileSize` controls the
    /// particle resolution: 1 = one particle per source pixel
    /// (Telegram default — finest grain, most expensive); larger
    /// values quadratically reduce particle count and per-frame
    /// compute, but the grain becomes visibly chunky. The default
    /// matches Telegram's reference look.
    public func addItem(frame: CGRect, image: UIImage, tileSize: CGFloat = 1.0) {
        guard isReady, let device = metalDevice else { return }
        guard frame.width > 0, frame.height > 0 else { return }
        guard let cgImage = image.cgImage else { return }
        guard let texture = makeBGRATexture(from: cgImage, device: device) else { return }

        items.append(Item(frame: frame, texture: texture, tileSize: max(1.0, tileSize)))
        startDisplayLinkIfNeeded()
    }

    /// Build an MTLTexture from a CGImage by hand — `MTKTextureLoader`
    /// rejects images produced by `UIGraphicsImageRenderer` in some
    /// pixel-format combinations (most notably on the iOS simulator),
    /// so we re-render the image into a known-good BGRA buffer and
    /// upload it manually.
    private func makeBGRATexture(from cgImage: CGImage, device: MTLDevice) -> MTLTexture? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = bytesPerRow * height

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: totalBytes)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 0, count: totalBytes)

        // BGRA premultiplied — matches Metal `.bgra8Unorm`.
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: buffer, bytesPerRow: bytesPerRow)
        return texture
    }

    /// Snapshot a view into a UIImage — convenience for callers.
    /// `afterScreenUpdates` defaults to `true` so any pending model
    /// writes (an `alpha` you just set, a layout you just triggered)
    /// are flushed into the presentation tree before the image is
    /// captured. With `false` `drawHierarchy` would render the
    /// last-rendered state, which is exactly the "blank snapshot"
    /// trap when the view was hidden a moment ago and you forced
    /// it visible only on this run-loop tick.
    public static func snapshot(of view: UIView, afterScreenUpdates: Bool = true) -> UIImage? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { _ in
            view.drawHierarchy(in: bounds, afterScreenUpdates: afterScreenUpdates)
        }
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        let scale = metalLayer.contentsScale
        let pixelSize = CGSize(
            width: max(1, bounds.width * scale),
            height: max(1, bounds.height * scale)
        )
        if metalLayer.drawableSize != pixelSize {
            metalLayer.drawableSize = pixelSize
        }
    }

    // MARK: - Display link tick

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil, !items.isEmpty else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(target: self), selector: #selector(DisplayLinkProxy.tick(_:)))
        // ProMotion / 120Hz: capping at 60 makes the burst visibly
        // judder against the rest of the UI's 120Hz updates — what
        // looks like "freezing on the first frame" is really every
        // other refresh missing a particle update. Let CoreAnimation
        // pick the device-native rate; the kernel runs in parallel
        // with main-thread work and the burst is short-lived.
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        } else {
            link.preferredFramesPerSecond = 60
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTickTimestamp = nil
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTickTimestamp = nil
    }

    fileprivate func displayLinkTick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt: Float
        if let last = lastTickTimestamp {
            dt = Float(now - last)
        } else {
            dt = 0
        }
        lastTickTimestamp = now

        // Telegram-iOS uses 4.0 as the end-of-life threshold, but
        // the particle lifetime ranges 0.7…1.5s and the wave window
        // is ~0.8s — by phase ≈2.0 every tile is invisible, so any
        // compute/render past that is just main-thread tax that
        // doesn't reach the screen. Drop items earlier so the
        // display link can stop and free the run loop.
        let phaseEnd: Float = 2.0
        var didFinish = false
        for i in (0..<items.count).reversed() {
            items[i].phase += dt * animationSpeed / Float(UIView.animationDurationFactor())
            if items[i].phase >= phaseEnd {
                items.remove(at: i)
                didFinish = true
            }
        }

        if items.isEmpty {
            stopDisplayLink()
            renderClear()
            if didFinish {
                becameEmpty?()
            }
            return
        }

        guard let queue = commandQueue,
              let drawable = metalLayer.nextDrawable() else {
            return
        }
        guard let cmdBuffer = queue.makeCommandBuffer() else { return }

        runComputePass(commandBuffer: cmdBuffer, dt: dt)
        runRenderPass(commandBuffer: cmdBuffer, drawable: drawable)

        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }

    private func renderClear() {
        guard let queue = commandQueue, let drawable = metalLayer.nextDrawable() else { return }
        guard let cmdBuffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        if let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.endEncoding()
        }
        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }

    // MARK: - Compute / Render

    private func runComputePass(commandBuffer: MTLCommandBuffer, dt: Float) {
        guard let device = metalDevice,
              let initPSO = initParticlePSO,
              let updatePSO = updateParticlePSO else { return }
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        var verticalDirection: Float = animateDown ? -1.0 : 1.0

        for item in items {
            let cols = max(1, Int(item.frame.width / item.tileSize))
            let rows = max(1, Int(item.frame.height / item.tileSize))
            let count = cols * rows

            if item.particleBuffer == nil {
                item.particleBuffer = device.makeBuffer(length: count * 20, options: [.storageModeShared])
            }
            guard let particleBuffer = item.particleBuffer else { continue }

            let threadgroup = MTLSize(width: 32, height: 1, depth: 1)
            let threadgroups = MTLSize(width: (count + 31) / 32, height: 1, depth: 1)

            encoder.setBuffer(particleBuffer, offset: 0, index: 0)

            if !item.particleBufferIsInitialized {
                item.particleBufferIsInitialized = true
                encoder.setComputePipelineState(initPSO)
                encoder.setBytes(&verticalDirection, length: 4, index: 1)
                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroup)
            }

            if dt > 0 {
                encoder.setComputePipelineState(updatePSO)
                var size = SIMD2<UInt32>(UInt32(cols), UInt32(rows))
                encoder.setBytes(&size, length: 8, index: 1)
                var phase = item.phase
                encoder.setBytes(&phase, length: 4, index: 2)
                var timeStep: Float = dt / Float(UIView.animationDurationFactor()) * 2.0
                encoder.setBytes(&timeStep, length: 4, index: 3)
                encoder.setBytes(&verticalDirection, length: 4, index: 4)
                encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadgroup)
            }
        }

        encoder.endEncoding()
    }

    private func runRenderPass(commandBuffer: MTLCommandBuffer, drawable: CAMetalDrawable) {
        guard let renderPSO = renderPSO else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(renderPSO)

        let containerSize = bounds.size
        guard containerSize.width > 0, containerSize.height > 0 else {
            encoder.endEncoding()
            return
        }

        for item in items {
            guard let particleBuffer = item.particleBuffer else { continue }
            let cols = max(1, Int(item.frame.width))
            let rows = max(1, Int(item.frame.height))
            let count = cols * rows

            let invertedY = containerSize.height - item.frame.maxY
            var rect = SIMD4<Float>(
                Float(item.frame.minX / containerSize.width),
                Float(invertedY / containerSize.height),
                Float(item.frame.width / containerSize.width),
                Float(item.frame.height / containerSize.height)
            )
            encoder.setVertexBytes(&rect, length: 16, index: 0)

            var size = SIMD2<Float>(Float(item.frame.width), Float(item.frame.height))
            encoder.setVertexBytes(&size, length: 8, index: 1)

            var resolution = SIMD2<UInt32>(UInt32(cols), UInt32(rows))
            encoder.setVertexBytes(&resolution, length: 8, index: 2)

            encoder.setVertexBuffer(particleBuffer, offset: 0, index: 3)
            encoder.setFragmentTexture(item.texture, index: 0)

            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: count
            )
        }

        encoder.endEncoding()
    }
}

private final class DisplayLinkProxy: NSObject {
    weak var target: AetherDustEffectView?

    init(target: AetherDustEffectView) {
        self.target = target
    }

    @objc func tick(_ link: CADisplayLink) {
        target?.displayLinkTick(link)
    }
}
