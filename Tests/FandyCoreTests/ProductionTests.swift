import Foundation
import Testing
@testable import FandyCore

@Test func capabilityStagesCannotSkipSensorAndRestorationGates() {
    let full = qualifiedCapabilities()
    #expect(full.canControl); #expect(full.canRestore)
    #expect(!full.forMachine("Other").canRestore)
    let pending = HardwareCapabilities(model: "Test", stage: .qualifiedControl, topology: .verified,
                                      automaticRestoration: .verified, manualTransaction: .verified)
    #expect(pending.canRestore); #expect(pending.canControl); #expect(!pending.permits(BuiltInProfiles.gaming)); #expect(pending.permits(BuiltInProfiles.maximum))
    let restoration = qualifiedCapabilities(stage: .restorationQualification)
    #expect(restoration.canRestore); #expect(!restoration.canControl)
    #expect(!qualifiedCapabilities(stage: .manualQualification).canControl)
    #expect(!qualifiedCapabilities(stage: .observation).canRestore)
    let noAutoProof = HardwareCapabilities(model: "Test", stage: .qualifiedControl, sensors: full.sensors,
                                          topology: .verified, manualTransaction: .verified)
    #expect(noAutoProof.canRestore); #expect(!noAutoProof.canControl)
}
@Test func informationalProximityEvidenceDoesNotBlockUnrelatedPolicies() {
    let full = qualifiedCapabilities()
    let incomplete = HardwareCapabilities(model: full.model, stage: .qualifiedControl, sensors: full.sensors.filter { $0.role != .charger },
                                          topology: .verified, automaticRestoration: .verified, manualTransaction: .verified)
    #expect(!incomplete.allSensorsVerified); #expect(incomplete.canRestore)
    for profile in BuiltInProfiles.all where profile.kind != .system {
        #expect(ProfileEligibility.evaluate(profile, capabilities: incomplete, helper: .controlReady, snapshot: fixture(), now: 10).allowed)
    }
}
@Test func duplicateAndMalformedEvidenceCannotQualify() {
    let full = qualifiedCapabilities()
    let duplicate = HardwareCapabilities(model: "Test", sensors: full.sensors + [full.sensors[0]])
    #expect(!duplicate.allSensorsVerified)
    let bad = SensorEvidence(role: .cpuPeak, keys: ["NotASMCKey"], state: .verified, source: "Test", limitation: "")
    #expect(!HardwareCapabilities(model: "Test", sensors: [bad]).verifiedRoles.contains(.cpuPeak))
}
@Test func shadowDemandAdmitsCandidatesWithoutQualifyingOriginalSnapshot() throws {
    var snapshot = fixture()
    snapshot.sensors = snapshot.sensors.map { var s = $0; s.health = .unverified; return s }
    let preview = try ShadowProfileEngine.evaluate(BuiltInProfiles.gaming, snapshot: snapshot, now: 10)
    #expect(preview.usesCandidates); #expect(preview.profileID == "gaming")
    #expect(preview.snapshotID == snapshot.id)
    #expect(throws: (any Error).self) { try ProfileEngine().evaluate(BuiltInProfiles.gaming, snapshot: snapshot, now: 10) }
    #expect(snapshot.sensors.allSatisfy { $0.health == .unverified })
}
@Test func shadowDemandRejectsMissingStaleAndNonfiniteValues() {
    for temperature: Double? in [nil, .nan, .infinity] {
        var snapshot = fixture()
        snapshot.sensors[snapshot.sensors.firstIndex { $0.role == .gpuPeak }!].celsius = temperature
        #expect(throws: (any Error).self) { try ShadowProfileEngine.evaluate(BuiltInProfiles.gaming, snapshot: snapshot, now: 10) }
    }
    #expect(throws: (any Error).self) { try ShadowProfileEngine.evaluate(BuiltInProfiles.gaming, snapshot: fixture(), now: 14) }
}
@Test func ownershipRequiresFreshIndependentFanEvidence() {
    #expect(FanOwnership.observe(fixture(), now: 10) == .appleObserved)
    #expect(FanOwnership.observe(fixture(), now: 14) == .unknown)
    var snapshot = fixture(); snapshot.fans[0].mode = .manual
    #expect(FanOwnership.observe(snapshot, now: 10) == .manualObserved)
    snapshot.fans[0].mode = .unknown
    #expect(FanOwnership.observe(snapshot, now: 10) == .unknown)
}
@Test func restorationReportKeepsPartialResultsAndNeverClearsTargets() throws {
    let spy = FanSpy(); spy.failAuto = 0
    let report = try FanRestoration.report(using: spy)
    #expect(!report.verified); #expect(!report.fans[0].verified); #expect(report.fans[1].verified)
    #expect(report.fans[0].observedMode == .manual)
    #expect(spy.calls == ["auto0", "auto1"])
}
@Test func restorationRemainsIndependentOfBrokenTemperatures() {
    let spy = FanSpy(); spy.invalid = true
    let coordinator = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(stage: .restorationQualification),
                                        read: { spy.snapshot() }, clock: { spy.now })
    #expect(coordinator.restore())
    let status = coordinator.status()
    #expect(status.automaticVerified); #expect(!status.manualQualified); #expect(status.restoration?.verified == true)
    #expect(throws: (any Error).self) { _ = try coordinator.begin(LeaseRequest(generation: 1, required: []), owner: UUID()) }
}
@Test func helperReportsPartialFailureAndRetriesEveryFan() {
    let spy = FanSpy(); spy.failAuto = 1
    let coordinator = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(), read: { spy.snapshot() }, clock: { spy.now })
    #expect(!coordinator.restore()); #expect(coordinator.status().restoration?.fans[0].verified == true)
    spy.failAuto = nil; coordinator.watchdog()
    #expect(coordinator.status().restoration?.verified == true)
}
@Test func statusDetectsExternalOwnershipChangeDuringLease() throws {
    let spy = FanSpy(); let (coordinator, lease, owner) = try leasedCoordinator(spy)
    let snapshot = coordinator.status().snapshot!
    try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id,
                                        targets: [FanTarget(0, 3000), FanTarget(1, 3000)]), owner: owner)
    spy.fans[1].mode = .automatic
    _ = coordinator.status()
    #expect(spy.fans.allSatisfy { $0.mode == .automatic })
}
@Test func oldObservationStatusRemainsWireCompatible() throws {
    let data = Data("{\"version\":2,\"automaticVerified\":true,\"manualQualified\":false,\"observationOnly\":true}".utf8)
    let status = try Wire.decode(HelperStatus.self, from: data)
    #expect(status.capabilities == nil); #expect(status.restoration == nil); #expect(status.observationOnly)
}

