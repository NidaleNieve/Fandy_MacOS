import Foundation

/// Integrates sample-held demand over elapsed time, not the number of callers.
/// Missing history is filled with the first observed value, never invented zeros.
public struct TimeWeightedDemand: Sendable {
    private struct Sample: Sendable { let time: Double; let value: Double }
    private var samples: [Sample] = []
    public init() {}
    public mutating func reset() { samples = [] }
    public mutating func update(_ value: Double, at now: Double, window: Double) throws -> Double {
        guard value.isFinite, (0...100).contains(value), now.isFinite, window.isFinite, (0...15).contains(window) else { throw ControlError.invalidNumber }
        if let last = samples.last {
            guard now >= last.time else { reset(); throw ControlError.invalidNumber }
            if now - last.time > 3 { reset() }
        }
        if samples.last?.time == now { samples.removeLast() }
        samples.append(Sample(time: now, value: value))
        let start = now - window
        while samples.count > 1 && samples[1].time <= start { samples.removeFirst() }
        guard window > 0 else { return value }
        var total = 0.0, cursor = start, held = samples[0].value
        for sample in samples {
            if sample.time <= start { held = sample.value; continue }
            total += (sample.time - cursor) * held
            cursor = sample.time; held = sample.value
        }
        total += (now - cursor) * held
        return min(100, max(0, total / window))
    }
}

public struct ChipGuardReading: Codable, Sendable, Equatable {
    public let rawPercent: Double
    public let enforcedPercent: Double
    public let sampledAt: Double
    public let immediate: Bool
}

public enum ChipSource: String, Codable, CaseIterable, Sendable { case cpu, gpu }
public extension Profile {
    mutating func setChipSource(_ source: ChipSource, selected: Bool) {
        let index = curves.firstIndex { $0.input == .chip }
        if index.map({ !curves[$0].enabled }) ?? true, targetTemperature?.input != .chip { chipSources = [] }
        if selected { chipSources.insert(source) } else { chipSources.remove(source) }
        if let index { curves[index].enabled = !chipSources.isEmpty }
        else if selected { curves.append(FanCurve(.chip, [(45,0),(85,100)])) }
    }
    var responseWindow: Double { 15 * (1 - fanResponse) }
    var upwardRate: Double { 2 + 8 * fanResponse }
    func chipRoles(policy: ChipControlPolicy) -> Set<SensorRole> {
        if policy == .conservativeEnvelope && chipSources.count == 2 { return policy.required }
        return Set(chipSources.map { source in
            policy == .conservativeEnvelope ? (source == .cpu ? .cpuRegion : .gpuRegion) : (source == .cpu ? .cpuPeak : .gpuPeak)
        })
    }
    func temperature(for input: CurveInput, snapshot: HardwareSnapshot, now: Double, policy: ChipControlPolicy) throws -> Double {
        guard input == .chip else { return try input.temperature(in: snapshot, now: now, chipPolicy: policy) }
        guard !chipSources.isEmpty else { throw ControlError.invalidProfile("Select CPU or GPU for the chip temperature target.") }
        // The full envelope is exactly the union of the two fixed regional manifests.
        if policy == .conservativeEnvelope && chipSources.count == 2 {
            return try policy.temperature(in: snapshot, now: now)
        }
        return try chipRoles(policy: policy).map { try snapshot.value($0, now: now) }.max()!
    }
}
