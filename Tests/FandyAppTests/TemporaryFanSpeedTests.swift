import AppKit
import Foundation
import Testing
import FandyCore
@testable import FandyApp

private final class SpeedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_000)
    func date() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: Double) { lock.lock(); value = value.addingTimeInterval(seconds); lock.unlock() }
}

@MainActor @Test func temporarySpeedExpiresToOrdinaryProfileWithoutSavingIt() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = SpeedClock(), url = dir.appendingPathComponent("profiles.json")
    let model = AppModel(storeURL: url, autoStart: false, simulation: true, wallClock: clock.date)
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    let saved = model.profiles
    #expect(model.activateCustomFanSpeed(percent: 28, seconds: 300))
    let temporaryID = model.machine.selected.id
    #expect(model.isCustomFanSpeedActive && model.machine.selected.floor == 28)
    #expect(model.machine.selected.curves.isEmpty && model.machine.selected.chipSources.isEmpty)
    #expect(!model.machine.selected.automaticAtIdle)
    #expect(model.profiles == saved && model.automation.preferences.defaultProfileID == "cool-chassis")
    for _ in 0..<8 { await model.tick() }
    #expect(model.machine.state == .customActive && model.isCustomFanSpeedActive)
    #expect(model.machine.lastDemand?.percent == 28)
    model.setPreferences { $0.showCustomFanSpeed = false }
    await model.prepareForTermination()
    let bytes = try Data(contentsOf: url)
    #expect(!String(decoding: bytes, as: UTF8.self).contains(temporaryID))
    let next = AppModel(storeURL: url, autoStart: false, simulation: true)
    #expect(!next.isCustomFanSpeedActive && next.profiles == saved)
    for _ in 0..<7 { await next.tick() }
    #expect(next.machine.selected.id == "cool-chassis")
    let timed = AppModel(storeURL: dir.appendingPathComponent("timer.json"), autoStart: false, simulation: true, wallClock: clock.date)
    timed.select("cool-chassis"); for _ in 0..<7 { await timed.tick() }
    #expect(timed.activateCustomFanSpeed(percent: 35, seconds: 300))
    for _ in 0..<7 { await timed.tick() }
    clock.advance(301); for _ in 0..<8 { await timed.tick() }
    #expect(timed.manualIntent == nil && !timed.isCustomFanSpeedActive && timed.machine.selected.id == "cool-chassis")
}

@MainActor @Test func temporarySpeedRejectsInvalidInputWithoutChangingActiveControl() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    let generation = model.machine.generation
    for percent in [Double.nan, .infinity, -.infinity, -1, 101] {
        #expect(!model.activateCustomFanSpeed(percent: percent, seconds: 300))
    }
    for seconds in [Double.nan, .infinity, -1, 0, 31 * 86400 + 1] {
        #expect(!model.activateCustomFanSpeed(percent: 25, seconds: seconds))
    }
    #expect(model.machine.generation == generation && model.machine.selected.id == "cool-chassis" && model.manualIntent == nil)
    #expect(model.activateCustomFanSpeed(percent: 0, seconds: 60))
    #expect(model.machine.selected.floor == 0 && !model.machine.selected.automaticAtIdle)
    #expect(model.activateCustomFanSpeed(percent: 100, seconds: 60))
    #expect(model.machine.selected.floor == 100)
}

@MainActor @Test func temporarySpeedCanBeRetimedCancelledAndHiddenWithoutChangingDefault() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = SpeedClock()
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: clock.date)
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    #expect(model.activateCustomFanSpeed(percent: 30, seconds: 300))
    for _ in 0..<7 { await model.tick() }
    model.activateFor(seconds: 600)
    #expect(model.manualIntent?.limit == .deadline(clock.date().addingTimeInterval(600)))
    model.activateForever()
    #expect(model.manualIntent?.limit == .forever && model.automation.preferences.defaultProfileID == "cool-chassis")
    let menu = NSMenu(), presenter = StatusMenu(model: model, install: false)
    presenter.rebuild(menu)
    let row = menu.items.first { $0.title == "Custom Fan Speed" }
    #expect(row?.state == .on && row?.isEnabled == true)
    #expect(row?.submenu?.items.first?.view?.accessibilityIdentifier() == "activation.fan-speed")
    model.setPreferences { $0.showCustomFanSpeed = false }; presenter.rebuild(menu)
    #expect(!menu.items.contains { $0.title == "Custom Fan Speed" })
    #expect(model.isCustomFanSpeedActive && model.manualIntent?.limit == .forever)
    model.cancelActivation(); for _ in 0..<8 { await model.tick() }
    #expect(!model.isCustomFanSpeedActive && model.machine.selected.id == "cool-chassis")
}

