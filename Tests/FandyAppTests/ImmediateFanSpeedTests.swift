import AppKit
import Foundation
import Testing
import FandyCore
@testable import FandyApp

@MainActor @Test func sliderChangesStartControlAndPreserveItsOriginalTimerAndAdmission() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.select("cool-chassis"); for _ in 0..<7 { await model.tick() }
    let view = CustomFanSpeedMenuView(model: model)
    #expect(!model.isCustomFanSpeedActive)
    view.slider.doubleValue = 28
    view.slider.sendAction(view.slider.action, to: view.slider.target)
    #expect(model.isCustomFanSpeedActive && model.machine.selected.floor == 28)
    let id = model.machine.selected.id, intent = model.manualIntent, deadline = model.activationDeadline, generation = model.machine.generation
    for value in [30.0, 32, 34, 36, 38, 40, 42] {
        await model.tick()
        view.slider.doubleValue = value; view.slider.sendAction(view.slider.action, to: view.slider.target)
    }
    await model.tick()
    #expect(model.machine.state == .customActive && model.machine.selected.floor == 42)
    #expect(model.machine.selected.id == id && model.manualIntent == intent && model.activationDeadline == deadline)
    #expect(model.machine.generation == generation)
    #expect(model.automation.preferences.defaultProfileID == "cool-chassis")
    #expect(view.slider.numberOfTickMarks == 0 && view.slider.isContinuous)
    #expect(!view.subviews.contains { ($0 as? NSButton)?.title == "Activate" })
    #expect(!view.subviews.contains { ($0 as? NSTextField)?.stringValue.contains("minimum speed") == true })
    for invalid in [Double.nan, .infinity, -1, 101] { #expect(!model.updateCustomFanSpeed(percent: invalid)) }
    #expect(model.machine.selected.floor == 42 && model.manualIntent == intent)
    await model.prepareForTermination()
}

@MainActor @Test func nativeSpeedDurationSelectionRetimesWithoutReplacingControl() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let view = CustomFanSpeedMenuView(model: model)
    let presenter = StatusMenu(model: model, install: false), menu = NSMenu()
    func choose(_ minutes: Int) throws {
        presenter.rebuild(menu)
        let speed = try #require(menu.items.first { $0.title == "Custom Fan Speed" }?.submenu)
        let duration = try #require(speed.items.first { $0.title.hasPrefix("For ") }?.submenu)
        duration.performActionForItem(at: try #require(duration.items.firstIndex { $0.tag == minutes }))
    }
    try choose(240)
    #expect(!model.isCustomFanSpeedActive)
    view.slider.doubleValue = 25; view.slider.sendAction(view.slider.action, to: view.slider.target)
    let id = model.machine.selected.id, generation = model.machine.generation
    let first = try #require(model.activationDeadline)
    try choose(5)
    #expect(model.activationDeadline! < first - 13_000)
    #expect(model.machine.selected.id == id && model.machine.generation == generation)
    let reopened = CustomFanSpeedMenuView(model: model)
    #expect(reopened.slider.doubleValue == 25)
    let intent = model.manualIntent
    reopened.slider.doubleValue = 20; reopened.slider.sendAction(reopened.slider.action, to: reopened.slider.target)
    #expect(model.machine.selected.id == id && model.manualIntent == intent)
    await model.prepareForTermination()
}

@MainActor private final class TrackingProbe: NSSliderCell {
    var trackedUntilMouseUp = false
    override func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView, untilMouseUp flag: Bool) -> Bool {
        trackedUntilMouseUp = flag; return true
    }
}

