import MetalKit
import SwiftUI

/// GPU particle engine for the recorder island.
/// A Metal compute kernel moves the particles every frame; a render pass draws them as soft round dots.
/// Phases: listening (dots appear and drift with volume), refining (they condense into a line),
/// sent (they stream into the send button), idle (they fade out).
enum ParticlePhase: Float {
    case listening = 0
    case refining = 1
    case sent = 2
    case idle = 3
}

// Layouts must match the Metal structs below (SIMD2<Float> aligns to 8 bytes in both).
private struct Particle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var home: SIMD2<Float>
    var rank: Float      // 0...1, order in which particles appear as volume rises
    var alpha: Float
}

private struct Uniforms {
    var time: Float
    var dt: Float
    var volume: Float
    var phase: Float
    var size: SIMD2<Float>   // view size in points
    var reveal: Float        // 0...1 share of particles visible
    var dark: Float
    var scale: Float         // backing scale factor
    var pad: Float = 0
}

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Particle { float2 position; float2 velocity; float2 home; float rank; float alpha; };
struct Uniforms { float time; float dt; float volume; float phase; float2 size; float reveal; float dark; float scale; float pad; };

static float2 hash2(float n) {
    return fract(sin(float2(n * 12.9898, n * 78.233)) * 43758.5453);
}

kernel void update(device Particle *ps [[buffer(0)]],
                   constant Uniforms &u [[buffer(1)]],
                   uint id [[thread_position_in_grid]]) {
    Particle p = ps[id];
    float t = u.time;
    float v = u.volume;
    float2 h = hash2(p.rank * 917.0 + 3.0);          // per-particle constants
    float aspect = u.size.x / max(u.size.y, 1.0);
    float2 target;
    float stiffness;
    float alphaTarget;

    if (u.phase < 0.5) {                            // listening
        float2 freq = 0.35 + h * 0.9;
        float2 amp = float2(0.012 + 0.07 * v, (0.05 + 0.26 * v));
        float2 wander = float2(sin(t * freq.x + h.y * 40.0), cos(t * freq.y + h.x * 31.0)) * amp;
        // A gentle flow field adds motion that grows with volume.
        float2 flow = float2(sin(p.position.y * 9.0 + t * 1.3 + h.x * 6.0),
                             cos(p.position.x * 7.0 * aspect * 0.25 - t * 1.1 + h.y * 4.0)) * (0.01 + 0.05 * v);
        target = p.home + wander + flow;
        stiffness = 7.0;
        alphaTarget = p.rank < u.reveal ? 0.95 : 0.0;
    } else if (u.phase < 1.5) {                     // refining: condense into a shimmering line
        target = float2(p.home.x, 0.5 + 0.05 * sin(p.home.x * 22.0 - t * 7.0));
        stiffness = 11.0;
        alphaTarget = p.rank < max(u.reveal, 0.55) ? 0.9 : 0.0;
    } else if (u.phase < 2.5) {                     // sent: stream into the send button on the left
        target = float2(-0.08, 0.5 + (p.home.y - 0.5) * 0.2);
        stiffness = 3.0 + h.x * 7.0;
        alphaTarget = p.position.x < 0.12 ? 0.0 : p.alpha;
    } else {                                        // idle
        target = p.position;
        stiffness = 0.0;
        alphaTarget = 0.0;
    }

    float dt = u.dt;
    p.velocity += (target - p.position) * stiffness * dt * 6.0;
    p.velocity *= pow(0.015, dt);                   // damping
    p.position += p.velocity * dt;
    p.alpha += (alphaTarget - p.alpha) * min(1.0, dt * (u.phase > 1.5 ? 6.0 : 3.5));
    ps[id] = p;
}

struct VOut { float4 position [[position]]; float size [[point_size]]; float4 color; };

static float3 thermal(float x) {
    const float3 c0 = float3(0.20, 0.04, 0.37);
    const float3 c1 = float3(0.47, 0.11, 0.43);
    const float3 c2 = float3(0.74, 0.22, 0.33);
    const float3 c3 = float3(0.93, 0.41, 0.15);
    const float3 c4 = float3(0.98, 0.71, 0.10);
    x = clamp(x, 0.0, 1.0) * 4.0;
    if (x < 1.0) return mix(c0, c1, x);
    if (x < 2.0) return mix(c1, c2, x - 1.0);
    if (x < 3.0) return mix(c2, c3, x - 2.0);
    return mix(c3, c4, x - 3.0);
}

