import Foundation
import AppKit
import Testing
import FandyCore
@testable import FandyApp
@MainActor @Test func editorCRUDAndProtectedBuiltins() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let model=AppModel(storeURL:directory.appendingPathComponent("profiles.json"),autoStart:false,simulation:true)
    #expect(model.machine.selected.id == "system");#expect(model.simulation)
    model.editorSelection="system";model.delete(); await model.waitForCollection();#expect(model.profiles.count==6)
    model.create(); await model.waitForCollection();let id=model.editorSelection;#expect(model.profiles.count==7)
    var profile=model.edited!;profile.name="Typing";model.update(profile);#expect(model.edited?.name=="Typing")
    model.duplicate(); await model.waitForCollection();#expect(model.profiles.count==8);model.delete(); await model.waitForCollection();#expect(model.profiles.count==7)
    model.editorSelection=id;model.delete(); await model.waitForCollection();#expect(model.profiles.count==6)
    model.editorSelection="cool-chassis";profile=model.edited!;profile.floor=35;model.update(profile);model.reset();#expect(model.edited?.floor==20)
}
@MainActor @Test func invalidDraftRetainsValidatedProfileAndScenarioFaultRestores() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let model=AppModel(storeURL:directory.appendingPathComponent("profiles.json"),autoStart:false,simulation:true)
    model.editorSelection="gaming";let valid=model.edited!;var bad=valid;bad.floor = .nan;model.update(bad)
    #expect(model.edited==valid);#expect(model.draftError != nil)
    model.select("gaming");for _ in 0..<6 { await model.tick() };#expect(model.machine.state == .customActive)
    model.scenario = .sensorFailure;await model.tick();#expect(model.machine.selected.id=="system");#expect(model.machine.state == .system)
}
@MainActor @Test func liveEditsPersistAfterDebounceAndInvalidEditsDoNotReplaceThem() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let url=directory.appendingPathComponent("profiles.json"),model=AppModel(storeURL:url,autoStart:false)
    model.editorSelection="school";var profile=model.edited!;profile.floor=15;model.update(profile)
    profile.floor=20;model.update(profile);profile.floor = .infinity;model.update(profile)
    try await Task.sleep(for:.milliseconds(400))
    #expect(ProfileStore(url:url).load().profiles.first{$0.id=="school"}?.floor==20)
}
@MainActor @Test func customReorderingCannotDisplaceBuiltinsAndReportsBoundaries() async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.create(); await model.waitForCollection(); let first = model.editorSelection
    #expect(!model.canMove(-1)); #expect(!model.canMove(1))
    model.create(); await model.waitForCollection(); let second = model.editorSelection
    #expect(model.canMove(-1)); model.move(-1); await model.waitForCollection()
    #expect(model.profiles.suffix(2).map(\.id) == [second, first])
    #expect(!model.canMove(-1)); #expect(model.canMove(1))
    model.editorSelection = "gaming"
    #expect(!model.canMove(-1)); #expect(!model.canMove(1))
    #expect(model.profiles.prefix(6).map(\.id) == BuiltInProfiles.all.map(\.id))
}
@MainActor @Test func powerResetPreservesGenerationAndFailedRestorationIsNotSystem() async throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let model=AppModel(storeURL:directory.appendingPathComponent("profiles.json"),autoStart:false,simulation:true)
    model.select("gaming");for _ in 0..<6 { await model.tick() }
    let generation=model.machine.generation
    model.scenario = .helperDisconnected;await model.tick()
    model.powerTransition()
    for _ in 0..<8 { await Task.yield() }
    #expect(model.machine.generation > generation);#expect(model.machine.selected.id=="system")
    #expect(model.machine.state == .fault)
}

