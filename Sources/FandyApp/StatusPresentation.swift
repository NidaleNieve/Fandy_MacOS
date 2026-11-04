import Foundation
import FandyCore

enum StatusPresentation {
    /// Observed RPM on the same minimum-to-maximum scale as curves and floors.
    /// This remains an observation, not the engine's requested level.
    static func observedFanPercent(_ fans: [Fan]) -> Double {
        fans.compactMap { try? $0.percent(rpm: $0.actualRPM) }.max() ?? 0
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
        return (curves + target + ["Floor: \(Int(floor.rounded()))%"] ).joined(separator: " · ")
    }

}

extension AppModel {
    var edited: Profile? { profiles.first { $0.id == editorSelection } }
    var ownership: FanOwnership { FanOwnership.observe(snapshot, now: clockNow()) }
    var preview: ProfilePreview? {
        guard let edited, let snapshot, edited.kind != .system else { return nil }
        return try? ShadowProfileEngine.evaluate(edited, snapshot: snapshot, now: simulation ? snapshot.sampledAt : clockNow(), chipPolicy: machine.chipPolicy)
    }
    func temperatureText(_ role: SensorRole) -> String {
        let estimate = !simulation && capabilities.chipPolicy == .conservativeEnvelope && [.cpuAverage, .gpuAverage].contains(role)
        return StatusPresentation.temperature(snapshot?.sensors.first { $0.role == role },
            now: simulation ? snapshot?.sampledAt ?? clockNow() : clockNow(), estimate: estimate)
    }
    func curveTemperature(_ curve: FanCurve, profile: Profile) -> Double? {
        guard let snapshot else { return nil }
        return try? profile.temperature(for: curve.input, snapshot: snapshot, now: simulation ? snapshot.sampledAt : clockNow(), policy: machine.chipPolicy)
    }
    var statusText: String {
        if machine.state == .system, machine.fault == ControlError.thermalPressure.localizedDescription {
            return simulation ? "Simulation · " + ControlError.thermalPressure.localizedDescription : ControlError.thermalPressure.localizedDescription
        }
        if !simulation {
            if let hardwareError { return hardwareError }
            if capabilities.canRestore && (machine.selected.kind != .system || machine.state != .system) { return controlStatus }
            switch ownership {
            case .appleObserved: return "Monitoring · Apple automatic observed"
            case .manualObserved: return "Monitoring · external manual control observed"
            case .unknown: return "Monitoring · fan ownership unavailable"
            }
        }
        if machine.automaticAtIdle { return "Simulation · Apple auto at idle" }
        return "Simulation · \(controlStatus)"
    }
    private var controlStatus: String {
        if machine.automaticAtIdle && machine.state == .customActive { return "\(machine.selected.name) · Apple auto at idle" }
        return switch machine.state {
        case .system: "System"
        case .initializingCustom: "Starting \(machine.selected.name)…"
        case .customActive: machine.selected.name
        case .restoringSystem: "Returning to System…"
        case .fault: "Fan state unverified"
        }
    }
    func isSelected(_ id: String) -> Bool {
        if !simulation {
            if id == "system" { return machine.selected.kind == .system && ownership == .appleObserved && (!capabilities.canRestore || machine.state == .system) }
            guard capabilities.canControl, helperHealth == .controlReady else { return false }
        }
        return (machine.state == .system || machine.state == .customActive) && machine.selected.id == id
    }
}