@Test func automaticObservationCannotEraseFailedRestorationAttempt() {
    let spy = FanSpy(); spy.fans = spy.fans.map { var fan = $0; fan.mode = .automatic; return fan }; spy.failAuto = 0
    let coordinator = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(), read: { spy.snapshot() }, clock: { spy.now })
    #expect(!coordinator.restore()); #expect(!coordinator.status().automaticVerified)
    spy.failAuto = nil; coordinator.watchdog()
    #expect(coordinator.status().automaticVerified)
}

@Test func restorationFirstNeedsTopologyButNotSensorQualification() {
    let release = HardwareCapabilities(model: "Test", stage: .restorationQualification, topology: .verified)
    #expect(release.canRestore); #expect(!release.allSensorsVerified); #expect(!release.canControl)
    #expect(!release.forMachine("Other").canRestore)
    let noTopology = HardwareCapabilities(model: "Test", stage: .restorationQualification)
    #expect(!noTopology.canRestore)
    let spy = FanSpy()
    let coordinator = HelperCoordinator(io: spy, capabilities: release, read: { throw ControlError.invalidSnapshot }, clock: { spy.now })
    #expect(coordinator.startup())
    #expect(spy.fans.allSatisfy { $0.mode == .automatic })
    #expect(coordinator.status().startupRestoration?.fans.allSatisfy(\.releasedManual) == true)
    #expect(throws: ControlError.hardwareUnqualified) { _ = try coordinator.begin(LeaseRequest(generation: 1, required: []), owner: UUID()) }
    #expect(spy.calls == ["auto0", "auto1"])
}
@Test func startupRestorationProofSurvivesLaterIdempotentRequests() {
    let spy = FanSpy()
    let coordinator = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(stage: .restorationQualification), read: { spy.snapshot() }, clock: { spy.now })
    #expect(coordinator.startup()); #expect(coordinator.restore())
    let status = coordinator.status()
    #expect(status.startupRestoration?.fans.allSatisfy(\.releasedManual) == true)
    #expect(status.restoration?.fans.allSatisfy { $0.initialMode == .automatic && $0.commandSucceeded == true && $0.immediateMode == .automatic && $0.observedMode == .automatic } == true)
    #expect(status.restoration?.fans.allSatisfy(\.releasedManual) == false)
}
@Test func firmwareSystemStateIsUnqualifiedOwnership() {
    var snapshot = fixture(); snapshot.fans[0].mode = .system
    #expect(FanOwnership.observe(snapshot, now: 10) == .unknown)
}