@Test func helperDiagnosticActionsAreFixedAndCannotBeCombined() throws {
    #expect(try HelperDiagnosticAction.parse(["Fandy"]) == nil)
    #expect(try HelperDiagnosticAction.parse(["Fandy", "--helper-observation-status"]) == .status)
    #expect(throws: ControlError.malformedMessage) { try HelperDiagnosticAction.parse(["--helper-observation-register", "--helper-observation-unregister"]) }
    #expect(throws: ControlError.malformedMessage) { try HelperDiagnosticAction.parse(["--helper-observation-register", "--helper-observation-register"]) }
}

private func monitoringFixture(at now: Double = 10) -> HardwareSnapshot {
    HardwareSnapshot(at: now, sensors: SensorRole.allCases.map {
        SensorReading($0, $0 == .trackpad ? 27 : $0 == .actuator ? 25 : $0 == .cpuPeak || $0 == .gpuPeak ? 48 : 33,
                      at: now, sequence: 1, health: .unverified)
    }, fans: [Fan(id: 0, min: 2000, max: 8000, actual: 0), Fan(id: 1, min: 2200, max: 7400, actual: 0)])
}
private actor MonitoringClient: PrivilegedFanClient {
    var applies = 0
    var restores = 0
    var failed = false
    var restoreFailed = false
    var reportedReleaseFailed = false
    func setReportedReleaseFailed() { reportedReleaseFailed = true }
    func setRestoreFailed(_ failed: Bool) { restoreFailed = failed }
    func setFailed() { failed = true }
    func counts() -> (Int, Int) { (applies, restores) }
    func status() throws -> HelperStatus {
        if failed { throw ControlError.helperUnavailable }
        if reportedReleaseFailed {
            let report = try Wire.decode(RestorationReport.self, from: Data("{\"fans\":[{\"fanID\":0,\"initialMode\":0,\"commandSucceeded\":false,\"immediateMode\":0,\"observedMode\":0,\"failure\":\"write failed\"}]}".utf8))
            return HelperStatus(automaticVerified: false, snapshot: monitoringFixture(), fault: "write failed", restoration: report)
        }
        return HelperStatus(automaticVerified: true, observationOnly: true, snapshot: monitoringFixture())
    }
    func apply(_ targets: [FanTarget], generation: UInt64) { applies += 1 }
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) { applies += 1 }
    func restoreAutomatic() throws { restores += 1; if restoreFailed { throw ControlError.restorationUnverified } }
}
private actor SuspendedProvider: TemperatureSensorProvider {
    var pending: CheckedContinuation<HardwareSnapshot, any Error>?
    func snapshot() async throws -> HardwareSnapshot {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waiting() -> Bool { pending != nil }
    func release() { pending?.resume(returning: monitoringFixture()); pending = nil }
}
@MainActor @Test func productionStartupAndPreviewNeverActivateOrWrite() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MonitoringClient()
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
                         client: client, capabilities: HardwareCapabilities(model: "Test"), helperAvailable: { true }, clock: { 10 })
    #expect(!model.simulation); #expect(model.machine.selected.id == "system")
    await model.tick()
    #expect(model.helperHealth == .monitoring); #expect(model.ownership == .appleObserved)
    model.editorSelection = "cool-chassis"
    #expect(model.preview?.usesCandidates == true); #expect(model.preview?.percent == 20)
    #expect(!model.isSelected("cool-chassis")); #expect(!model.canActivate(model.edited!))
    model.select("cool-chassis")
    #expect(model.machine.selected.id == "system")
    model.powerTransition(); await model.tick(); await model.prepareForTermination()
    #expect(model.canTerminate)
    let counts = await client.counts(); #expect(counts.0 == 0); #expect(counts.1 == 0)
}
@MainActor @Test func helperLossRemovesOwnershipAndPreviewWithoutClaimingSystem() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MonitoringClient()
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
                         client: client, capabilities: HardwareCapabilities(model: "Test"), helperAvailable: { true }, clock: { 10 })
    await model.tick(); #expect(model.isSelected("system"))
    await client.setFailed(); await model.tick()
    #expect(model.helperHealth == .fault); #expect(model.ownership == .unknown)
    #expect(!model.isSelected("system")); #expect(model.preview == nil)
    let counts = await client.counts(); #expect(counts.0 == 0); #expect(counts.1 == 0)
}
@MainActor @Test func powerResetDiscardsInFlightMonitoringReply() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = SuspendedProvider()
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
                         provider: provider, capabilities: HardwareCapabilities(model: "Test"), helperAvailable: { false }, clock: { 10 })
    let request = Task { await model.tick() }
    while !(await provider.waiting()) { await Task.yield() }
    model.powerTransition(); await provider.release(); await request.value
    #expect(model.snapshot == nil); #expect(model.tickCount == 0); #expect(!model.isSelected("system"))
}
@MainActor @Test func backendSwitchDiscardsOldMonitoringReply() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let provider = SuspendedProvider()
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
                         provider: provider, capabilities: HardwareCapabilities(model: "Test"), helperAvailable: { false }, clock: { 10 })
    let request = Task { await model.tick() }
    while !(await provider.waiting()) { await Task.yield() }
    model.setSimulation(true)
    for _ in 0..<10 { await Task.yield() }
    #expect(model.simulation)
    await provider.release(); await request.value
    #expect(model.snapshot == nil)
    await model.tick(); #expect(model.snapshot != nil); #expect(model.machine.selected.id == "system")
}