vertex VOut particleVertex(const device Particle *ps [[buffer(0)]],
                           constant Uniforms &u [[buffer(1)]],
                           uint id [[vertex_id]]) {
    Particle p = ps[id];
    VOut o;
    o.position = float4(p.position.x * 2.0 - 1.0, 1.0 - p.position.y * 2.0, 0.0, 1.0);
    float speed = length(p.velocity * float2(u.size.x / max(u.size.y, 1.0), 1.0));
    float spread = (fract(p.rank * 13.7) - 0.5) * 0.3;    // per-dot color variation
    float heat = 0.26 + 0.45 * u.volume + min(0.25, speed * 0.6) + spread + (u.phase > 0.5 && u.phase < 1.5 ? 0.12 : 0.0);
    heat = min(heat, u.dark > 0.5 ? 0.98 : 0.84);
    float3 rgb = thermal(heat);
    o.color = float4(rgb, p.alpha);
    float rank = fract(p.rank * 7.31);
    o.size = (1.1 + rank * 0.8 + u.volume * 0.5) * u.scale;
    return o;
}

fragment float4 particleFragment(VOut in [[stage_in]], float2 pc [[point_coord]]) {
    float d = length(pc - 0.5) * 2.0;               // 0 at center, 1 at edge
    float a = smoothstep(1.0, 0.25, d) * in.color.a;
    return float4(in.color.rgb * a, a);             // premultiplied
}
"""

/// Shared Metal state; nil when Metal or the shaders are unavailable (callers fall back to the CPU field).
final class ParticleEngine {
    static let shared: ParticleEngine? = ParticleEngine()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let compute: MTLComputePipelineState
    let render: MTLRenderPipelineState
    let renderAdditive: MTLRenderPipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let update = library.makeFunction(name: "update"),
                let vertex = library.makeFunction(name: "particleVertex"),
                let fragment = library.makeFunction(name: "particleFragment")
            else { return nil }
            compute = try device.makeComputePipelineState(function: update)
            render = try Self.renderPipeline(device: device, vertex: vertex, fragment: fragment, additive: false)
            renderAdditive = try Self.renderPipeline(device: device, vertex: vertex, fragment: fragment, additive: true)
        } catch {
            NSLog("Vocality: particle engine unavailable: \(error.localizedDescription)")
            return nil
        }
        self.device = device
        self.queue = queue
    }

    private static func renderPipeline(device: MTLDevice, vertex: MTLFunction, fragment: MTLFunction, additive: Bool) throws
        -> MTLRenderPipelineState
    {
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vertex
        d.fragmentFunction = fragment
        let a = d.colorAttachments[0]!
        a.pixelFormat = .bgra8Unorm
        a.isBlendingEnabled = true
        a.rgbBlendOperation = .add
        a.alphaBlendOperation = .add
        a.sourceRGBBlendFactor = .one              // premultiplied
        a.sourceAlphaBlendFactor = .one
        a.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
        a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: d)
    }
}

/// Owns the particle buffer and draws each frame.
final class ParticleRenderer: NSObject, MTKViewDelegate {
    static let count = 900

    var volume: Float = 0
    var phase: ParticlePhase = .idle {
        didSet { if phase != .idle { idleSince = nil } }
    }
    var dark = false
    var reduceMotion = false

    private let engine: ParticleEngine
    private let particles: MTLBuffer
    private var start = CACurrentMediaTime()
    private var last = CACurrentMediaTime()
    private var idleSince: CFTimeInterval?
    weak var view: MTKView?

    init(engine: ParticleEngine) {
        self.engine = engine
        var rng = SystemRandomNumberGenerator()
        let n = Self.count
        // Jittered grid so dots cover the area evenly; ranks shuffled for an even reveal.
        let cols = 45, rows = 20
        var ranks = (0..<n).map { Float($0) / Float(n) }
        ranks.shuffle(using: &rng)
        var list: [Particle] = []
        list.reserveCapacity(n)
        for i in 0..<n {
            let c = i % cols, r = (i / cols) % rows
            let home = SIMD2<Float>(
                (Float(c) + 0.5 + Float.random(in: -0.4...0.4, using: &rng)) / Float(cols),
                (Float(r) + 0.5 + Float.random(in: -0.4...0.4, using: &rng)) / Float(rows) * 0.8 + 0.1)
            list.append(Particle(position: home, velocity: .zero, home: home, rank: ranks[i], alpha: 0))
        }
        particles = engine.device.makeBuffer(bytes: list, length: MemoryLayout<Particle>.stride * n, options: .storageModeShared)!
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(1.0 / 20.0, max(1.0 / 240.0, now - last)))
        last = now

        // Pause once idle particles have faded out.
        if phase == .idle {
            if idleSince == nil { idleSince = now }
            if let since = idleSince, now - since > 1.2 { view.isPaused = true }
        }

        guard let commands = engine.queue.makeCommandBuffer(),
            let pass = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else { return }
        encode(commands: commands, pass: pass, size: view.bounds.size,
               scale: Float(view.window?.backingScaleFactor ?? 2), time: Float(now - start), dt: dt)
        commands.present(drawable)
        commands.commit()
    }

    /// Encodes one physics step and one draw. Shared by the live view and the offscreen check.
    func encode(commands: MTLCommandBuffer, pass: MTLRenderPassDescriptor, size: CGSize, scale: Float, time: Float, dt: Float) {
        let v = reduceMotion ? min(volume, 0.3) : volume
        // Map volume to the share of visible particles: a few at rest, more as it gets louder.
        let reveal = 0.035 + 0.6 * powf(max(0, min(1, v)), 0.85)
        var u = Uniforms(
            time: time, dt: reduceMotion ? dt * 0.4 : dt, volume: v, phase: phase.rawValue,
            size: SIMD2(Float(size.width), Float(size.height)),
            reveal: reveal, dark: dark ? 1 : 0, scale: scale)

        if let encoder = commands.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(engine.compute)
            encoder.setBuffer(particles, offset: 0, index: 0)
            encoder.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            let width = min(engine.compute.maxTotalThreadsPerThreadgroup, 256)
            encoder.dispatchThreads(
                MTLSize(width: Self.count, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
            encoder.endEncoding()
        }

        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].loadAction = .clear
        if let encoder = commands.makeRenderCommandEncoder(descriptor: pass) {
            encoder.setRenderPipelineState(dark ? engine.renderAdditive : engine.render)
            encoder.setVertexBuffer(particles, offset: 0, index: 0)
            encoder.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Self.count)
            encoder.endEncoding()
        }
    }
}

/// SwiftUI wrapper. Falls back to nothing if Metal is unavailable; check `ParticleEngine.shared` first.
struct ParticleEngineView: NSViewRepresentable {
    var volume: CGFloat
    var phase: ParticlePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> ParticleRenderer? {
        ParticleEngine.shared.map { ParticleRenderer(engine: $0) }
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: ParticleEngine.shared?.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.delegate = context.coordinator
        context.coordinator?.view = view
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        guard let renderer = context.coordinator else { return }
        renderer.volume = Float(volume)
        renderer.phase = phase
        renderer.dark = colorScheme == .dark
        renderer.reduceMotion = reduceMotion
        if phase != .idle { view.isPaused = false }
    }
}

// MARK: - Offscreen check

extension ParticleEngine {
    /// Runs the engine offscreen through each phase and writes PNG frames. Used by `Vocality --engine-check`.
    /// Returns a summary line per phase with the share of pixels drawn.
    static func offscreenCheck(outputDirectory: URL) -> [String] {
        guard let engine = shared else { return ["engine unavailable"] }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let width = 380, height = 72      // 190x36 points at 2x
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let texture = engine.device.makeTexture(descriptor: td) else { return ["no texture"] }

        var lines: [String] = []
        for dark in [false, true] {
            let renderer = ParticleRenderer(engine: engine)
            renderer.dark = dark
            let steps: [(String, ParticlePhase, Float)] = [
                ("quiet", .listening, 0.05), ("speaking", .listening, 0.5), ("loud", .listening, 0.95),
                ("refining", .refining, 0.5), ("sent", .sent, 0.5),
            ]
            var time: Float = 0
            for (name, phase, volume) in steps {
                renderer.phase = phase
                renderer.volume = volume
                for _ in 0..<(phase == .sent ? 20 : 70) {     // ~1.2 s at 60 fps (sent: mid-stream)
                    let pass = MTLRenderPassDescriptor()
                    pass.colorAttachments[0].texture = texture
                    pass.colorAttachments[0].storeAction = .store
                    guard let commands = engine.queue.makeCommandBuffer() else { continue }
                    renderer.encode(commands: commands, pass: pass, size: CGSize(width: 190, height: 36),
                                    scale: 2, time: time, dt: 1 / 60)
                    commands.commit()
                    commands.waitUntilCompleted()
                    time += 1 / 60
                }
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
                let drawn = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 8 }.count
                let label = "\(dark ? "dark" : "light")-\(name)"
                lines.append("\(label): \(String(format: "%.1f", Double(drawn) * 100 / Double(width * height)))% pixels")
                writePNG(bytes: bytes, width: width, height: height, dark: dark,
                         to: outputDirectory.appendingPathComponent("engine-\(label).png"))
            }
        }
        return lines
    }

    /// Composites the BGRA premultiplied frame over the island's glass color and saves it.
    private static func writePNG(bytes: [UInt8], width: Int, height: Int, dark: Bool, to url: URL) {
        let background: (Double, Double, Double) = dark ? (0.12, 0.12, 0.13) : (0.95, 0.95, 0.96)
        var out = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            let b = Double(bytes[i * 4]) / 255, g = Double(bytes[i * 4 + 1]) / 255
            let r = Double(bytes[i * 4 + 2]) / 255, a = Double(bytes[i * 4 + 3]) / 255
            out[i * 4] = UInt8(min(255, (r + background.0 * (1 - a)) * 255))
            out[i * 4 + 1] = UInt8(min(255, (g + background.1 * (1 - a)) * 255))
            out[i * 4 + 2] = UInt8(min(255, (b + background.2 * (1 - a)) * 255))
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: width * 4, bitsPerPixel: 32)!
        out.withUnsafeBytes { memcpy(rep.bitmapData!, $0.baseAddress!, out.count) }
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
