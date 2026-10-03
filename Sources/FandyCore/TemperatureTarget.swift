import Foundation

/// An optional proportional cooling goal. It never reduces existing curve or
/// chip-guard demand, and cannot promise an exact physical temperature.
public struct TemperatureTarget: Codable, Sendable, Equatable {
    public var input: CurveInput
    public var celsius: Double
    public init(input: CurveInput = .chip, celsius: Double = 75) { self.input = input; self.celsius = celsius }
    public func validate() throws {
        guard celsius.isFinite, (0...125).contains(celsius) else { throw ControlError.invalidProfile("Target temperature must be finite and between 0 and 125°C.") }
    }
    public static func defaultTemperature(for input: CurveInput) -> Double {
        switch input { case .chip: 75; case .trackpad: 29; case .actuator: 27; case .airflow: 36 }
    }
    /// Separate comfort scales: +/-10°C chip, +/-5°C surface, +/-8°C airflow.
    public var responseBand: Double {
        switch input { case .chip: 20; case .trackpad, .actuator: 10; case .airflow: 16 }
    }
    public func evaluate(_ temperature: Double) throws -> Double {
        try validate()
        guard temperature.isFinite else { throw ControlError.invalidNumber }
        return min(100, max(0, (0.5 + (temperature - celsius) / responseBand) * 100))
    }
    public func demand(in snapshot: HardwareSnapshot, now: Double, chipPolicy: ChipControlPolicy) throws -> Double {
        return try evaluate(input.temperature(in: snapshot, now: now, chipPolicy: chipPolicy))
    }
}
