import Foundation
import Testing
@testable import FandyCore

private func activationPlan() throws -> ManualQualificationPlan {
    try ManualQualificationPlan(capabilities: qualifiedCapabilities(stage: .manualQualification), actualModel: "Test",
        owner: UUID(), trial: .initial, snapshot: fixture(), now: 10, automaticVerified: true)
}
private func activationSnapshot(at time: Double, activated: Set<Int>) -> HardwareSnapshot {
    var snapshot = fixture(at: time)
    for index in snapshot.fans.indices where activated.contains(snapshot.fans[index].id) {
        snapshot.fans[index].mode = .manual
        snapshot.fans[index].targetRPM = snapshot.fans[index].actualRPM + 200
    }
    return snapshot
}

@Test func activationChecksEachFanAndPreservesOriginalDeadline() throws {
    let plan = try activationPlan()
    var activation = ManualQualificationActivation(plan: plan)
    #expect(try activation.authorizeNext(snapshot: activation.plan.baseline, now: 10) == plan.targets[0])
    let first = activationSnapshot(at: 11, activated: [0])
    try activation.didActivate(snapshot: first, now: 11)
    #expect(activation.activatedFanIDs == [0])
    #expect(try activation.authorizeNext(snapshot: first, now: 11) == plan.targets[1])
    let both = activationSnapshot(at: 12, activated: [0, 1])
    try activation.didActivate(snapshot: both, now: 12)
    var session = try activation.finish(snapshot: both, now: 12)
    #expect(session.plan.deadline == 15)
    #expect(session.check(snapshot: activationSnapshot(at: 15, activated: [0, 1]), now: 15) == .deadline)
}

@Test func blockingActivationCannotAdmitSecondFanAfterDeadline() throws {
    var activation = ManualQualificationActivation(plan: try activationPlan())
    _ = try activation.authorizeNext(snapshot: activation.plan.baseline, now: 10)
    #expect(throws: ControlError.staleSession) {
        try activation.didActivate(snapshot: activationSnapshot(at: 15, activated: [0]), now: 15)
    }
    #expect(activation.stopReason == .deadline)
    #expect(throws: ControlError.staleSession) {
        try activation.authorizeNext(snapshot: activationSnapshot(at: 16, activated: [0]), now: 16)
    }
}

@Test func activationRejectsCompetingOwnershipAndWrongTargetReadback() throws {
    for corruptTarget in [false, true] {
        var activation = ManualQualificationActivation(plan: try activationPlan())
        _ = try activation.authorizeNext(snapshot: activation.plan.baseline, now: 10)
        var snapshot = activationSnapshot(at: 11, activated: [0])
        if corruptTarget { snapshot.fans[0].targetRPM = 2700 }
        else { snapshot.fans[1].mode = .manual }
        #expect(throws: ControlError.restorationUnverified) { try activation.didActivate(snapshot: snapshot, now: 11) }
        #expect(activation.stopReason == .ownershipConflict)
    }
}

@Test func activationDoesNotLowerNewAppleDemandOrStartStoppedFan() throws {
    for rpm in [0.0, 2600, 2800] {
        var activation = ManualQualificationActivation(plan: try activationPlan())
        var snapshot = fixture(at: 11); snapshot.fans[0].actualRPM = rpm
        #expect(throws: ControlError.invalidFan) { try activation.authorizeNext(snapshot: snapshot, now: 11) }
        #expect(activation.stopReason == .hardwareChanged)
        #expect(activation.activatedFanIDs.isEmpty)
    }
}

@Test func partialActivationRechecksSensorsAndBoundsBeforeNextFan() throws {
    for kind in 0..<3 {
        var activation = ManualQualificationActivation(plan: try activationPlan())
        _ = try activation.authorizeNext(snapshot: activation.plan.baseline, now: 10)
        try activation.didActivate(snapshot: activationSnapshot(at: 11, activated: [0]), now: 11)
        var next = activationSnapshot(at: 12, activated: [0])
        if kind == 0 { next.sensors.removeAll { $0.role == .trackpad } }
        if kind == 1 { next.fans[1].maximumRPM -= 1 }
        if kind == 2 { next.sensors[0].celsius = 75 }
        #expect(throws: (any Error).self) { try activation.authorizeNext(snapshot: next, now: 12) }
        #expect(activation.stopReason == (kind == 1 ? .hardwareChanged : .sensorFailure))
        #expect(activation.activatedFanIDs == [0])
    }
}

@Test func activationRejectsNonadvancingOrMutatedAcquisition() throws {
    for reusedID in [false, true] {
        var activation = ManualQualificationActivation(plan: try activationPlan())
        let first = activationSnapshot(at: 11, activated: [])
        _ = try activation.authorizeNext(snapshot: first, now: 11)
        var next = activationSnapshot(at: 12, activated: [0])
        if reusedID { next.id = first.id }
        else { next.sensors[0].sequence = first.sensors[0].sequence }
        #expect(throws: ControlError.invalidSnapshot) { try activation.didActivate(snapshot: next, now: 12) }
        #expect(activation.stopReason == .sensorFailure)
    }
}

@Test func activationRejectsRepeatedAuthorizationAndIncompleteFinish() throws {
    var duplicate = ManualQualificationActivation(plan: try activationPlan())
    _ = try duplicate.authorizeNext(snapshot: duplicate.plan.baseline, now: 10)
    #expect(throws: ControlError.staleSession) { try duplicate.authorizeNext(snapshot: fixture(at: 11), now: 11) }
    #expect(duplicate.stopReason == .malformedRequest)
    var incomplete = ManualQualificationActivation(plan: try activationPlan())
    #expect(throws: ControlError.staleSession) { try incomplete.finish(snapshot: fixture(), now: 10) }
    #expect(incomplete.stopReason == .malformedRequest)
}

@Test func activationRevocationAndBadClocksCannotReactivate() throws {
    for now in [9.0, Double.nan, .infinity] {
        var activation = ManualQualificationActivation(plan: try activationPlan())
        #expect(throws: ControlError.invalidNumber) { try activation.authorizeNext(snapshot: fixture(), now: now) }
        #expect(activation.stopReason == .invalidClock)
    }
    var activation = ManualQualificationActivation(plan: try activationPlan())
    _ = try activation.authorizeNext(snapshot: activation.plan.baseline, now: 10)
    activation.stop(.disconnected)
    #expect(throws: ControlError.staleSession) { try activation.didActivate(snapshot: activationSnapshot(at: 11, activated: [0]), now: 11) }
    #expect(activation.stopReason == .disconnected)
}
