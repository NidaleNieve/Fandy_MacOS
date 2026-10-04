import Foundation
import FandyCore

/// Per-input requested airflow before other sensors, chip guard and smoothing.
/// Uses production interpolation/target math without changing editable nodes.
struct CurveRequestPreview {
    var floor: Double = 0
    var target: TemperatureTarget?
    func percent(at temperature: Double, curve: FanCurve) throws -> Double {
        guard floor.isFinite, (0...100).contains(floor), temperature.isFinite else { throw ControlError.invalidNumber }
        try curve.validate()
        let base = curve.enabled ? try curve.evaluate(temperature) : 0
        let goal = target?.input == curve.input ? try target?.evaluate(temperature) ?? 0 : 0
        return max(base, floor, goal)
    }
    func range(for curve: FanCurve) -> ClosedRange<Double> {
        let base = CurveDraft(curve).range
        guard let target, target.input == curve.input, (try? target.validate()) != nil else { return base }
        return min(base.lowerBound, max(0, target.celsius - target.responseBand / 2))...max(base.upperBound, min(125, target.celsius + target.responseBand / 2))
    }
    func hasOverlay(for input: CurveInput) -> Bool { floor > 0 || target?.input == input }
}
