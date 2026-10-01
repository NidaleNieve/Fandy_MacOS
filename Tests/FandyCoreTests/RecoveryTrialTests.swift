import Foundation
import Testing
@testable import FandyCore

private final class RecoveryRig: RecoveryFanHardwareIO, @unchecked Sendable {
    var now = 10.0
    var sequence: UInt64 = 0
    var fans = fixture().fans
    var events: [String] = []
    var peak = 50.0
    var missingSensor = false
    var prepareFailure = false
    var clearPrepared = false
    var stallActivation = false
    var failingRestore: Int?
    var pressure: ThermalPressure = .nominal
    var conflictingController = false
    let owner = UUID()
    var engine: RecoveryTrialCoordinator!
    init() {
        let caps = HardwareCapabilities(model: "Test", stage: .recoveryQualification,
            topology: .verified, automaticRestoration: .verified)
        engine = RecoveryTrialCoordinator(io: self, capabilities: caps,
            read: { [self] in try observation() }, clock: { [self] in now },
            restore: { [self] in try? FanRestoration.report(using: self) },
            requireExclusive: { [self] in if conflictingController { throw ControlError.unauthorized } })
    }
    func observation() throws -> RecoveryObservation {
        now += 0.01; sequence += 1
        var snapshot = fixture(at: now, pressure: pressure); snapshot.fans = fans
        snapshot.sensors = snapshot.sensors.map { var s = $0; s.sequence = sequence; s.health = .unverified; return s }
        if missingSensor { snapshot.sensors.removeAll { $0.role == .trackpad } }
        return RecoveryObservation(snapshot: snapshot, diagnosticPeak: peak, diagnosticKeyCount: 105)
    }
    func enumerateFans() throws -> [Fan] { fans }
    func readMode(fanID: Int) throws -> FanMode { fans[fanID].mode }
    func setAutomatic(fanID: Int) throws {
        events.append("auto\(fanID)")
        if failingRestore == fanID { throw ControlError.restorationUnverified }
        fans[fanID].mode = .automatic; fans[fanID].targetRPM = 0
    }
    func setManual(fanID: Int) throws { throw ControlError.unauthorized }
    func setTarget(fanID: Int, rpm: Double) throws { throw ControlError.unauthorized }
    func prepareRecoveryTarget(_ target: FanTarget, deadline: Double) throws {
        events.append("prepare\(target.fanID)")
        if prepareFailure { throw ControlError.invalidFan }
        fans[target.fanID].targetRPM = clearPrepared ? 0 : target.rpm
    }
    func activateRecoveryFan(_ target: FanTarget, deadline: Double) throws {
        events.append("manual\(target.fanID)"); fans[target.fanID].mode = .manual
        if stallActivation { now += 5 }
    }
    func startStoppedRecoveryFan(_ target: FanTarget, deadline: Double) throws {
        events.append("stopped\(target.fanID)")
        fans[target.fanID].mode = .manual; fans[target.fanID].targetRPM = target.rpm
        if stallActivation { now += 5 }
    }
    func start(_ action: RecoveryTrialRequest.Action = .initial) throws -> RecoveryTrialStatus {
        try engine.request(RecoveryTrialRequest(action), owner: owner)
    }
}

