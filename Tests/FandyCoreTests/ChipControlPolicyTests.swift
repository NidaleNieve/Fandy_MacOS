import Foundation
import Testing
@testable import FandyCore

private func envelopeSnapshot(_ value: Double = 80) -> HardwareSnapshot {
    var snapshot = fixture()
    snapshot.sensors.removeAll { $0.role == .socPeak }
    snapshot.sensors.append(SensorReading(.socPeak, value, at: 10, sequence: 1))
    for index in snapshot.sensors.indices where [.cpuAverage, .gpuAverage, .cpuPeak, .gpuPeak].contains(snapshot.sensors[index].role) {
        snapshot.sensors[index].health = .unverified
    }
    return snapshot
}
private func envelopeCapabilities(stage: HardwareStage = .qualifiedControl) -> HardwareCapabilities {
    HardwareCapabilities(model: "Test", stage: stage,
        sensors: [SensorEvidence(role: .socPeak, keys: ["Tp00", "Tm00", "Tg0U"], state: .verified,
                                 source: "Test model-specific envelope", limitation: "No individual core identity")],
        topology: .verified, automaticRestoration: .verified, manualTransaction: .verified,
        chipControl: .conservativeEnvelope)
}
@Test func envelopeDoesNotQualifyCPUOrGPUIdentity() throws {
    let capabilities = envelopeCapabilities()
    #expect(capabilities.verifiedRoles == [.socPeak])
    #expect(!capabilities.allSensorsVerified)
    #expect(capabilities.permits(BuiltInProfiles.systemPlus))
    #expect(capabilities.permits(BuiltInProfiles.gaming))
    #expect(!capabilities.permits(BuiltInProfiles.coolChassis))
    #expect(!capabilities.permits(required: [.cpuPeak, .gpuPeak]))
    #expect(capabilities.permits(required: [.socPeak]))
    #expect(envelopeCapabilities(stage: .curveQualification).canQualifyCurves)
    #expect(!envelopeCapabilities(stage: .curveQualification).permits(BuiltInProfiles.gaming))
}
@Test func envelopeDemandIgnoresUnverifiedDisplayEstimates() throws {
    let snapshot = envelopeSnapshot()
    let demand = try ProfileEngine().evaluate(BuiltInProfiles.systemPlus, snapshot: snapshot, now: 10, chipPolicy: .conservativeEnvelope)
    #expect(demand.percent == 80)
    #expect(demand.safetyPercent == 70)
    #expect(throws: (any Error).self) { try ProfileEngine().evaluate(BuiltInProfiles.systemPlus, snapshot: snapshot, now: 10) }
    #expect(ProfileEligibility.evaluate(BuiltInProfiles.gaming, capabilities: envelopeCapabilities(), helper: .controlReady,
                                        snapshot: snapshot, now: 10).allowed)
}
@Test func missingOrUnverifiedEnvelopeNeverFallsBackToDisplayReadings() {
    for health in [ReadingHealth.missing, .corrupt, .stale, .unverified] {
        var snapshot = envelopeSnapshot()
        snapshot.sensors[snapshot.sensors.firstIndex { $0.role == .socPeak }!].health = health
        #expect(throws: (any Error).self) { try ProfileEngine().evaluate(BuiltInProfiles.gaming, snapshot: snapshot, now: 10, chipPolicy: .conservativeEnvelope) }
    }
    #expect(throws: (any Error).self) { try ProfileEngine().evaluate(BuiltInProfiles.gaming, snapshot: envelopeSnapshot(), now: 14, chipPolicy: .conservativeEnvelope) }
}
@Test func envelopeGuardWinsEvenWhenChipCurveDisabled() throws {
    var profile = BuiltInProfiles.gaming; profile.curves[0].enabled = false
    let demand = try ProfileEngine().evaluate(profile, snapshot: envelopeSnapshot(85), now: 10, chipPolicy: .conservativeEnvelope)
    #expect(demand.percent == 100); #expect(demand.safetyPercent == 100)
    #expect(profile.requiredSensors(chipPolicy: .conservativeEnvelope) == [.socPeak])
    #expect(BuiltInProfiles.maximum.requiredSensors(chipPolicy: .conservativeEnvelope).isEmpty)
}
@Test func envelopeStateMachineTransmitsOnlyItsCompiledRequiredRole() throws {
    var machine = ControlMachine(chipPolicy: .conservativeEnvelope)
    _ = try machine.select(BuiltInProfiles.gaming)
    var effect = ControlEffect.none
    for _ in 0..<5 { effect = machine.step(envelopeSnapshot(), now: 10) }
    guard case .apply(_, let generation, _, let required) = effect else { Issue.record("Expected an envelope-based command"); return }
    #expect(required == [.socPeak]); #expect(machine.state == .initializingCustom)
    machine.applied(generation: generation); #expect(machine.state == .customActive)
    var lost = envelopeSnapshot(); lost.sensors.removeAll { $0.role == .socPeak }
    guard case .restore = machine.step(lost, now: 10) else { Issue.record("Missing envelope must restore"); return }
    #expect(machine.selected.kind == .system)
}
@Test func helperEnforcesEnvelopeEscalationIndependently() throws {
    var safety = HelperSafety(chipPolicy: .conservativeEnvelope); safety.restorationFinished(true)
    let snapshot = envelopeSnapshot(85), owner = UUID()
    let lease = try safety.begin(owner: owner, generation: 1, required: [.socPeak], snapshot: snapshot, now: 10)
    let low = snapshot.fans.map { FanTarget($0.id, $0.minimumRPM) }
    let safe = try safety.validateAndRenew(owner: owner, leaseID: lease.id, generation: 1, targets: low, snapshot: snapshot, now: 10)
    #expect(safe == snapshot.fans.map { FanTarget($0.id, $0.maximumRPM) })
}
@Test func olderCapabilitiesDecodeToOriginalChipPolicy() throws {
    let encoded = try JSONEncoder().encode(envelopeCapabilities())
    var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    object.removeValue(forKey: "chipControl")
    let restored = try JSONDecoder().decode(HardwareCapabilities.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(restored.chipPolicy == .cpuGPU)
    #expect(!restored.permits(BuiltInProfiles.gaming))
}
@Test func helperEnvelopeLossAndWatchdogEscalationUseTheSamePolicy() throws {
    let spy = FanSpy(); var temperature = 40.0; var lost = false
    let coordinator = HelperCoordinator(io: spy, capabilities: envelopeCapabilities(), read: {
        var snapshot = spy.snapshot()
        snapshot.sensors = snapshot.sensors.filter { ![SensorRole.cpuPeak, .gpuPeak, .socPeak].contains($0.role) }
        if !lost { snapshot.sensors.append(SensorReading(.socPeak, temperature, at: spy.now, sequence: UInt64(spy.now * 100))) }
        return snapshot
    }, clock: { spy.now })
    #expect(coordinator.startup())
    for _ in 0..<5 { _ = coordinator.status() }
    let owner = UUID(), lease = try coordinator.begin(LeaseRequest(generation: 1, required: [.socPeak]), owner: owner)
    let snapshot = coordinator.status().snapshot!
    try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id,
                                       targets: snapshot.fans.map { FanTarget($0.id, $0.minimumRPM) }), owner: owner)
    temperature = 85; spy.now += 1; coordinator.watchdog()
    #expect(coordinator.status().snapshot!.fans.allSatisfy { $0.targetRPM == $0.maximumRPM })
    lost = true; spy.now += 1; coordinator.watchdog()
    #expect(spy.snapshot().fans.allSatisfy { $0.mode == .automatic })
    #expect(coordinator.lastRestoration?.verified == true)
}
@Test func envelopeShadowDoesNotMislabelUnverifiedDisplayAveragesAsControlInputs() throws {
    let result = try ShadowProfileEngine.evaluate(BuiltInProfiles.gaming, snapshot: envelopeSnapshot(), now: 10, chipPolicy: .conservativeEnvelope)
    #expect(!result.usesCandidates)
    var snapshot = envelopeSnapshot(); snapshot.sensors[snapshot.sensors.firstIndex { $0.role == .socPeak }!].health = .unverified
    #expect(try ShadowProfileEngine.evaluate(BuiltInProfiles.gaming, snapshot: snapshot, now: 10, chipPolicy: .conservativeEnvelope).usesCandidates)
}
