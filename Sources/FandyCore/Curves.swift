import Foundation
public struct CurvePoint: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var temperature: Double
    public var percent: Double
    public init(_ temperature: Double, _ percent: Double, id: UUID = UUID()) { self.id = id; self.temperature = temperature; self.percent = percent }
}
public struct FanCurve: Codable, Sendable, Equatable {
    public var input: CurveInput
    public var enabled: Bool
    public var points: [CurvePoint]
    public init(_ input: CurveInput, _ pairs: [(Double, Double)], enabled: Bool = true) {
        self.input = input; self.enabled = enabled; points = pairs.map { CurvePoint($0.0, $0.1) }
    }
    public func validate() throws {
        guard (2...32).contains(points.count), Set(points.map(\.id)).count == points.count else { throw ControlError.invalidCurve("Use 2–32 unique nodes.") }
        for (index, point) in points.enumerated() {
            guard point.temperature.isFinite, point.percent.isFinite, (0...125).contains(point.temperature), (0...100).contains(point.percent) else { throw ControlError.invalidCurve("Nodes need finite temperatures (0–125°C) and speeds (0–100%).") }
            if index > 0 {
                guard point.temperature > points[index - 1].temperature else { throw ControlError.invalidCurve("Temperatures must strictly increase.") }
                guard point.percent >= points[index - 1].percent else { throw ControlError.invalidCurve("Hotter nodes cannot request less cooling.") }
            }
        }
    }
    public func evaluate(_ temperature: Double) throws -> Double {
        try validate()
        guard temperature.isFinite else { throw ControlError.invalidNumber }
        guard let first = points.first, let last = points.last else { throw ControlError.invalidCurve("Missing nodes.") }
        if temperature <= first.temperature { return first.percent }
        if temperature >= last.temperature { return last.percent }
        for index in 1..<points.count where temperature <= points[index].temperature {
            let a = points[index - 1], b = points[index]
            return a.percent + (temperature - a.temperature) / (b.temperature - a.temperature) * (b.percent - a.percent)
        }
        return last.percent
    }
    public func temperature(in snapshot: HardwareSnapshot, now: TimeInterval, chipPolicy: ChipControlPolicy = .cpuGPU) throws -> Double {
        return try input.temperature(in: snapshot, now: now, chipPolicy: chipPolicy)
    }
}
public extension CurveInput {
    func temperature(in snapshot: HardwareSnapshot, now: TimeInterval, chipPolicy: ChipControlPolicy = .cpuGPU) throws -> Double {
        switch self {
        case .chip: return try chipPolicy.temperature(in: snapshot, now: now)
        case .trackpad: return try snapshot.value(.trackpad, now: now)
        case .actuator: return try snapshot.value(.actuator, now: now)
        case .airflow: return try [SensorRole.airflowLeft, .airflowTop, .airflowRight].map { try snapshot.value($0, now: now) }.max()!
        }
    }
}
public enum ChipAggregation {
    public static func summarize(_ values: [Double]) throws -> (average: Double, peak: Double) {
        guard !values.isEmpty, values.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 150 }) else { throw ControlError.invalidSnapshot }
        return (values.reduce(0, +) / Double(values.count), values.max()!)
    }
}
/// One-way acoustic smoothing: raw rises are never smoothed; safety bypasses all limits.
public struct DemandGovernor: Sendable {
    public private(set) var output: Double = 0
    private var lastTime: Double?
    private var lowerSince: Double?
    private var filtered: Double = 0
    public init() {}
    public mutating func reset(_ value: Double = 0) { output = value; filtered = value; lastTime = nil; lowerSince = nil }
    public mutating func update(_ demand: Double, at now: Double, urgent: Bool = false) throws -> Double {
        guard demand.isFinite, now.isFinite, (0...100).contains(demand), lastTime.map({ now >= $0 }) ?? true else { throw ControlError.invalidNumber }
        let elapsed = lastTime.map { min(5, max(0, now - $0)) } ?? 1
        lastTime = now
        if urgent { output = max(output, demand); filtered = output; lowerSince = nil; return output }
        if demand >= output {
            output = min(demand, output + 10 * elapsed); filtered = output; lowerSince = nil
        } else if output - demand >= 2 {
            if lowerSince == nil { lowerSince = now; filtered = output }
            if now - lowerSince! >= 5 {
                filtered += (1 - exp(-elapsed / 5)) * (demand - filtered)
                output = max(demand, filtered, output - 2 * elapsed)
            }
        } else { lowerSince = nil; filtered = output }
        return output
    }
}
