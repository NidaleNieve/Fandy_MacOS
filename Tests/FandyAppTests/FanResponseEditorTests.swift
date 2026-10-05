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
