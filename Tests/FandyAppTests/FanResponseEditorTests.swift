import Foundation
import Testing
@testable import FandyCore
@testable import FandyApp

@Test func airflowNoteAppearsOnlyForSelectedAirflowProxy() {
    #expect(ProfileEditorPresentation.showsAirflowNote(input: .airflow, simulation: false, topName: "Top proximity"))
    for input in [CurveInput.chip, .trackpad, .actuator] {
        #expect(!ProfileEditorPresentation.showsAirflowNote(input: input, simulation: false, topName: "Top proximity"))
    }
    #expect(!ProfileEditorPresentation.showsAirflowNote(input: .airflow, simulation: true, topName: "Top proximity"))
    #expect(!ProfileEditorPresentation.showsAirflowNote(input: .airflow, simulation: false, topName: "Airflow Top"))
}

@MainActor @Test func fanResponseAndChipSelectionCanBeUndoneAndPersisted() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.editorHistory.groupsByEvent = false
    model.editorSelection = "school"
    let original = try #require(model.edited)
    var next = original; next.fanResponse = 0.7; next.chipSources = [.gpu]
    model.beginEditGroup(); model.update(next); model.endEditGroup(); #expect(model.edited == next)
    model.editorHistory.undo(); #expect(model.edited == original)
    model.editorHistory.redo(); #expect(model.edited == next)
    try await model.prepareForUpdate()
    #expect(ProfileStore(url: dir.appendingPathComponent("profiles.json")).load().profiles.first { $0.id == "school" } == next)
}

@Test func fanResponseShowsNumbersTimingAndIdleExplanation() {
    #expect(ProfileEditorPresentation.responseValue(BuiltInProfiles.school) == "0%")
    #expect(ProfileEditorPresentation.responseValue(BuiltInProfiles.gaming) == "100%")
    #expect(ProfileEditorPresentation.responseSummary(BuiltInProfiles.school) == "3.0 s smoothing · up to 2 percentage points/s")
    #expect(ProfileEditorPresentation.responseSummary(BuiltInProfiles.gaming) == "0.0 s smoothing · up to 10 percentage points/s")
    #expect(ProfileEditorPresentation.idleHelp.contains("macOS"))
    #expect(ProfileEditorPresentation.idleTimingHelp.contains("15 seconds") && ProfileEditorPresentation.idleTimingHelp.contains("minimum airflow"))
}

@MainActor @Test func verifiedThermalHandbackRetainsItsReasonUntilExplicitSelection() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, simulation: true)
    model.select("school"); for _ in 0..<6 { await model.tick() }
    model.scenario = .overheating; await model.tick()
    #expect(model.machine.state == .system && model.machine.selected.kind == .system)
    #expect(model.statusText.contains("macOS control — elevated thermal pressure"))
    model.scenario = .comfortableSchool; await model.tick()
    #expect(model.statusText.contains("elevated thermal pressure") && model.defaultResumeBlocked)
    model.select("system"); await model.tick()
    #expect(!model.statusText.contains("elevated thermal pressure"))
}