private actor DeferredControlClient: PrivilegedFanClient {
    var pending: CheckedContinuation<Void, any Error>?
    var modes: FanMode = .automatic
    var restores = 0
    var sequence: UInt64 = 0
    func status() -> HelperStatus {
        sequence += 1
        var snapshot = monitoringFixture()
        snapshot.sensors = snapshot.sensors.map { var s = $0; s.health = .valid; s.sequence = sequence; return s }
        snapshot.fans = snapshot.fans.map { var fan = $0; fan.mode = modes; return fan }
        return HelperStatus(automaticVerified: modes == .automatic, manualQualified: true, snapshot: snapshot)
    }
    func waiting() -> Bool { pending != nil }
    func restoreCount() -> Int { restores }
    func releaseFailure() { pending?.resume(throwing: ControlError.helperUnavailable); pending = nil }
    func apply(_ targets: [FanTarget], generation: UInt64) async throws {
        modes = .manual
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) async throws { try await apply(targets, generation: generation) }
    func restoreAutomatic() { restores += 1; modes = .automatic }
}
@MainActor @Test func lateControlFailureCannotReplaceNewSystemSelection() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = DeferredControlClient()
    let capabilities = HardwareCapabilities(model: "Test", stage: .qualifiedControl,
        sensors: HardwareCapabilities.requiredRoles.map { SensorEvidence(role: $0, keys: ["TEST"], state: .verified, source: "Injected test", limitation: "") },
        topology: .verified, automaticRestoration: .verified, manualTransaction: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, client: client,
                         capabilities: capabilities, helperAvailable: { true }, clock: { 10 })
    await model.tick(); model.select("gaming")
    for _ in 0..<4 { await model.tick() }
    let pending = Task { await model.tick() }
    while !(await client.waiting()) { await Task.yield() }
    model.select("system")
    while await client.restoreCount() == 0 { await Task.yield() }
    for _ in 0..<10 { await Task.yield() }
    let generation = model.machine.generation
    #expect(model.machine.state == .system)
    await client.releaseFailure(); await pending.value
    #expect(model.machine.generation == generation); #expect(model.machine.selected.id == "system")
    #expect(model.machine.state == .system); #expect(model.machine.fault == nil)
}

