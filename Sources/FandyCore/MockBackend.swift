import Foundation
public enum MockScenario: String, CaseIterable, Sendable, Identifiable {
    case comfortableSchool = "Comfortable School", warmChassis = "Warm Chassis", gamingLoad = "Gaming Load", gpuHot = "GPU Hot", sensorFailure = "Sensor Failure", staleSensor = "Stale Sensor", helperDisconnected = "Helper Disconnected", overheating = "Overheating"
    public var id: String { rawValue }
}
public actor MockBackend: TemperatureSensorProvider, FanController {
    private var scenario: MockScenario = .comfortableSchool
    private var fans = [Fan(id: 0, min: 2317, max: 7826, actual: 0), Fan(id: 1, min: 2200, max: 7400, actual: 0)]
    private var now: Double = 0
    private var sequence: UInt64 = 0
    private var generation: UInt64 = 0
    private var safety = HelperSafety()
    private var owner = UUID()
    private var latest: HardwareSnapshot?
    public init() { safety.restorationFinished(true) }
    public func setScenario(_ scenario: MockScenario) { self.scenario = scenario }
    public func snapshot() throws -> HardwareSnapshot {
        now += 1; sequence += 1
        if safety.expired(at: now) { restoreInternal() }
        let chip: (Double,Double) = switch scenario { case .gamingLoad: (81,83); case .gpuHot: (65,87); case .overheating: (100,103); default: (48,44) }
        let warm = scenario == .warmChassis
        let values: [(SensorRole, Double)] = [(.cpuAverage,chip.0),(.cpuPeak,chip.0+1),(.gpuAverage,chip.1),(.gpuPeak,chip.1),(.socPeak,max(chip.0+1,chip.1)),(.cpuRegion,chip.0+1),(.gpuRegion,chip.1),(.trackpad,warm ? 31:27),(.actuator,warm ? 29:25),(.airflowLeft,warm ? 43:33),(.airflowTop,warm ? 44:33),(.airflowRight,warm ? 43:33),(.charger,33),(.powerSupply,33),(.wireless,32)]
        var readings = values.map { SensorReading($0.0, $0.1, at: now, sequence: sequence) }
        if scenario == .sensorFailure { readings.removeAll { $0.role == .gpuPeak } }
        if scenario == .staleSensor { for i in readings.indices { readings[i].sampledAt = now - 4 } }
        for i in fans.indices {
            let goal = fans[i].mode == .manual ? fans[i].targetRPM ?? fans[i].minimumRPM : (scenario == .gamingLoad || scenario == .gpuHot || scenario == .overheating ? fans[i].maximumRPM : 0)
            fans[i].actualRPM += (goal - fans[i].actualRPM) * 0.7
        }
        let snapshot = HardwareSnapshot(at: now, sensors: readings, fans: fans, pressure: scenario == .overheating ? .serious : .nominal)
        latest = snapshot; return snapshot
    }
    public func apply(_ targets: [FanTarget], generation requested: UInt64) throws {
        if scenario == .helperDisconnected { restoreInternal(); throw ControlError.helperUnavailable }
        do {
        guard let latest else { throw ControlError.invalidSnapshot }
        if requested != generation || safety.lease == nil {
            restoreInternal(); generation = requested
            _ = try safety.begin(owner: owner, generation: requested, required: Set(latest.sensors.map(\.role)), snapshot: latest, now: now)
        }
        let safe = try safety.validateAndRenew(owner: owner, leaseID: safety.lease!.id, generation: requested, targets: targets, snapshot: latest, now: now)
        for target in safe { if let index = fans.firstIndex(where: { $0.id == target.fanID }) { fans[index].mode = .manual; fans[index].targetRPM = target.rpm } }
        } catch { restoreInternal(); throw error }
    }
    public func restoreAutomatic() throws {
        if scenario == .helperDisconnected { restoreInternal(); throw ControlError.restorationUnverified }
        restoreInternal()
    }
    private func restoreInternal() {
        safety.revoke()
        for i in fans.indices { fans[i].mode = .automatic; fans[i].targetRPM = nil }
        safety.restorationFinished(true)
    }
    public func helperRestart() { safety = HelperSafety(); generation = 0; owner = UUID(); restoreInternal() }
    public func controllerDisconnected() { _ = safety.disconnect(owner: owner); restoreInternal() }
    public func advanceWithoutHeartbeat(_ seconds: Double) { now += seconds; if safety.expired(at: now) { restoreInternal() } }
}