@MainActor @Test func temporarySpeedUsesCurrentScheduleAfterExpiryAndSurvivesOnlyValidWake() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = SpeedClock()
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: clock.date)
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    #expect(model.activateCustomFanSpeed(percent: 25, seconds: 60))
    for _ in 0..<7 { await model.tick() }
    let intent = model.manualIntent
    await model.systemWillSleep(); clock.advance(20); await model.systemDidWake()
    #expect(model.isCustomFanSpeedActive && model.manualIntent == intent)
    model.stop(); for _ in 0..<7 { await model.tick() }
    var config = model.automation
    let weekday = (Calendar.current.component(.weekday, from: clock.date()) + 5) % 7 + 1
    config.periods = [.init(profileID: "school", weekday: weekday, startMinute: 0, endMinute: 1440)]
    model.setAutomation(config)
    await model.systemWillSleep(); clock.advance(61); await model.systemDidWake(); model.stop()
    for _ in 0..<8 { await model.tick() }
    #expect(!model.isCustomFanSpeedActive && model.machine.selected.id == "school")
    #expect(model.automation.preferences.defaultProfileID == "cool-chassis")
}

@MainActor @Test func temporarySpeedCannotBypassEligibilityOrSleepAndFaultsReturnToSystem() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let unqualified = AppModel(storeURL: dir.appendingPathComponent("real.json"), autoStart: false,
                               capabilities: HardwareCapabilities(model: "Unsupported"), helperAvailable: { false })
    #expect(!unqualified.activateCustomFanSpeed(percent: 25, seconds: 300))
    #expect(unqualified.machine.selected.id == "system")
    let model = AppModel(storeURL: dir.appendingPathComponent("mock.json"), autoStart: false, simulation: true)
    await model.systemWillSleep()
    #expect(!model.activateCustomFanSpeed(percent: 25, seconds: 300))
    await model.systemDidWake(); model.stop()
    #expect(model.activateCustomFanSpeed(percent: 25, seconds: 300))
    for _ in 0..<7 { await model.tick() }
    model.scenario = .sensorFailure; await model.tick()
    #expect(!model.isCustomFanSpeedActive && model.manualIntent == nil)
    #expect(model.machine.selected.id == "system")
    model.scenario = .comfortableSchool; for _ in 0..<8 { await model.tick() }
    #expect(model.machine.selected.id == "system")
}

@MainActor @Test func temporarySpeedSurvivesSavedProfileEditsAndNeverLeaksIntoArchives() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("profiles.json")
    let model = AppModel(storeURL: url, autoStart: false, simulation: true)
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    #expect(model.activateCustomFanSpeed(percent: 35, seconds: 300))
    for _ in 0..<7 { await model.tick() }
    let intent = model.manualIntent, id = model.machine.selected.id
    model.create(); await model.waitForCollection()
    #expect(model.isCustomFanSpeedActive && model.manualIntent == intent)
    #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains(id))
    let exported = try ConfigurationInterchange.encode(PortableConfiguration(profiles: model.profiles, automation: model.automation))
    #expect(!String(decoding: exported, as: UTF8.self).contains(id))
    var next = model.profiles
    next[next.firstIndex { $0.id == "school" }!].name = "Quiet study"
    model.commitConfiguration(profiles: next, automation: model.automation, selection: "school")
    await model.waitForCollection()
    #expect(model.isCustomFanSpeedActive && model.manualIntent == intent)
    model.editorHistory.undo()
    #expect(model.isCustomFanSpeedActive && model.manualIntent == intent)
    model.select("system"); for _ in 0..<5 { await model.tick() }
    #expect(!model.isCustomFanSpeedActive && model.temporaryFanSpeedProfile == nil && model.manualIntent == nil)
}

@MainActor @Test func temporarySpeedReplacesOnlyItsOwnTimerAndNormalSelectionsRetireIt() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let clock = SpeedClock()
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true, wallClock: clock.date)
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    #expect(model.activateCustomFanSpeed(percent: 70, seconds: 10))
    let firstID = model.machine.selected.id, firstGeneration = model.machine.generation
    #expect(model.activateCustomFanSpeed(percent: 20, seconds: 600))
    #expect(model.machine.generation > firstGeneration && model.machine.selected.id != firstID)
    clock.advance(11); for _ in 0..<7 { await model.tick() }
    #expect(model.isCustomFanSpeedActive && model.machine.lastDemand?.percent == 20 && model.machine.percent <= 20)
    model.activateUntil(clock.date().addingTimeInterval(120))
    #expect(model.manualIntent?.limit == .deadline(clock.date().addingTimeInterval(120)))
    model.select("school"); for _ in 0..<7 { await model.tick() }
    #expect(model.machine.selected.id == "school" && model.temporaryFanSpeedProfile == nil && model.manualIntent == nil)
    #expect(model.automation.preferences.defaultProfileID == "school")
}