@Test func restorationRetainsImmediateReadbackWhenFinalReadDetectsConflict() throws {
    let spy = FanSpy(); spy.conflictOnFinalRead = true
    let report = try FanRestoration.report(using: spy)
    #expect(!report.verified)
    #expect(report.fans[0].initialMode == .manual)
    #expect(report.fans[0].commandSucceeded == true)
    #expect(report.fans[0].immediateMode == .automatic)
    #expect(report.fans[0].observedMode == .manual)
    #expect(report.fans[0].failure != nil); #expect(report.fans[1].verified)
}

@Test func diagnosticStimuliRequireFreshAutomaticOwnershipAndConservativeThermals() throws {
    var snapshot = fixture()
    snapshot.sensors = snapshot.sensors.map { var r = $0; r.health = .unverified; return r }
    try MeasurementSafety.validate(snapshot, now: 10)
    for mode in [FanMode.manual, .system, .unknown] {
        var bad = snapshot; bad.fans[0].mode = mode
        #expect(throws: (any Error).self) { try MeasurementSafety.validate(bad, now: 10) }
    }
    for value: Double? in [75, .nan, .infinity, nil] {
        var bad = snapshot; bad.sensors[bad.sensors.firstIndex { $0.role == .cpuPeak }!].celsius = value
        #expect(throws: (any Error).self) { try MeasurementSafety.validate(bad, now: 10) }
    }
    for pressure in [ThermalPressure.serious, .critical, .unknown] {
        var bad = snapshot; bad.thermalPressure = pressure
        #expect(throws: (any Error).self) { try MeasurementSafety.validate(bad, now: 10) }
    }
    #expect(throws: (any Error).self) { try MeasurementSafety.validate(snapshot, now: 12.1) }
}
@Test func measurementScheduleIsBoundedAndDoesNotRepeatStimuli() {
    #expect(MeasurementPhase.at(0) == .baseline); #expect(MeasurementPhase.at(59.9) == .baseline)
    #expect(MeasurementPhase.at(60) == .cpu); #expect(MeasurementPhase.at(90) == .cpuCooldown)
    #expect(MeasurementPhase.at(210) == .gpu); #expect(MeasurementPhase.at(240) == .gpuCooldown)
    #expect(MeasurementPhase.at(360) == .chassis)
    for elapsed in [960.0, -1, .nan, .infinity] { #expect(MeasurementPhase.at(elapsed) == nil) }
}

@Test func idleExternalOwnershipConflictDoesNotStartAWriteFight() {
    let spy = FanSpy()
    let coordinator = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(stage: .restorationQualification), read: { spy.snapshot() }, clock: { spy.now })
    #expect(coordinator.startup())
    spy.fans[0].mode = .manual
    let calls = spy.calls
    #expect(!coordinator.status().automaticVerified)
    coordinator.watchdog(); coordinator.watchdog()
    #expect(spy.calls == calls); #expect(spy.fans[0].mode == .manual)
    #expect(coordinator.restore()); #expect(coordinator.status().automaticVerified)
}