@MainActor @Test func failedRestorationWithholdsCheckmarkAndRetriesOnNextReading() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MonitoringClient()
    let capabilities = HardwareCapabilities(model: "Test", stage: .restorationQualification,
        sensors: HardwareCapabilities.requiredRoles.map { SensorEvidence(role: $0, keys: ["TEST"], state: .verified, source: "Injected test", limitation: "") }, topology: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false, client: client,
                         capabilities: capabilities, helperAvailable: { true }, clock: { 10 })
    await model.tick(); #expect(model.isSelected("system"))
    await client.setRestoreFailed(true); model.select("system")
    while await client.counts().1 == 0 { await Task.yield() }
    for _ in 0..<10 { await Task.yield() }
    #expect(model.machine.state == .fault); #expect(model.ownership == .appleObserved)
    #expect(!model.isSelected("system"))
    await client.setRestoreFailed(false); await model.tick()
    #expect(model.machine.state == .system); #expect(model.isSelected("system"))
}

@MainActor @Test func rapidBackendToggleKeepsLatestRequestedMode() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MonitoringClient()
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
                         client: client, capabilities: HardwareCapabilities(model: "Test"), helperAvailable: { true }, clock: { 10 })
    model.setSimulation(true); model.setSimulation(false)
    for _ in 0..<10 { await Task.yield() }
    #expect(!model.simulation)
    await model.tick(); #expect(model.helperHealth == .monitoring)
    let counts = await client.counts(); #expect(counts.0 == 0); #expect(counts.1 == 0)
}

@MainActor @Test func restorationBuildReleasesButNeverActivatesCandidateProfiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MonitoringClient()
    let release = HardwareCapabilities(model: "Test", stage: .restorationQualification, topology: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
                         client: client, capabilities: release, helperAvailable: { true }, clock: { 10 })
    await model.tick()
    model.editorSelection = "cool-chassis"
    #expect(model.preview?.usesCandidates == true)
    #expect(!model.canActivate(model.edited!))
    model.select("cool-chassis")
    #expect(model.machine.selected.id == "system")
    await model.prepareForTermination()
    let counts = await client.counts()
    #expect(counts.0 == 0); #expect(counts.1 > 0); #expect(model.canTerminate)
}

@Test func restorationDiagnosticsRejectExtraHardwareArguments() throws {
    #expect(try HelperDiagnosticAction.parse(["Fandy", "--helper-restore"]) == .restore)
    #expect(try HelperDiagnosticAction.parse(["Fandy", "--helper-restoration-check"]) == .checkRestoration)
    #expect(throws: ControlError.malformedMessage) { try HelperDiagnosticAction.parse(["Fandy", "--helper-restore", "--rpm", "3000"]) }
    #expect(throws: ControlError.malformedMessage) { try HelperDiagnosticAction.parse(["Fandy", "--helper-restoration-register", "--helper-restore"]) }
}

@MainActor @Test func failedHelperReleaseReportCannotProduceSystemCheckmark() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MonitoringClient()
    await client.setReportedReleaseFailed(); await client.setRestoreFailed(true)
    let release = HardwareCapabilities(model: "Test", stage: .restorationQualification, topology: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
                         client: client, capabilities: release, helperAvailable: { true }, clock: { 10 })
    await model.tick()
    #expect(model.machine.state == .fault); #expect(!model.isSelected("system"))
    #expect(model.helperHealth == .fault); #expect(await client.counts().0 == 0)
}

@Test func fixedRecoveryDiagnosticsRejectHardwareParametersAndDuplicateActions() throws {
    let actions: [HelperDiagnosticAction] = [.recoveryInitial, .recoveryDeadline, .recoveryHeartbeat, .recoveryDisconnect, .recoveryHold]
    for action in actions {
        #expect(try HelperDiagnosticAction.parse(["Fandy", action.rawValue]) == action)
        for parameter in ["--rpm=7000", "--duration=60", "--fan=0", "--qualified", "--key=F0Tg", action.rawValue] {
            #expect(throws: ControlError.malformedMessage) { try HelperDiagnosticAction.parse(["Fandy", action.rawValue, parameter]) }
        }
    }
}

