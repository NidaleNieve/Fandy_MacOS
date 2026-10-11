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
    view.durationPopup.selectItem(withTag: 240)
    view.durationPopup.sendAction(view.durationPopup.action, to: view.durationPopup.target)
    #expect(!model.isCustomFanSpeedActive)
    view.slider.doubleValue = 25; view.slider.sendAction(view.slider.action, to: view.slider.target)
    let id = model.machine.selected.id, generation = model.machine.generation
    let first = try #require(model.activationDeadline)
    view.durationPopup.selectItem(withTag: 5)
    view.durationPopup.sendAction(view.durationPopup.action, to: view.durationPopup.target)
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

@MainActor @Test func unfinishedCustomDurationKeepsTheExistingTimerAndSpeedEditable() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    let view = CustomFanSpeedMenuView(model: model)
    view.slider.doubleValue = 25; view.slider.sendAction(view.slider.action, to: view.slider.target)
    let intent = model.manualIntent
    view.durationPopup.selectItem(withTag: 0)
    view.durationPopup.sendAction(view.durationPopup.action, to: view.durationPopup.target)
    #expect(model.manualIntent == intent)
    let minutes = try #require(view.subviews.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Minutes" })
    minutes.stringValue = ""
    view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: minutes))
    view.slider.doubleValue = 40; view.slider.sendAction(view.slider.action, to: view.slider.target)
    #expect(model.machine.selected.floor == 40 && model.manualIntent == intent)
    minutes.stringValue = "0"
    view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: minutes))
    #expect(model.manualIntent == intent)
    minutes.stringValue = "15"
    view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: minutes))
    #expect(model.manualIntent != intent && model.machine.selected.floor == 40)
    await model.prepareForTermination()
}
