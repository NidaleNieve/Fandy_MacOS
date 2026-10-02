import Foundation
import Metal
import CoreImage
import FandyCore
import FandyHardware

// Read-only, finite diagnostic. No privileged API, fan writer, network, or configurable load.
// Every workload stops if fresh automatic ownership / conservative thermal admission is lost.
final class Stimulus: @unchecked Sendable {
    private let lock = NSLock()
    private let startedAt: Double
    private var phase: MeasurementPhase?
    private var authorizedUntil = 0.0
    private var failure: String?
    private var checksum = 0.0
    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLComputePipelineState
    private let buffer: any MTLBuffer
    init(startedAt: Double) throws {
        self.startedAt = startedAt
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let buffer = device.makeBuffer(length: 262_144 * MemoryLayout<Float>.stride, options: .storageModeShared) else { throw ControlError.invalidSnapshot }
        let library = try device.makeLibrary(source: """
        #include <metal_stdlib>
        using namespace metal;
        kernel void pulse(device float *v [[buffer(0)]], uint i [[thread_position_in_grid]]) {
            float x = v[i];
            for (uint n=0; n<64; ++n) { x = sin(x + 0.01f) + 0.1f; }
            v[i] = x;
        }
        """, options: nil)
        guard let function = library.makeFunction(name: "pulse") else { throw ControlError.invalidSnapshot }
        self.device = device; self.queue = queue; self.buffer = buffer
        self.pipeline = try device.makeComputePipelineState(function: function)
        buffer.contents().initializeMemory(as: Float.self, repeating: 0.1, count: 262_144)
    }
    func update(_ phase: MeasurementPhase?) {
        lock.lock(); defer { lock.unlock() }
        self.phase = phase
        let phaseEnd = phase == .cpu ? startedAt + 90 : phase == .gpu ? startedAt + 240 : .infinity
        authorizedUntil = min(ProcessInfo.processInfo.systemUptime + 2, phaseEnd)
    }
    func stop() { update(nil) }
    func error() -> String? { lock.lock(); defer { lock.unlock() }; return failure }
    private func fail(_ message: String) { lock.lock(); defer { lock.unlock() }; failure = message; phase = nil }
    private func allowed(_ wanted: MeasurementPhase) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let pressure = ProcessInfo.processInfo.thermalState
        return phase == wanted && failure == nil && ProcessInfo.processInfo.systemUptime < authorizedUntil &&
            (pressure == .nominal || pressure == .fair)
    }
    func start() {
        for _ in 0..<2 {
            Thread.detachNewThread { [self] in
                while error() == nil {
                    if allowed(.cpu) {
                        let end = ProcessInfo.processInfo.systemUptime + 0.05
                        var value = 0.1
                        while allowed(.cpu) && ProcessInfo.processInfo.systemUptime < end {
                            for _ in 0..<1_000 { value = sin(value + 0.01) + 0.1 }
                        }
                        lock.lock(); checksum += value; lock.unlock()
                    }
                    Thread.sleep(forTimeInterval: 0.15)
                }
            }
        }
        Thread.detachNewThread { [self] in
            while error() == nil {
                if allowed(.gpu) {
                    let end = ProcessInfo.processInfo.systemUptime + 0.05
                    while allowed(.gpu) && ProcessInfo.processInfo.systemUptime < end {
                        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { fail("GPU command unavailable"); break }
                        encoder.setComputePipelineState(pipeline); encoder.setBuffer(buffer, offset: 0, index: 0)
                        encoder.dispatchThreads(MTLSize(width: 262_144, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: pipeline.threadExecutionWidth, height: 1, depth: 1))
                        encoder.endEncoding()
                        let done = DispatchSemaphore(value: 0)
                        command.addCompletedHandler { _ in done.signal() }; command.commit()
                        if done.wait(timeout: .now() + .milliseconds(250)) == .timedOut { fail("GPU batch exceeded diagnostic budget"); break }
                        if command.status != .completed { fail("GPU batch failed"); break }
                    }
                }
                Thread.sleep(forTimeInterval: 0.15)
            }
        }
    }
}
struct Record: Encodable {
    let timestamp: String
    let model: String
    let os: String
    let phase: MeasurementPhase
    let elapsed: Double
    let fans: [Fan]
    let keys: [DiscoveredSensor]
    let hid: [HIDTemperature]
    let note = "Bounded read-only measurement. Candidate sensor identities remain unqualified."
}
func emit<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(value); data.append(10); FileHandle.standardOutput.write(data)
}
let renderCycle = CommandLine.arguments == [CommandLine.arguments[0], "--gpu-render-cycle"]
guard renderCycle || CommandLine.arguments == [CommandLine.arguments[0], "--bounded-cycle"] else {
    FileHandle.standardError.write(Data("Usage: fandy-measure --bounded-cycle | --gpu-render-cycle\nFixed read-only cycles under verified automatic fan mode. GPU render: 30s baseline, 30s 4K image processing, 120s cooldown.\n".utf8)); exit(2)
}
/// A finite ordinary Core Image video-processing workload, not the earlier sine compute pulse.
/// Each submitted frame must finish within 250ms; admission is rechecked every frame.
func captureRenderCycle() throws {
    guard HardwareSnapshotReader.machineModel() == SensorRegistry.model,
          let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw ControlError.hardwareUnqualified }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 3840, height: 2160, mipmapped: false)
    descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
    guard let texture = device.makeTexture(descriptor: descriptor) else { throw ControlError.invalidSnapshot }
    let context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
    let rectangle = CGRect(x: 0, y: 0, width: 3840, height: 2160)
    guard let source = CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": 24.0])?.outputImage else { throw ControlError.invalidSnapshot }
    let reader = try SMCReader(), sampler = try HardwareSnapshotReader()
    let keys = Array(Set(SensorRegistry.chipEnvelopeKeys + SensorRegistry.mappings.flatMap(\.keys))).sorted()
    let start = ProcessInfo.processInfo.systemUptime
    var nextSample = start
    while ProcessInfo.processInfo.systemUptime - start < 180 {
        let now = ProcessInfo.processInfo.systemUptime, elapsed = now - start
        let phase: MeasurementPhase = elapsed < 30 ? .baseline : elapsed < 60 ? .gpu : .gpuCooldown
        let fresh = try sampler.snapshot()
        try MeasurementSafety.validate(fresh, now: ProcessInfo.processInfo.systemUptime)
        if now >= nextSample {
            let samples = try keys.map { try reader.read($0) }
            guard samples.allSatisfy({ $0.type == "flt " && $0.size == 4 && $0.error == nil &&
                $0.value.map { $0.isFinite && $0 > 0 && $0 < MeasurementSafety.ceilingC } == true }) else { throw ControlError.invalidSnapshot }
            let owned = try sampler.snapshot()
            try MeasurementSafety.validate(owned, now: ProcessInfo.processInfo.systemUptime)
            try emit(Record(timestamp: ISO8601DateFormatter().string(from: Date()), model: SensorRegistry.model,
                            os: ProcessInfo.processInfo.operatingSystemVersionString, phase: phase,
                            elapsed: elapsed, fans: owned.fans, keys: samples, hid: HIDTemperatureReader.read()))
            nextSample = ProcessInfo.processInfo.systemUptime + 1
        }
        if phase == .gpu && ProcessInfo.processInfo.systemUptime - start < 60 {
            let image = source.transformed(by: CGAffineTransform(translationX: elapsed * 12, y: elapsed * 6))
                .cropped(to: rectangle).clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 12.0]).cropped(to: rectangle)
                .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.8, "inputBrightness": 0.02])
            guard let command = queue.makeCommandBuffer() else { throw ControlError.invalidSnapshot }
            context.render(image, to: texture, commandBuffer: command, bounds: rectangle, colorSpace: CGColorSpaceCreateDeviceRGB())
            let finished = DispatchSemaphore(value: 0)
            command.addCompletedHandler { _ in finished.signal() }; command.commit()
            guard finished.wait(timeout: .now() + .milliseconds(250)) == .success, command.status == .completed else { throw ControlError.invalidSnapshot }
            Thread.sleep(forTimeInterval: max(0, 1.0 / 24 - (ProcessInfo.processInfo.systemUptime - now)))
        } else { Thread.sleep(forTimeInterval: 0.1) }
    }
    FileHandle.standardError.write(Data("GPU render capture completed: 180 seconds, no fan writes.\n".utf8))
}
do {
    if renderCycle { try captureRenderCycle(); exit(0) }
    guard HardwareSnapshotReader.machineModel() == SensorRegistry.model else { throw ControlError.hardwareUnqualified }
    let reader = try SMCReader(), sampler = try HardwareSnapshotReader()
    // Enumerate once, before the timed baseline. This catalog is discovery evidence only;
    // no prefix family is promoted into a production control mapping.
    let catalog = try reader.enumerate(prefix: "T")
    let selected = catalog.filter { sample in sample.type == "flt " && sample.size == 4 &&
        ["Tp", "Tm", "Tg"].contains { sample.key.hasPrefix($0) } }.map(\.key)
    let comfort = SensorRegistry.mappings.flatMap(\.keys)
    let measurementKeys = Array(Set(selected + comfort)).sorted()
    let started = ProcessInfo.processInfo.systemUptime
    let stimulus = try Stimulus(startedAt: started)
    defer { stimulus.stop() }
    stimulus.start()
    while MeasurementPhase.at(ProcessInfo.processInfo.systemUptime - started) != nil {
        let snapshot = try sampler.snapshot()
        try MeasurementSafety.validate(snapshot, now: ProcessInfo.processInfo.systemUptime)
        if let error = stimulus.error() { throw ControlError.invalidProfile(error) }
        let keys = measurementKeys.map { key -> DiscoveredSensor in
            do { return try reader.read(key) }
            catch { return DiscoveredSensor(key: key, type: "unknown", size: 0, attributes: 0, bytes: [], value: nil, error: error.localizedDescription) }
        }
        guard keys.allSatisfy({ key in
            guard let value = key.value else { return false }
            return key.type == "flt " && value.isFinite && value > 0 && value < MeasurementSafety.ceilingC
        }) else { throw ControlError.invalidSnapshot }
        let hid = HIDTemperatureReader.read()
        // Enumeration may block; reacquire ownership/temperatures before renewing stimulus admission.
        let fresh = try sampler.snapshot()
        try MeasurementSafety.validate(fresh, now: ProcessInfo.processInfo.systemUptime)
        let current = MeasurementPhase.at(ProcessInfo.processInfo.systemUptime - started)
        stimulus.update(current)
        if let current {
            try emit(Record(timestamp: ISO8601DateFormatter().string(from: Date()), model: SensorRegistry.model,
                            os: ProcessInfo.processInfo.operatingSystemVersionString, phase: current,
                            elapsed: ProcessInfo.processInfo.systemUptime - started, fans: fresh.fans, keys: keys, hid: hid))
        }
        Thread.sleep(forTimeInterval: max(0, 1 - (ProcessInfo.processInfo.systemUptime - fresh.sampledAt)))
    }
    FileHandle.standardError.write(Data("Measurement completed: 660-second bounded cycle, no fan writes.\n".utf8))
} catch {
    FileHandle.standardError.write(Data("Measurement aborted: \(error.localizedDescription)\n".utf8)); exit(1)
}