private actor MaximumClient: PrivilegedFanClient {
    var fans = monitoringFixture().fans
    var applies = 0
    var restores = 0
    var blocker: String?
    func block() { blocker = "Known competing fan controller is running." }
    func status() -> HelperStatus {
        var snapshot = monitoringFixture(); snapshot.fans = fans
        var status = HelperStatus(automaticVerified: fans.allSatisfy { $0.mode == .automatic }, manualQualified: true, snapshot: snapshot)
        status.recoveryBlocker = blocker; return status
    }
    func apply(_ targets: [FanTarget], generation: UInt64) throws { try apply(targets, generation: generation, required: []) }
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) throws {
        guard required.isEmpty, targets.count == fans.count,
              targets.allSatisfy({ target in fans.contains { $0.id == target.fanID && $0.maximumRPM == target.rpm } }) else { throw ControlError.invalidFan }
        applies += 1
        for i in fans.indices { fans[i].mode = .manual; fans[i].targetRPM = fans[i].maximumRPM }
    }
    func restoreAutomatic() {
        restores += 1
        for i in fans.indices { fans[i].mode = .automatic }
    }
    func counts() -> (Int, Int) { (applies, restores) }
}
@MainActor @Test func productionMaximumActivatesWithCandidateTemperaturesAndSystemAndWakeRelease() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let caps = HardwareCapabilities(model: "Test", stage: .maximumControl, topology: .verified,
        automaticRestoration: .verified, manualTransaction: .verified)
    let client = MaximumClient()
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
        client: client, capabilities: caps, helperAvailable: { true }, clock: { 10 })
    await model.tick(); #expect(model.isSelected("system")); #expect(model.canActivate(BuiltInProfiles.maximum))
    #expect(!model.canActivate(BuiltInProfiles.gaming)); #expect(!model.canActivate(BuiltInProfiles.coolChassis))
    model.select("max"); #expect(!model.isSelected("max"))
    await model.tick()
    #expect(model.isSelected("max")); #expect(model.machine.percent == 100)
    model.select("system")
    while await client.counts().1 == 0 { await Task.yield() }
    for _ in 0..<10 { await Task.yield() }
    await model.tick(); #expect(model.isSelected("system"))
    model.select("max"); for _ in 0..<5 { await model.tick() }; #expect(model.isSelected("max"))
    model.powerTransition(); for _ in 0..<10 { await Task.yield() }; await model.tick()
    #expect(model.isSelected("system")); #expect(!model.isSelected("max"))
    await model.prepareForTermination(); #expect(model.canTerminate)
}
@Test func maximumDiagnosticRejectsCallerSelectedTargetsAndDurations() throws {
    #expect(try HelperDiagnosticAction.parse(["Fandy", "--profile-max-check"]) == .maximumCheck)
    for value in ["--rpm=7000", "--duration=20", "--fan=0", "--profile=gaming"] {
        #expect(throws: ControlError.malformedMessage) { try HelperDiagnosticAction.parse(["Fandy", "--profile-max-check", value]) }
    }
}

@MainActor @Test func competingControllerRemovesProductionEligibilityBeforeClick() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MaximumClient(); await client.block()
    let caps = HardwareCapabilities(model: "Test", stage: .maximumControl, topology: .verified,
        automaticRestoration: .verified, manualTransaction: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
        client: client, capabilities: caps, helperAvailable: { true }, clock: { 10 })
    await model.tick(); #expect(!model.canActivate(BuiltInProfiles.maximum)); #expect(model.hardwareError != nil)
    model.select("max"); #expect(model.machine.selected.kind == .system)
    #expect(await client.counts().0 == 0)
}

@Test @MainActor func curveDiagnosticArgumentsAreFixedAndCannotSelectHardware() throws {
    for action in [HelperDiagnosticAction.curveCheck, .curveHeartbeat, .curveDisconnect, .curveHold, .curveSpinning, .curveQuit] {
        #expect(try HelperDiagnosticAction.parse(["Fandy", action.rawValue]) == action)
        #expect(throws: (any Error).self) { _ = try HelperDiagnosticAction.parse(["Fandy", action.rawValue, "--rpm", "3000"]) }
        #expect(throws: (any Error).self) { _ = try HelperDiagnosticAction.parse(["Fandy", action.rawValue, "--duration", "9999"]) }
    }
}

