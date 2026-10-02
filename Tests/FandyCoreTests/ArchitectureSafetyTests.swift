import Foundation
import Testing
@testable import FandyCore

@Test func idleReadFailureDoesNotAcquireExternalFanOwnership() {
    let spy = FanSpy()
    let coordinator = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(), read: {
        if spy.inventoryFailure { throw ControlError.invalidSnapshot }
        return spy.snapshot()
    }, clock: { spy.now })
    #expect(coordinator.startup())
    spy.calls = []; spy.fans[0].mode = .manual; spy.inventoryFailure = true
    #expect(!coordinator.status().automaticVerified)
    coordinator.watchdog(); coordinator.watchdog()
    #expect(spy.calls.isEmpty); #expect(spy.fans[0].mode == .manual)
    spy.inventoryFailure = false
    #expect(!coordinator.status().automaticVerified)
    coordinator.watchdog(); #expect(spy.calls.isEmpty)
    spy.fans[0].mode = .automatic
    #expect(coordinator.status().automaticVerified)
}

@Test func observationFailureRetainsRetriesForAnActualFailedRelease() {
    let spy = FanSpy(); spy.failAuto = 0
    let coordinator = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(), read: {
        throw ControlError.invalidSnapshot
    }, clock: { spy.now })
    #expect(!coordinator.startup()); _ = coordinator.status()
    spy.failAuto = nil; spy.calls = []; coordinator.watchdog()
    #expect(spy.calls == ["auto0", "auto1"])
    #expect(spy.fans.allSatisfy { $0.mode == .automatic })
}

private func delayedCoordinator(_ spy: FanSpy, stage: HardwareStage = .qualifiedControl,
                                delay: @escaping () -> Void) throws -> (HelperCoordinator, ControlLease, UUID) {
    let coordinator = HelperCoordinator(io: spy, capabilities: qualifiedCapabilities(stage: stage), read: {
        delay(); return spy.snapshot()
    }, clock: { spy.now })
    #expect(coordinator.startup()); for _ in 0..<5 { _ = coordinator.status() }
    let owner = UUID()
    let lease = try coordinator.begin(LeaseRequest(generation: 1, required: SensorRole.safety), owner: owner)
    let snapshot = try #require(coordinator.status().snapshot)
    try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id,
        targets: [FanTarget(0, 4000), FanTarget(1, 4000)]), owner: owner)
    return (coordinator, lease, owner)
}

@Test func returningLateReadCannotWritePastHeartbeatOrQualificationDeadline() throws {
    for stage in [HardwareStage.qualifiedControl, .curveQualification] {
        let spy = FanSpy(); var delay = false
        let (coordinator, _, _) = try delayedCoordinator(spy, stage: stage) {
            if delay { spy.now += 11 }
        }
        spy.hot = true; spy.calls = []; delay = true
        coordinator.watchdog()
        #expect(spy.calls == ["auto0", "auto1"])
        #expect(spy.fans.allSatisfy { $0.mode == .automatic })
    }
}

@Test func returningLateNormalizationCannotEscalateAnExpiredLease() throws {
    let spy = FanSpy()
    let (coordinator, _, _) = try delayedCoordinator(spy) {}
    spy.hot = true; spy.calls = []
    spy.normalize = { targets in spy.now += 11; return targets }
    coordinator.watchdog()
    #expect(spy.calls == ["auto0", "auto1"])
}

@Test func latePostWriteAcquisitionCannotAcknowledgeExpiredControl() throws {
    let spy = FanSpy(); var delayAfterWrite = false
    let (coordinator, lease, owner) = try delayedCoordinator(spy) {
        if delayAfterWrite && spy.calls.contains("target1") { spy.now += 11 }
    }
    let snapshot = try #require(coordinator.status().snapshot)
    spy.calls = []; delayAfterWrite = true
    #expect(throws: ControlError.staleSession) {
        try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id,
            targets: [FanTarget(0, 4100), FanTarget(1, 4100)]), owner: owner)
    }
    #expect(spy.calls.suffix(2) == ["auto0", "auto1"])
    #expect(spy.fans.allSatisfy { $0.mode == .automatic })
}

@Test func batchAdapterEstablishesEveryModeBeforeAnyTarget() throws {
    let spy = FanSpy(); spy.fans = spy.fans.map { var fan = $0; fan.mode = .automatic; return fan }
    try FanRestoration.apply([FanTarget(0, 4000), FanTarget(1, 4000)], using: spy)
    #expect(spy.calls == ["manual0", "manual1", "target0", "target1"])
}

@Test func secondModeFailureRestoresBothWithoutWritingAnyTargets() {
    let spy = FanSpy(); spy.fans = spy.fans.map { var fan = $0; fan.mode = .automatic; return fan }; spy.failManual = 1
    #expect(throws: (any Error).self) {
        try FanRestoration.apply([FanTarget(0, 4000), FanTarget(1, 4000)], using: spy)
    }
    #expect(spy.calls == ["manual0", "manual1", "auto0", "auto1"])
    #expect(spy.fans.allSatisfy { $0.mode == .automatic })
}

@Test func qualificationHardDeadlineWinsWhileHeartbeatIsStillFresh() throws {
    let spy = FanSpy(); var late = false
    let (coordinator, lease, owner) = try delayedCoordinator(spy, stage: .curveQualification) {
        if late { spy.now += 7 }
    }
    spy.now = 19
    let snapshot = try #require(coordinator.status().snapshot)
    try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id,
        targets: [FanTarget(0, 4100), FanTarget(1, 4100)]), owner: owner)
    spy.calls = []; late = true
    coordinator.watchdog() // Read returns at 26, past deadline 25, heartbeat only 7s old.
    #expect(spy.calls == ["auto0", "auto1"])
}

@Test func returningLateStatusRestoresWithoutReportingAnOwnedSnapshot() throws {
    let spy = FanSpy(); var late = false
    let (coordinator, _, _) = try delayedCoordinator(spy) { if late { spy.now += 11 } }
    spy.calls = []; late = true
    let status = coordinator.status()
    #expect(status.snapshot == nil); #expect(status.automaticVerified)
    #expect(spy.calls == ["auto0", "auto1"])
}

@Test func idleControllerFailureDistinguishesObservationFromFailedRelease() throws {
    var machine = ControlMachine()
    #expect(machine.observationFailed(ControlError.invalidSnapshot) == .none)
    #expect(machine.state == .system)
    let report = try Wire.decode(RestorationReport.self, from: Data("{\"fans\":[]}".utf8))
    #expect(!report.verified)
    #expect(machine.observationFailed(ControlError.invalidSnapshot, restoration: report) == .restore(generation: 1))
    #expect(machine.state == .restoringSystem)
}

@Test func sensorPollingBudgetNeverDelaysHeartbeatExpiryOrExplicitRelease() throws {
    let spy = FanSpy(); var reads = 0
    let (coordinator, _, _) = try delayedCoordinator(spy) { reads += 1 }
    let initial = reads
    coordinator.watchdog(); #expect(reads == initial + 1)
    spy.now += 0.1; coordinator.watchdog(); #expect(reads == initial + 1)
    spy.now = 10.5; spy.hot = true; coordinator.watchdog()
    #expect(reads == initial + 2); #expect(spy.fans.map(\.targetRPM) == [8000, 7400])
    spy.now = 19.9; coordinator.watchdog()
    let lastRead = reads; spy.calls = []
    spy.now = 20; coordinator.watchdog()
    #expect(reads == lastRead); #expect(spy.calls == ["auto0", "auto1"])
    #expect(spy.fans.allSatisfy { $0.mode == .automatic })
}
