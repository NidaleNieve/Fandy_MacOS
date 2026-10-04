import AppKit
import SwiftUI
import Testing
@testable import FandyCore
@testable import FandyApp

@Test func graphRequestMatchesProductionCurveFloorAndTargetWithoutEditingNodes() throws {
    let curve = FanCurve(.chip, [(40, 10), (80, 90)])
    let target = TemperatureTarget(input: .chip, celsius: 65)
    let profile = Profile(name: "Preview", curves: [curve], floor: 35, targetTemperature: target)
    let preview = CurveRequestPreview(floor: profile.floor, target: target)
    for temperature in [40.0, 50, 60, 70, 80, 90] {
        let readings = SensorRole.allCases.map { SensorReading($0, $0 == .cpuPeak || $0 == .gpuPeak ? temperature : 30, at: 20) }
        let snapshot = HardwareSnapshot(at: 20, sensors: readings, fans: [Fan(id: 0, min: 2000, max: 8000, actual: 2000)])
        let demand = try ProfileEngine().evaluate(profile, snapshot: snapshot, now: 20)
        #expect(try preview.percent(at: temperature, curve: curve) == demand.percent)
    }
    #expect(profile.curves[0] == curve)
    #expect(try CurveRequestPreview(floor: 60).percent(at: 40, curve: curve) == 60)
    #expect(try CurveRequestPreview(floor: 0).percent(at: 40, curve: curve) == 10)
}

@Test func graphRequestRespectsDisabledInputsSeparateScalesAndRejectsCorruption() throws {
    let disabled = FanCurve(.airflow, [(33, 20), (50, 90)], enabled: false)
    let preview = CurveRequestPreview(floor: 25, target: .init(input: .trackpad, celsius: 29))
    #expect(try preview.percent(at: 44, curve: disabled) == 25)
    #expect(try CurveRequestPreview(target: .init(input: .airflow, celsius: 36)).percent(at: 36, curve: disabled) == 50)
    #expect(throws: (any Error).self) { try preview.percent(at: .nan, curve: disabled) }
    #expect(throws: (any Error).self) { try CurveRequestPreview(floor: .infinity).percent(at: 40, curve: disabled) }
    #expect(throws: (any Error).self) { try CurveRequestPreview(target: .init(input: .airflow, celsius: .nan)).percent(at: 40, curve: disabled) }
    let expanded = CurveRequestPreview(target: .init(input: .airflow, celsius: 80)).range(for: disabled)
    #expect(expanded.contains(80) && expanded.upperBound == 88)
    #expect(preview.range(for: disabled) == CurveDraft(disabled).range)
}

@MainActor @Test func profileContextActionsUseClickedIdentityAndKeepBuiltinsProtected() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    var exported: String?
    let coordinator = ProfileSidebar.Coordinator(model: model, exportProfile: { exported = $0 }), table = NSTableView()
    coordinator.table = table; coordinator.update(); model.editorSelection = "school"
    let index = try #require(model.profiles.firstIndex { $0.id == "gaming" })
    let menu = try #require(coordinator.menu(for: index))
    #expect(menu.items.map(\.title) == ["Rename…", "Duplicate", "Export…", "Remove"])
    #expect(menu.items.last?.isEnabled == false)
    menu.performActionForItem(at: 2)
    #expect(exported == "gaming" && model.editorSelection == "school")
    menu.performActionForItem(at: 1); await model.waitForCollection()
    let copy = try #require(model.edited)
    #expect(copy.curves == BuiltInProfiles.gaming.curves && !copy.bundled)
    model.editorSelection = "school"; coordinator.update()
    let copyIndex = try #require(model.profiles.firstIndex { $0.id == copy.id })
    let removal = try #require(coordinator.menu(for: copyIndex)); removal.performActionForItem(at: 3)
    await model.waitForCollection()
    #expect(!model.profiles.contains { $0.id == copy.id } && model.editorSelection == "school")
    model.delete("system"); model.delete("gaming"); model.delete("absent")
    #expect(model.profiles.contains { $0.id == "system" } && model.profiles.contains { $0.id == "gaming" })
}

@MainActor @Test func nativeUntilClockRetainsTwentyFourHourTimeAndMinuteBindings() throws {
    let picker = TimeDial.makePicker()
    #expect(picker.datePickerStyle == .clockAndCalendar && picker.datePickerElements == [.hourMinute])
    #expect(picker.frame.width > 0 && picker.frame.height > 0)
    #expect(picker.frame.width <= 155 && picker.frame.height <= 155)
    var hour = 0, minute = 0
    let coordinator = TimeDial.Coordinator(hour: Binding(get: { hour }, set: { hour = $0 }), minute: Binding(get: { minute }, set: { minute = $0 }))
    picker.dateValue = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 45)))
    coordinator.changed(picker)
    #expect(hour == 23 && minute == 45)
    picker.dateValue = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 0, minute: 5)))
    coordinator.changed(picker)
    #expect(hour == 0 && minute == 5)
}