private actor EnvelopeClient: PrivilegedFanClient {
    var sequence: UInt64 = 0
    var missing = false
    var requests: [Set<SensorRole>] = []
    var restores = 0
    func loseEnvelope() { missing = true }
    func counts() -> (Int, Int) { (requests.count, restores) }
    func roles() -> [Set<SensorRole>] { requests }
    func status() -> HelperStatus {
        sequence += 1
        var snapshot = monitoringFixture()
        snapshot.sensors[snapshot.sensors.firstIndex { $0.role == .socPeak }!] = SensorReading(.socPeak, missing ? nil : 65,
            at: 10, sequence: sequence, health: missing ? .missing : .valid)
        return HelperStatus(automaticVerified: requests.isEmpty, manualQualified: true, snapshot: snapshot)
    }
    func apply(_ targets: [FanTarget], generation: UInt64) throws { throw ControlError.malformedMessage }
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) throws {
        guard required == [.socPeak] else { throw ControlError.hardwareUnqualified }; requests.append(required)
    }
    func restoreAutomatic() { restores += 1 }
}
@MainActor @Test func appEnvelopePolicyKeepsDisplayEstimatesSeparateAndLossReturnsSystem() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = EnvelopeClient()
    let caps = HardwareCapabilities(model: "Test", stage: .qualifiedControl,
        sensors: [SensorEvidence(role: .socPeak, keys: ["Tp00", "Tm00", "Tg0U"], state: .verified, source: "Test", limitation: "")],
        topology: .verified, automaticRestoration: .verified, manualTransaction: .verified, chipControl: .conservativeEnvelope)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
                         client: client, capabilities: caps, helperAvailable: { true }, clock: { 10 })
    await model.tick()
    #expect(model.machine.chipPolicy == .conservativeEnvelope)
    #expect(model.canActivate(BuiltInProfiles.gaming)); #expect(!model.canActivate(BuiltInProfiles.coolChassis))
    model.editorSelection = "gaming"; #expect(model.preview?.usesCandidates == false)
    model.select("gaming"); #expect(!model.isSelected("gaming"))
    for _ in 0..<5 { await model.tick() }
    #expect(model.isSelected("gaming")); #expect(await client.roles() == [[.socPeak]])
    await client.loseEnvelope(); await model.tick()
    #expect(model.machine.selected.kind == .system); #expect(!model.isSelected("gaming"))
    #expect(await client.counts().1 > 0)
}

@MainActor @Test func pollingRestartOwnsExactlyOnePairOfPowerObservers() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let center = NotificationCenter()
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
                         simulation: true, powerCenter: center)
    model.start(); model.stop(); model.start(); model.start()
    let generation = model.machine.generation
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    for _ in 0..<20 { await Task.yield() }
    #expect(model.machine.generation == generation + 1)
    model.stop()
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    for _ in 0..<20 { await Task.yield() }
    #expect(model.machine.generation == generation + 1)
    await model.prepareForTermination(); model.start()
    let terminated = model.machine.generation
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    for _ in 0..<20 { await Task.yield() }
    #expect(model.machine.generation == terminated)
}

@MainActor @Test func productionIdleMonitoringFailuresNeverIssueFanCommands() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = MonitoringClient()
    let caps = HardwareCapabilities(model: "Test", stage: .qualifiedControl, topology: .verified,
                                    automaticRestoration: .verified, manualTransaction: .verified)
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
                         client: client, capabilities: caps, helperAvailable: { true }, clock: { 10 })
    await model.tick(); await client.setFailed()
    for _ in 0..<4 { await model.tick() }
    #expect(model.snapshot == nil); #expect(model.machine.state == .system)
    #expect(!model.isSelected("system")); #expect(model.helperHealth == .fault)
    let counts = await client.counts(); #expect(counts.0 == 0); #expect(counts.1 == 0)
}