@Test func recoveryAuthorityCannotUnlockProfilesOrFullSensorQualification() {
    let caps = HardwareCapabilities(model: "Test", stage: .recoveryQualification,
        topology: .verified, automaticRestoration: .verified)
    #expect(caps.canQualifyRecovery); #expect(!caps.canControl); #expect(!caps.canQualifyManual)
    #expect(!caps.allSensorsVerified); #expect(!caps.forMachine("Other").canQualifyRecovery)
    for stage in [HardwareStage.observation, .restorationQualification, .manualQualification, .qualifiedControl] {
        #expect(!qualifiedCapabilities(stage: stage).canQualifyRecovery)
    }
}
@Test func recoveryPreloadsBothTargetsBeforeEitherManualModeAndUsesFixedDeadline() throws {
    let rig = RecoveryRig(); let trial = try rig.start()
    #expect(trial.targets == [FanTarget(0, 2600), FanTarget(1, 2500)])
    #expect(rig.events == ["auto0", "auto1", "prepare0", "prepare1", "manual0", "manual1"])
    #expect(trial.deadline - trial.startedAt == 5)
    rig.now = trial.deadline; rig.engine.watchdog()
    #expect(rig.engine.status?.reason == "deadline expired")
    #expect(rig.engine.status?.restoration?.fans.allSatisfy(\.releasedManual) == true)
    #expect(rig.fans.allSatisfy { $0.mode == .automatic })
    #expect(throws: ControlError.staleSession) { try rig.start() }
}
@Test func stoppedRecoveryTrialIsExplicitlyMinimumPlusMarginAndNeverBelowBounds() throws {
    let rig = RecoveryRig(); rig.fans[0].actualRPM = 0; rig.fans[1].actualRPM = 0; rig.fans[0].targetRPM = 0; rig.fans[1].targetRPM = 0
    let trial = try rig.start()
    #expect(trial.targets == [FanTarget(0, 2517), FanTarget(1, 2400)])
    #expect(trial.baselineFans.allSatisfy { $0.actualRPM == 0 })
    let limited = RecoveryRig(); limited.fans[1].actualRPM = 7300
    #expect(throws: ControlError.invalidFan) { try limited.start() }
    #expect(!limited.events.contains { $0.hasPrefix("prepare") })
}
@Test func recoveryNeverFallsBackToManualFirstWhenTargetCannotBePreloaded() {
    for fail in [true, false] {
        let rig = RecoveryRig(); rig.prepareFailure = fail; rig.clearPrepared = !fail
        #expect(throws: (any Error).self) { try rig.start() }
        #expect(!rig.events.contains { $0.hasPrefix("manual") })
        #expect(rig.fans.allSatisfy { $0.mode == .automatic })
    }
}
@Test func recoveryAbortsSecondFanWhenFirstOperationBlocksPastDeadline() {
    let rig = RecoveryRig(); rig.stallActivation = true
    #expect(throws: ControlError.staleSession) { try rig.start() }
    #expect(rig.events.contains("manual0")); #expect(!rig.events.contains("manual1"))
    #expect(rig.fans.allSatisfy { $0.mode == .automatic })
    #expect(rig.engine.status?.restoration?.verified == true)
}
@Test func recoveryRequiresAllCandidateReadingsAndConservativeRawCeiling() {
    for failure in 0..<4 {
        let rig = RecoveryRig()
        if failure == 0 { rig.missingSensor = true }
        if failure == 1 { rig.peak = 75 }
        if failure == 2 { rig.peak = .nan }
        if failure == 3 { rig.pressure = .serious }
        #expect(throws: (any Error).self) { try rig.start() }
        #expect(!rig.events.contains { $0.hasPrefix("prepare") })
    }
}
@Test func recoveryHeartbeatCannotExtendHardDeadlineAndStatusDoesNotRenewIt() throws {
    let rig = RecoveryRig(); _ = try rig.start(); _ = rig.engine.release(reason: "test end")
    let trial = try rig.start(.recovery)
    #expect(trial.deadline == trial.startedAt + 15)
    for offset in [1.0, 8, 14] {
        rig.now = trial.startedAt + offset
        _ = try rig.engine.request(RecoveryTrialRequest(.heartbeat, sessionID: trial.id), owner: rig.owner)
        #expect(rig.engine.status?.deadline == trial.deadline)
    }
    rig.now = trial.deadline; rig.engine.watchdog()
    #expect(rig.engine.status?.reason == "deadline expired")
    #expect(rig.engine.status?.restoration?.verified == true)
}
@Test func recoveryHeartbeatExpiresBeforeFifteenSecondDeadline() throws {
    let rig = RecoveryRig(); _ = try rig.start(); _ = rig.engine.release(reason: "test end")
    let trial = try rig.start(.recovery)
    rig.now = trial.startedAt + 10; rig.engine.watchdog()
    #expect(rig.engine.status?.reason == "heartbeat expired")
    #expect(rig.engine.status?.restoration?.verified == true)
}
@Test func recoveryOnlyOwningConnectionCanRenewRejectOrDisconnect() throws {
    let rig = RecoveryRig(); let trial = try rig.start(); let other = UUID()
    #expect(throws: ControlError.unauthorized) {
        try rig.engine.request(RecoveryTrialRequest(.heartbeat, sessionID: trial.id), owner: other)
    }
    rig.engine.disconnected(owner: other); rig.engine.reject(owner: other)
    #expect(rig.engine.status?.active == true)
    rig.engine.disconnected(owner: rig.owner)
    #expect(rig.engine.status?.reason == "controller disconnected")
    #expect(rig.engine.status?.restoration?.verified == true)
}
@Test func recoveryPartialReleaseIsReportedAndRetriedAcrossBothFans() throws {
    let rig = RecoveryRig(); _ = try rig.start(); rig.failingRestore = 0
    rig.engine.disconnected(owner: rig.owner)
    #expect(rig.engine.status?.active == false)
    #expect(rig.engine.status?.restoration?.verified == false)
    #expect(rig.fans[0].mode == .manual); #expect(rig.fans[1].mode == .automatic)
    rig.failingRestore = nil; rig.engine.watchdog()
    #expect(rig.engine.status?.restoration?.verified == true)
    #expect(rig.fans.allSatisfy { $0.mode == .automatic })
}
@Test func recoveryWatchdogRestoresOnChangedTargetSensorOrClock() throws {
    for fault in 0..<3 {
        let rig = RecoveryRig(); _ = try rig.start()
        if fault == 0 { rig.fans[0].targetRPM = 2700 }
        if fault == 1 { rig.missingSensor = true }
        if fault == 2 { rig.now = 9 }
        rig.engine.watchdog()
        #expect(rig.engine.status?.active == false)
        #expect(rig.engine.status?.restoration?.verified == true)
    }
}
@Test func recoveryWireRejectsCallerAuthorityTargetsAndInvalidSessionShape() throws {
    for text in ["{}", "{\"version\":2,\"action\":\"initial\",\"rpm\":7000}",
                 "{\"version\":2,\"action\":\"heartbeat\"}", "{\"version\":99,\"action\":\"initial\"}"] {
        #expect(throws: (any Error).self) { try RecoveryTrialRequest.decode(Data(text.utf8)) }
    }
    let request = try RecoveryTrialRequest.decode(Wire.encode(RecoveryTrialRequest(.initial)))
    #expect(request.action == .initial); #expect(request.sessionID == nil)
}

