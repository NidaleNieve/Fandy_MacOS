import AppKit
import Foundation
import Testing
import FandyCore
@testable import FandyApp

@MainActor @Test func customFanSpeedOffersIndefinitelyBeforeFiveMinutes() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("profiles.json")
    let model = AppModel(storeURL: url, autoStart: false, simulation: true)
    let presenter = StatusMenu(model: model, install: false), menu = NSMenu()
    func durations() throws -> NSMenu {
        presenter.rebuild(menu)
        let speed = try #require(menu.items.first { $0.title == "Custom Fan Speed" }?.submenu)
        return try #require(speed.items.compactMap(\.submenu).first { $0.items.contains { $0.title == "Indefinitely" } })
    }
    let choices = try durations()
    #expect(choices.items[0].title == "Indefinitely" && choices.items[1].title == "5 minutes")
    choices.performActionForItem(at: 0)
    #expect(!model.isCustomFanSpeedActive)
    #expect(model.updateCustomFanSpeed(percent: 20))
    #expect(model.manualIntent?.limit == .forever && model.activationDeadline == nil)
    let id = model.machine.selected.id, generation = model.machine.generation
    try durations().performActionForItem(at: 0)
    #expect(model.isCustomFanSpeedActive && model.manualIntent?.limit == .forever)
    #expect(model.machine.selected.id == id && model.machine.generation == generation)
    #expect(model.updateCustomFanSpeed(percent: 21))
    #expect(model.manualIntent?.limit == .forever && model.activationDeadline == nil)
    await model.prepareForTermination()
    let reopened = AppModel(storeURL: url, autoStart: false, simulation: true)
    #expect(!reopened.isCustomFanSpeedActive)
    #expect(reopened.updateCustomFanSpeed(percent: 20))
    #expect(reopened.manualIntent?.limit == .forever && reopened.activationDeadline == nil)
    #expect(reopened.setCustomFanSpeedDuration(minutes: 5))
    #expect(reopened.manualIntent?.limit != .forever && reopened.activationDeadline != nil)
    await reopened.prepareForTermination()
}

@MainActor @Test func customSpeedOtherUsesTheSameForUntilPickerAsProfileTiming() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let presenter = StatusMenu(model: model, install: false), menu = NSMenu()
    presenter.rebuild(menu)
    let speed = try #require(menu.items.first { $0.title == "Custom Fan Speed" }?.submenu)
    let durations = try #require(speed.items.first { $0.title.hasPrefix("For ") }?.submenu)
    let other = try #require(durations.items.first { $0.title == "Other…" }?.submenu)
    presenter.menuWillOpen(other)
    let shared = try #require(other.items.first?.view as? MenuControlHostingView<CustomActivationPicker>)
    let timing = try #require(menu.items.first { $0.title == "Activate for/until" }?.submenu)
    let profileOther = try #require(timing.items.first { $0.title == "Other Time/Until" }?.submenu)
    presenter.menuWillOpen(profileOther)
    #expect(profileOther.items.first?.view is MenuControlHostingView<CustomActivationPicker>)
    #expect(!model.isCustomFanSpeedActive && model.manualIntent == nil)
    #expect(shared.frame.size == profileOther.items.first?.view?.frame.size)
    await model.prepareForTermination()
}

@MainActor @Test func sharedCustomSpeedPickerRemembersDurationAndRetimesOnlyOnConfirmation() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    #expect(model.setCustomFanSpeedDuration(minutes: 75))
    let picker = CustomActivationPicker(model: model, destination: .customFanSpeed, close: {})
    #expect(picker.initialDurationMinutes == 75 && !model.isCustomFanSpeedActive)
    #expect(picker.applyInterval(40 * 60))
    #expect(model.automation.preferences.customFanSpeedDurationMinutes == 40 && !model.isCustomFanSpeedActive)
    #expect(model.updateCustomFanSpeed(percent: 20))
    let id = model.machine.selected.id, generation = model.machine.generation, intent = model.manualIntent
    for bad in [0, -1, Double.nan, .infinity, 31 * 86400 + 1] { #expect(!picker.applyInterval(bad)) }
    #expect(model.manualIntent == intent)
    // Until reuses the same validated interval path and retains the exact deadline.
    #expect(picker.applyInterval(91))
    #expect(model.manualIntent?.limit != intent?.limit)
    #expect(try #require(model.activationDeadline) - model.clockNow() > 90)
    #expect(model.automation.preferences.customFanSpeedDurationMinutes == 2)
    #expect(model.machine.selected.id == id && model.machine.generation == generation)
    await model.prepareForTermination()
}