@Test func maximumPolicyNeedsMechanicalProofButNoTemperatureIdentities() throws {
    let caps = HardwareCapabilities(model: "Test", stage: .maximumControl, topology: .verified,
        automaticRestoration: .verified, manualTransaction: .verified)
    #expect(caps.canControl); #expect(caps.permits(BuiltInProfiles.maximum))
    #expect(!caps.permits(BuiltInProfiles.gaming)); #expect(!caps.permits(required: SensorRole.safety))
    #expect(caps.permits(required: [])); #expect(!caps.forMachine("Other").canControl)
    let spy = FanSpy(); spy.invalid = true
    let coordinator = HelperCoordinator(io: spy, capabilities: caps, read: { spy.snapshot() }, clock: { spy.now })
    #expect(coordinator.startup())
    for _ in 0..<5 { _ = coordinator.status() }
    let owner = UUID(), lease = try coordinator.begin(LeaseRequest(generation: 1, required: []), owner: owner)
    let snapshot = coordinator.status().snapshot!
    let targets = snapshot.fans.map { FanTarget($0.id, $0.maximumRPM) }
    try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id, targets: targets), owner: owner)
    #expect(spy.fans.map(\.targetRPM) == [8000, 7400])
    spy.now += 1; coordinator.watchdog(); #expect(spy.fans.allSatisfy { $0.mode == .manual })
    spy.now += 10; coordinator.watchdog(); #expect(spy.fans.allSatisfy { $0.mode == .automatic })
}
@Test func maximumLeaseCannotBeUsedToRequestLowerSpeedOrUnknownFan() throws {
    let caps = HardwareCapabilities(model: "Test", stage: .maximumControl, topology: .verified,
        automaticRestoration: .verified, manualTransaction: .verified)
    for malformed in [[FanTarget(0, 4000), FanTarget(1, 7400)], [FanTarget(0, 8000), FanTarget(99, 7400)]] {
        let spy = FanSpy()
        let coordinator = HelperCoordinator(io: spy, capabilities: caps, read: { spy.snapshot() }, clock: { spy.now })
        #expect(coordinator.startup()); for _ in 0..<5 { _ = coordinator.status() }
        #expect(throws: ControlError.hardwareUnqualified) { try coordinator.begin(LeaseRequest(generation: 1, required: SensorRole.safety), owner: UUID()) }
        let owner = UUID(), lease = try coordinator.begin(LeaseRequest(generation: 1, required: []), owner: owner)
        let snapshot = coordinator.status().snapshot!
        #expect(throws: ControlError.invalidFan) {
            try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id, targets: malformed), owner: owner)
        }
        #expect(spy.fans.allSatisfy { $0.mode == .automatic }); #expect(!spy.calls.contains("manual0"))
    }
}
@Test func maximumEngineUsesEachFanLimitAndRefusesStaleHardwareOrThermalPressure() throws {
    var snapshot = fixture(); snapshot.sensors = []
    #expect(BuiltInProfiles.maximum.requiredSensors.isEmpty)
    #expect(try ProfileEngine().evaluate(BuiltInProfiles.maximum, snapshot: snapshot, now: 10).percent == 100)
    #expect(throws: (any Error).self) { try ProfileEngine().evaluate(BuiltInProfiles.maximum, snapshot: snapshot, now: 14) }
    snapshot.thermalPressure = .serious
    #expect(throws: ControlError.thermalPressure) { try ProfileEngine().evaluate(BuiltInProfiles.maximum, snapshot: snapshot, now: 10) }
}

@Test func changedTargetOrKnownControllerDuringMaximumLeaseRestoresInsteadOfCompeting() throws {
    let caps = HardwareCapabilities(model: "Test", stage: .maximumControl, topology: .verified,
        automaticRestoration: .verified, manualTransaction: .verified)
    for mode in 0..<2 {
        let spy = FanSpy(); var conflict = false
        let coordinator = HelperCoordinator(io: spy, capabilities: caps, read: { spy.snapshot() }, clock: { spy.now },
            requireExclusive: { if conflict { throw ControlError.unauthorized } })
        #expect(coordinator.startup()); for _ in 0..<5 { _ = coordinator.status() }
        let owner = UUID(), lease = try coordinator.begin(LeaseRequest(generation: 1, required: []), owner: owner)
        let snapshot = coordinator.status().snapshot!
        try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id,
            targets: snapshot.fans.map { FanTarget($0.id, $0.maximumRPM) }), owner: owner)
        if mode == 0 { spy.fans[0].targetRPM = 4000 } else { conflict = true }
        spy.now += 1; coordinator.watchdog()
        #expect(spy.fans.allSatisfy { $0.mode == .automatic })
    }
}

@Test func persistentStoppedFanWhileHeartbeatContinuesReturnsToSystem() throws {
    let caps = HardwareCapabilities(model: "Test", stage: .maximumControl, topology: .verified,
        automaticRestoration: .verified, manualTransaction: .verified)
    let spy = FanSpy()
    let coordinator = HelperCoordinator(io: spy, capabilities: caps, read: { spy.snapshot() }, clock: { spy.now })
    #expect(coordinator.startup()); for _ in 0..<5 { _ = coordinator.status() }
    let owner = UUID(), lease = try coordinator.begin(LeaseRequest(generation: 1, required: []), owner: owner)
    func send() throws {
        let snapshot = coordinator.status().snapshot!
        try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id,
            targets: snapshot.fans.map { FanTarget($0.id, $0.maximumRPM) }), owner: owner)
    }
    try send(); spy.fans[0].actualRPM = 0
    spy.now += 5; try send(); coordinator.watchdog(); #expect(spy.fans[0].mode == .manual)
    spy.now += 5; try send(); coordinator.watchdog()
    #expect(spy.fans.allSatisfy { $0.mode == .automatic })
}
