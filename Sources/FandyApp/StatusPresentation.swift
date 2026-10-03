import Foundation
import FandyCore

enum StatusPresentation {
    /// Actual RPM as a fraction of reported maximum: stopped is 0%, regardless
    /// of manual minimum. This is observation, not the engine's requested level.
    static func observedFanPercent(_ fans: [Fan]) -> Double {
        fans.compactMap { fan -> Double? in
            guard fan.actualRPM.isFinite, fan.maximumRPM.isFinite, fan.maximumRPM > 0 else { return nil }
            return min(100, max(0, fan.actualRPM / fan.maximumRPM * 100))
        }.max() ?? 0
    }
    static func temperature(_ reading: SensorReading?, now: Double, estimate: Bool = false) -> String {
        guard var display = reading else { return "Unavailable" }
        let candidate = display.health == .unverified
        // This copy is only for display. Control continues to reject unverified inputs.
        if candidate { display.health = .valid }
        guard let value = try? display.value(now: now) else { return "Unavailable" }
        let suffix = candidate ? estimate ? " · estimate" : " · candidate" : ""
        return String(format: "%.1f°C%@", value, suffix)
    }
    static func demand(_ preview: ProfilePreview, active: Bool) -> String {
        let title = active ? "Calculated demand" : "Preview"
        let provenance = preview.usesCandidates ? " · candidate inputs" : ""
        return "\(title): \(Int(preview.percent.rounded()))%\(provenance)\(active ? "" : " · no fan commands")"
    }
    static func breakdown(_ preview: ProfilePreview, floor: Double) -> String {
        let curves = CurveInput.allCases.compactMap { input -> String? in
            guard let demand = preview.byCurve[input] else { return nil }
            return "\(input.label): \(Int(demand.rounded()))%"
        }
        let target = preview.targetPercent.map { ["Target: \(Int($0.rounded()))%"] } ?? []
        return (curves + target + ["Floor: \(Int(floor.rounded()))%", "Chip guard: \(Int(preview.safetyPercent.rounded()))%"] ).joined(separator: " · ")
    }

}