@Test func stoppedRecoveryPathRequiresZeroTargetsAndCoolReadingsAndNeverFallsBack() throws {
    let rig = RecoveryRig()
    for i in rig.fans.indices { rig.fans[i].actualRPM = 0; rig.fans[i].targetRPM = 0 }
    let trial = try rig.start()
    #expect(trial.activationPath == "stopped-zero-target mode-first")
    #expect(rig.events == ["auto0", "auto1", "stopped0", "stopped1"])
    for failure in 0..<2 {
        let rejected = RecoveryRig()
        for i in rejected.fans.indices { rejected.fans[i].actualRPM = 0; rejected.fans[i].targetRPM = 0 }
        if failure == 0 { rejected.peak = 60 }
        else { rejected.stallActivation = true }
        #expect(throws: (any Error).self) { try rejected.start() }
        #expect(!rejected.events.contains("stopped1"))
        #expect(rejected.fans.allSatisfy { $0.mode == .automatic })
    }
}

@Test func recoveryRetainsFirstHandbackEvidenceAcrossLaterIdempotentReleases() throws {
    let rig = RecoveryRig(); _ = try rig.start()
    _ = rig.engine.release(reason: "test end")
    #expect(rig.engine.status?.firstRestoration?.fans.allSatisfy(\.releasedManual) == true)
    _ = rig.engine.release(reason: "System requested")
    #expect(rig.engine.status?.firstRestoration?.fans.allSatisfy(\.releasedManual) == true)
    #expect(rig.engine.status?.restoration?.fans.allSatisfy(\.releasedManual) == false)
    #expect(rig.engine.status?.restoration?.verified == true)
}

@Test func recoveryKnownControllerConflictBlocksAdmissionAndRevokesAnActiveTrial() throws {
    let blocked = RecoveryRig(); blocked.conflictingController = true
    #expect(throws: ControlError.unauthorized) { try blocked.start() }
    #expect(blocked.events.isEmpty)
    let rig = RecoveryRig(); _ = try rig.start()
    rig.conflictingController = true; rig.engine.watchdog()
    #expect(rig.engine.status?.active == false)
    #expect(rig.engine.status?.restoration?.verified == true)
    #expect(rig.fans.allSatisfy { $0.mode == .automatic })
}

@Test func failedInitialTrialCannotAuthorizeLongerRecoveryRequests() {
    let rig = RecoveryRig(); rig.clearPrepared = true
    #expect(throws: (any Error).self) { try rig.start() }
    rig.clearPrepared = false
    #expect(throws: ControlError.staleSession) { try rig.start(.recovery) }
    #expect(!rig.events.contains { $0.hasPrefix("manual") })
}
