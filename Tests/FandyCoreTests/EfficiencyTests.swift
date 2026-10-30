import Foundation
import Testing
@testable import FandyCore

@Test func publicationCanReuseOnlyTheJustValidatedWatchdogSample() throws {
    let io = FanSpy(); var reads = 0
    let c = HelperCoordinator(io: io, capabilities: qualifiedCapabilities(), read: { reads += 1; return io.snapshot() }, clock: { io.now })
    #expect(c.restore())
    for _ in 0..<5 { _ = c.status() }
    let owner = UUID(), lease = try c.begin(LeaseRequest(generation: 1, required: SensorRole.safety), owner: owner)
    let issued = try #require(c.status().snapshot)
    try c.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: issued.id, targets: [FanTarget(0, 3000), FanTarget(1, 3000)]), owner: owner)
    io.now += 1; c.watchdog()
    let before = reads
    let sampled = try #require(c.status(reuseObservation: true).snapshot)
    #expect(reads == before)
    #expect(c.status(reuseObservation: true).snapshot?.id == sampled.id)
    io.now += 0.3
    _ = c.status(reuseObservation: true)
    #expect(reads == before + 1)
    io.fans[1].mode = .automatic
    _ = c.status() // Explicit fresh status never hides a later ownership change.
    #expect(io.fans.allSatisfy { $0.mode.isAutomatic })
}

@Test func publicationReuseCannotRenewHeartbeatOrAuthorizeOldTargetsAfterRestore() throws {
    let io = FanSpy(); let (c, lease, owner) = try leasedCoordinator(io)
    let old = try #require(c.status().snapshot)
    try c.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: old.id, targets: [FanTarget(0, 3000), FanTarget(1, 3000)]), owner: owner)
    io.now = 19.9; c.watchdog(); _ = c.status(reuseObservation: true)
    io.now = 20; c.watchdog()
    #expect(io.fans.allSatisfy { $0.mode.isAutomatic })
    #expect(c.status(reuseObservation: true).automaticVerified)
    #expect(throws: (any Error).self) {
        try c.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: old.id, targets: [FanTarget(0, 3000), FanTarget(1, 3000)]), owner: owner)
    }
}

@Test func helperTickCadenceSlowsOnlyWithoutAControlOrRecoveryObligation() {
    #expect(HelperPollingPolicy.interval(activeLease: false, recoveryActive: false, restorationPending: false) == 1)
    for flags in [(true,false,false),(false,true,false),(false,false,true),(true,true,true)] {
        #expect(HelperPollingPolicy.interval(activeLease: flags.0, recoveryActive: flags.1, restorationPending: flags.2) == 0.1)
    }
}

@Test func reusedPresentationNeverReplacesFreshCommandSensorValidation() throws {
    let io = FanSpy(); let (c, lease, owner) = try leasedCoordinator(io)
    let first = try #require(c.status().snapshot)
    try c.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: first.id, targets: [FanTarget(0,3000),FanTarget(1,3000)]), owner: owner)
    let shown = try #require(c.status(reuseObservation: true).snapshot)
    io.invalid = true
    #expect(throws: (any Error).self) {
        try c.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: shown.id, targets: [FanTarget(0,3100),FanTarget(1,3100)]), owner: owner)
    }
    #expect(io.fans.allSatisfy { $0.mode.isAutomatic })
}
