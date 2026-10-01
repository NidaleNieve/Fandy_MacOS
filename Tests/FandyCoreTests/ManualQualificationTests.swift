import Foundation
import Testing
@testable import FandyCore

private func qualificationPlan(_ trial: ManualQualificationPlan.Trial = .initial) throws -> ManualQualificationPlan {
    try ManualQualificationPlan(capabilities: qualifiedCapabilities(stage: .manualQualification), actualModel: "Test",
                                owner: UUID(), trial: trial, snapshot: fixture(), now: 10, automaticVerified: true)
}
private func manualSnapshot(at time: Double) -> HardwareSnapshot {
    var snapshot = fixture(at: time)
    snapshot.fans = snapshot.fans.map { var fan = $0; fan.mode = .manual; return fan }
    return snapshot
}

@Test func qualificationAuthorityIsSeparateFromProductionAndRestoration() {
    for stage in [HardwareStage.observation, .restorationQualification, .qualifiedControl] {
        let caps = qualifiedCapabilities(stage: stage)
        #expect(!caps.canQualifyManual)
        #expect(throws: ControlError.hardwareUnqualified) {
            try ManualQualificationPlan(capabilities: caps, actualModel: "Test", owner: UUID(), trial: .initial,
                                        snapshot: fixture(), now: 10, automaticVerified: true)
        }
    }
    let caps = qualifiedCapabilities(stage: .manualQualification)
    #expect(caps.canQualifyManual); #expect(!caps.canControl)
    #expect(!caps.forMachine("Other").canQualifyManual)
}
@Test func qualificationRequiresEveryRoleAndPriorAutomaticProof() {
    let full = qualifiedCapabilities(stage: .manualQualification)
    for missing in HardwareCapabilities.requiredRoles {
        let caps = HardwareCapabilities(model: full.model, stage: .manualQualification,
            sensors: full.sensors.filter { $0.role != missing }, topology: .verified, automaticRestoration: .verified)
        #expect(!caps.canQualifyManual)
    }
    #expect(!HardwareCapabilities(model: full.model, stage: .manualQualification, sensors: full.sensors,
                                  topology: .verified).canQualifyManual)
    #expect(throws: ControlError.restorationUnverified) {
        try ManualQualificationPlan(capabilities: full, actualModel: "Test", owner: UUID(), trial: .initial,
                                    snapshot: fixture(), now: 10, automaticVerified: false)
    }
}
@Test func qualificationTargetsUseFreshPerFanSpeedsAndLimits() throws {
    let plan = try qualificationPlan()
    #expect(plan.targets == [FanTarget(0, 2600), FanTarget(1, 2500)])
    #expect(plan.deadline == 15)
    #expect(try qualificationPlan(.recovery).deadline == 25)
    var snapshot = fixture(); snapshot.fans[1].actualRPM = 7200
    let atBound = try ManualQualificationPlan(capabilities: qualifiedCapabilities(stage: .manualQualification), actualModel: "Test",
        owner: UUID(), trial: .initial, snapshot: snapshot, now: 10, automaticVerified: true)
    #expect(atBound.targets[1].rpm == 7400)
}
@Test func qualificationSkipsStoppedOrCeilingLimitedFansInsteadOfClamping() {
    for speed in [0.0, 7201, Double.nan, Double.infinity] {
        var snapshot = fixture(); snapshot.fans[1].actualRPM = speed
        #expect(throws: (any Error).self) {
            try ManualQualificationPlan(capabilities: qualifiedCapabilities(stage: .manualQualification), actualModel: "Test",
                owner: UUID(), trial: .initial, snapshot: snapshot, now: 10, automaticVerified: true)
        }
    }
}
@Test func qualificationNeverStartsStoppedFanEvenWithZeroReportedMinimum() {
    var snapshot = fixture(); snapshot.fans[0].minimumRPM = 0; snapshot.fans[0].actualRPM = 0
    #expect(throws: ControlError.invalidFan) {
        try ManualQualificationPlan(capabilities: qualifiedCapabilities(stage: .manualQualification), actualModel: "Test",
            owner: UUID(), trial: .initial, snapshot: snapshot, now: 10, automaticVerified: true)
    }
}
@Test func qualificationRejectsOwnershipStaleCandidateAndThermalUncertainty() {
    var bad: [HardwareSnapshot] = []
    var snapshot = fixture(); snapshot.fans[0].mode = .manual; bad.append(snapshot)
    snapshot = fixture(); snapshot.sensors[0].health = .unverified; bad.append(snapshot)
    snapshot = fixture(); snapshot.sensors.removeAll { $0.role == .charger }; bad.append(snapshot)
    snapshot = fixture(cpu: 75); bad.append(snapshot)
    snapshot = fixture(pressure: .serious); bad.append(snapshot)
    snapshot = fixture(at: 7); bad.append(snapshot)
    snapshot = fixture(); snapshot.sensors[0].sampledAt = 7.5; bad.append(snapshot)
    snapshot = fixture(); snapshot.sensors[0].celsius = .nan; bad.append(snapshot)
    snapshot = fixture(); snapshot.sensors[0].celsius = .infinity; bad.append(snapshot)
    for snapshot in bad {
        #expect(throws: (any Error).self) {
            try ManualQualificationPlan(capabilities: qualifiedCapabilities(stage: .manualQualification), actualModel: "Test",
                owner: UUID(), trial: .initial, snapshot: snapshot, now: 10, automaticVerified: true)
        }
    }
}
@Test func initialQualificationDeadlineCannotBeRenewedByHeartbeats() throws {
    let plan = try qualificationPlan(); var session = ManualQualificationSession(plan: plan)
    for time in 11...14 {
        try session.heartbeat(owner: plan.owner, sessionID: plan.id, snapshot: manualSnapshot(at: Double(time)), now: Double(time))
    }
    #expect(session.active)
    #expect(session.check(snapshot: manualSnapshot(at: 15), now: 15) == .deadline)
    #expect(!session.active)
    #expect(throws: ControlError.staleSession) {
        try session.heartbeat(owner: plan.owner, sessionID: plan.id, snapshot: manualSnapshot(at: 16), now: 16)
    }
    #expect(session.check(snapshot: nil, now: 17) == .deadline)
}
@Test func recoveryQualificationExpiresHeartbeatOrAbsoluteDeadline() throws {
    let plan = try qualificationPlan(.recovery)
    var noHeartbeat = ManualQualificationSession(plan: plan)
    #expect(noHeartbeat.check(snapshot: manualSnapshot(at: 19), now: 19) == nil)
    #expect(noHeartbeat.check(snapshot: manualSnapshot(at: 20), now: 20) == .heartbeat)
    var renewed = ManualQualificationSession(plan: plan)
    for time in [11.0, 19, 24] {
        try renewed.heartbeat(owner: plan.owner, sessionID: plan.id, snapshot: manualSnapshot(at: time), now: time)
    }
    #expect(renewed.check(snapshot: manualSnapshot(at: 25), now: 25) == .deadline)
}
@Test func qualificationRejectsWrongOwnerAndRevokesMalformedOwnedHeartbeat() throws {
    let plan = try qualificationPlan(); var session = ManualQualificationSession(plan: plan)
    #expect(throws: ControlError.unauthorized) {
        try session.heartbeat(owner: UUID(), sessionID: plan.id, snapshot: manualSnapshot(at: 11), now: 11)
    }
    #expect(session.active); #expect(session.lastHeartbeat == 10)
    session.disconnect(owner: UUID()); #expect(session.active)
    #expect(throws: ControlError.staleSession) {
        try session.heartbeat(owner: plan.owner, sessionID: UUID(), snapshot: manualSnapshot(at: 11), now: 11)
    }
    #expect(session.stopReason == .malformedRequest)
    session.disconnect(owner: plan.owner); #expect(session.stopReason == .malformedRequest)
}
@Test func qualificationRevokesOnSensorFailureConflictAndHardwareChange() throws {
    let plan = try qualificationPlan()
    var absent = ManualQualificationSession(plan: plan)
    #expect(absent.check(snapshot: nil, now: 11) == .sensorFailure)
    var conflict = ManualQualificationSession(plan: plan)
    #expect(conflict.check(snapshot: fixture(at: 11), now: 11) == .ownershipConflict)
    var changed = manualSnapshot(at: 11); changed.fans[1].maximumRPM -= 1
    var topology = ManualQualificationSession(plan: plan)
    #expect(topology.check(snapshot: changed, now: 11) == .hardwareChanged)
    var stale = manualSnapshot(at: 11)
    stale.sensors = stale.sensors.map { var s = $0; s.sequence = 10; return s }
    var acquisition = ManualQualificationSession(plan: plan)
    #expect(acquisition.check(snapshot: stale, now: 11) == .sensorFailure)
}
@Test func qualificationChecksDoNotConfuseConstantTemperaturesWithStoppedAcquisition() throws {
    let plan = try qualificationPlan(); var session = ManualQualificationSession(plan: plan)
    let fresh = manualSnapshot(at: 11)
    #expect(session.check(snapshot: fresh, now: 11) == nil)
    #expect(session.check(snapshot: fresh, now: 11.5) == nil)
    #expect(session.check(snapshot: manualSnapshot(at: 12), now: 12) == nil)
    var corruptedSameID = fresh; corruptedSameID.sampledAt = 12
    var second = ManualQualificationSession(plan: plan)
    #expect(second.check(snapshot: fresh, now: 11) == nil)
    #expect(second.check(snapshot: corruptedSameID, now: 12) == .sensorFailure)
}
@Test func qualificationPowerDisconnectAndBadClocksRevokeWithoutReactivation() throws {
    let plan = try qualificationPlan(.recovery)
    var disconnected = ManualQualificationSession(plan: plan)
    disconnected.disconnect(owner: plan.owner); #expect(disconnected.stopReason == .disconnected)
    var sleeping = ManualQualificationSession(plan: plan)
    sleeping.stop(.powerTransition); #expect(!sleeping.active)
    for time in [9.0, .nan, .infinity] {
        var clock = ManualQualificationSession(plan: plan)
        #expect(clock.check(snapshot: manualSnapshot(at: 11), now: time) == .invalidClock)
    }
}