@MainActor @Test func nativeSliderRetainsDragUntilMouseUpInsteadOfEndingAtMenuEdge() throws {
    let slider = MenuFanSpeedSlider(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    let cell = TrackingProbe(); slider.cell = cell
    let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    slider.mouseDown(with: event)
    #expect(cell.trackedUntilMouseUp)
}

@MainActor @Test func customSpeedDurationUsesAnActualNativeSubmenuAction() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let presenter = StatusMenu(model: model, install: false), menu = NSMenu()
    presenter.rebuild(menu)
    let speed = try #require(menu.items.first { $0.title == "Custom Fan Speed" }?.submenu)
    let forRow = try #require(speed.items.first { $0.title.hasPrefix("For ") })
    #expect(forRow.view == nil)
    let durations = try #require(forRow.submenu)
    let index = try #require(durations.items.firstIndex { $0.tag == 240 })
    #expect(durations.items[index].isEnabled)
    durations.performActionForItem(at: index)
    #expect(!model.isCustomFanSpeedActive)
    presenter.rebuild(menu)
    let rebuilt = try #require(menu.items.first { $0.title == "Custom Fan Speed" }?.submenu)
    #expect(rebuilt.items.contains { $0.title == "For 4 hours" })
    let view = try #require(rebuilt.items.first?.view as? CustomFanSpeedMenuView)
    view.slider.doubleValue = 25; view.slider.sendAction(view.slider.action, to: view.slider.target)
    #expect(model.isCustomFanSpeedActive)
    #expect(try #require(model.activationDeadline) - model.clockNow() > 14_399)
    await model.prepareForTermination()
}

@MainActor @Test func unfinishedCustomDurationKeepsTheExistingTimerAndSpeedEditable() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let view = CustomFanSpeedMenuView(model: model)
    view.slider.doubleValue = 25; view.slider.sendAction(view.slider.action, to: view.slider.target)
    let intent = model.manualIntent
    let durationView = CustomActivationPicker(model: model, destination: .customFanSpeed, close: {})
    #expect(model.manualIntent == intent)
    #expect(!durationView.applyInterval(.nan))
    view.slider.doubleValue = 40; view.slider.sendAction(view.slider.action, to: view.slider.target)
    #expect(model.machine.selected.floor == 40 && model.manualIntent == intent)
    #expect(!durationView.applyInterval(0))
    #expect(model.manualIntent == intent)
    #expect(durationView.applyInterval(15 * 60))
    #expect(model.manualIntent != intent && model.machine.selected.floor == 40)
    await model.prepareForTermination()
}

@MainActor @Test func temporaryDurationRemembersTheChoiceAcrossReopeningAndRestart() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("profiles.json")
    let model = AppModel(storeURL: url, autoStart: false, simulation: true)
    #expect(model.setCustomFanSpeedDuration(minutes: 75))
    #expect(model.updateCustomFanSpeed(percent: 20))
    let intent = model.manualIntent, deadline = model.activationDeadline
    for _ in 0..<3 {
        let menu = NSMenu(), presenter = StatusMenu(model: model, install: false)
        presenter.rebuild(menu)
        let speed = try #require(menu.items.first { $0.title == "Custom Fan Speed" }?.submenu)
        #expect(speed.items.contains { $0.title == "For 1 hour 15 minutes" })
        #expect(model.manualIntent == intent && model.activationDeadline == deadline)
        let view = try #require(speed.items.first?.view as? CustomFanSpeedMenuView)
        view.slider.doubleValue = 21; view.slider.sendAction(view.slider.action, to: view.slider.target)
        #expect(model.manualIntent == intent)
    }
    for bad in [0, -1, 44_641, Int.max] { #expect(!model.setCustomFanSpeedDuration(minutes: bad)) }
    #expect(model.automation.preferences.customFanSpeedDurationMinutes == 75 && model.manualIntent == intent)
    await model.prepareForTermination()
    let reopened = AppModel(storeURL: url, autoStart: false, simulation: true)
    #expect(!reopened.isCustomFanSpeedActive && reopened.automation.preferences.customFanSpeedDurationMinutes == 75)
    #expect(reopened.updateCustomFanSpeed(percent: 20))
    #expect(try #require(reopened.activationDeadline) - reopened.clockNow() > 4499)
    reopened.activateFor(seconds: 600)
    #expect(reopened.automation.preferences.customFanSpeedDurationMinutes == 10)
    await reopened.prepareForTermination()
}
