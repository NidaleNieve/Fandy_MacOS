import AppKit
import Foundation
import Testing
import FandyCore
@testable import FandyApp

@MainActor @Test func nativeSleepPausesPollingAutomationAndResumesPreviousProfile() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    #expect(model.machine.selected.id == "cool-chassis")
    await model.systemWillSleep()
    #expect(model.powerLifecycle == .suspended && model.machine.selected.id == "system")
    let count = model.tickCount, generation = model.machine.generation
    for _ in 0..<5 { await model.tick(); model.select("gaming"); model.evaluateSchedule() }
    #expect(model.tickCount == count && model.machine.generation == generation)
    #expect(!model.canActivate(BuiltInProfiles.maximum))
    await model.systemWillSleep(); #expect(model.machine.generation == generation)
    await model.systemDidWake()
    #expect(model.powerLifecycle == .awake && model.machine.selected.id == "cool-chassis")
    for _ in 0..<7 { await model.tick() }
    #expect(model.machine.state == .customActive)
    model.stop()
}
@MainActor @Test func failedWakeStaysSystemAndDisplaySleepDoesNotSuspend() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let center = NotificationCenter()
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, powerCenter: center)
    model.observePower(); model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
    for _ in 0..<10 { await Task.yield() }
    #expect(model.powerLifecycle == .awake && model.machine.selected.id == "cool-chassis")
    await model.systemWillSleep(); model.scenario = .sensorFailure
    await model.systemDidWake()
    #expect(model.machine.selected.id == "system" && model.machine.state == .system)
    #expect(model.hardwareError != nil)
    model.stop()
}
private final class WakeClock: @unchecked Sendable {
    private let lock = NSLock(); private var value = Date(timeIntervalSince1970: 1_000)
    func date() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: Double) { lock.lock(); value = value.addingTimeInterval(seconds); lock.unlock() }
}
@MainActor @Test func sleepCannotExtendATimerAndExpiredOverrideResumesBackgroundProfile() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = WakeClock()
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: { clock.date() })
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    model.select("max"); model.activateFor(seconds: 60); await model.tick()
    let deadline = model.manualIntent
    await model.systemWillSleep(); clock.advance(20); await model.systemDidWake()
    #expect(model.machine.selected.id == "max" && model.manualIntent == deadline)
    await model.systemWillSleep(); clock.advance(60); await model.systemDidWake()
    #expect(model.manualIntent == nil && model.machine.selected.id == "cool-chassis")
    model.stop()
}
@MainActor @Test func scheduleIsReevaluatedOnWakeAndFinishedPeriodReturnsBackground() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = WakeClock()
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: { clock.date() })
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    model.automation.periods = [WeeklyPeriod(profileID: "school", weekday: 4, startMinute: 20, endMinute: 40)]
    await model.systemWillSleep(); clock.advance(300); await model.systemDidWake()
    #expect(model.machine.selected.id == "school")
    for _ in 0..<7 { await model.tick() }
    await model.systemWillSleep(); clock.advance(1500); await model.systemDidWake()
    #expect(model.machine.selected.id == "cool-chassis")
    model.stop()
}
private actor SleepDelayedProvider: TemperatureSensorProvider {
    private var pending: [CheckedContinuation<HardwareSnapshot, any Error>] = []
    private var calls = 0
    func snapshot() async throws -> HardwareSnapshot { calls += 1; return try await withCheckedThrowingContinuation { pending.append($0) } }
    func waiting() -> Bool { !pending.isEmpty }
    func count() -> Int { calls }
    func release() { for continuation in pending { continuation.resume(returning: HardwareSnapshot(at: 10, sensors: [], fans: [Fan(id: 0, min: 2000, max: 8000, actual: 2500)])) }; pending = [] }
}
@MainActor @Test func sleepDiscardsLateMonitoringAndCannotBeginUpdateReplacement() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let provider = SleepDelayedProvider()
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, provider: provider, capabilities: HardwareCapabilities(model: "unqualified"), helperAvailable: { false }, clock: { 10 })
    let reading = Task { await model.tick() }
    while !(await provider.waiting()) { await Task.yield() }
    let sleep = Task { await model.systemWillSleep() }
    for _ in 0..<30 { await Task.yield() }
    #expect(await provider.count() == 1)
    await provider.release(); await reading.value; await sleep.value
    #expect(model.snapshot == nil && model.tickCount == 0 && model.powerLifecycle == .suspended)
    await #expect(throws: ControlError.helperUnavailable) { try await model.prepareForUpdate() }
    model.stop()
}
@MainActor @Test func sleepCannotClearAFaultAndSilentlyResumeTheDefault() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    model.scenario = .sensorFailure; await model.tick()
    #expect(model.machine.selected.id == "system")
    await model.systemWillSleep(); model.scenario = .comfortableSchool; await model.systemDidWake()
    for _ in 0..<7 { await model.tick() }
    #expect(model.machine.selected.id == "system" && model.machine.state == .system)
    model.stop()
}

private actor WakeDelayedClient: PrivilegedFanClient {
    private let mock = MockBackend()
    private var delayNext = false
    private var pending: CheckedContinuation<HelperStatus, any Error>?
    func deferStatus() { delayNext = true }
    func waiting() -> Bool { pending != nil }
    func release() async throws { pending?.resume(returning: try await status()); pending = nil }
    func status() async throws -> HelperStatus {
        if delayNext { delayNext = false; return try await withCheckedThrowingContinuation { pending = $0 } }
        var reading = try await mock.snapshot()
        reading.sampledAt = 10
        reading.sensors = reading.sensors.map { var sensor = $0; sensor.sampledAt = 10; return sensor }
        return HelperStatus(automaticVerified: reading.appleOwnershipObserved, manualQualified: true, snapshot: reading)
    }
    func apply(_ targets: [FanTarget], generation: UInt64) async throws { try await mock.apply(targets, generation: generation) }
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) async throws { try await apply(targets, generation: generation) }
    func restoreAutomatic() async throws { try await mock.restoreAutomatic() }
}
@MainActor @Test func wakeWaitsForRevokedReadThenAcquiresFreshStateBeforeResuming() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let client = WakeDelayedClient()
    let caps = HardwareCapabilities(model: "Injected", stage: .qualifiedControl,
        sensors: HardwareCapabilities.requiredRoles.map { SensorEvidence(role: $0, keys: ["TEST"], state: .verified, source: "Injected", limitation: "") },
        topology: .verified, automaticRestoration: .verified, manualTransaction: .verified)
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false,
        client: client, capabilities: caps, helperAvailable: { true }, clock: { 10 })
    await model.tick(); model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    #expect(model.machine.selected.id == "cool-chassis")
    await client.deferStatus()
    let reading = Task { await model.tick() }
    while !(await client.waiting()) { await Task.yield() }
    await model.systemWillSleep()
    let wake = Task { await model.systemDidWake() }
    for _ in 0..<30 { await Task.yield() }
    #expect(model.powerLifecycle == .resuming && model.machine.selected.id == "system")
    try await client.release(); await reading.value; await wake.value
    #expect(model.powerLifecycle == .awake && model.machine.selected.id == "cool-chassis")
    #expect(model.snapshot != nil && model.hardwareError == nil)
    await model.prepareForTermination()
}
