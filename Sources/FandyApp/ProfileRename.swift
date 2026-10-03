import SwiftUI
import Foundation
import FandyCore

struct ProfileRenameRequest: Identifiable {
    let id: String
    let name: String
}
extension AppModel {
    func requestRename(_ id: String) {
        guard !savingCollection, !isQuitting, scheduleReview == nil, let profile = profiles.first(where: { $0.id == id }), !profile.protected else { return }
        editorSelection = id; renameRequest = ProfileRenameRequest(id: id, name: profile.name)
    }
    @discardableResult func renameProfile(_ id: String, to name: String) -> Bool {
        guard !savingCollection, !isQuitting, var profile = profiles.first(where: { $0.id == id }), !profile.protected else { return false }
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try profile.validate() } catch { draftError = error.localizedDescription; return false }
        update(profile)
        return profiles.first(where: { $0.id == id })?.name == profile.name
    }
}
struct ProfileRenameSheet: View {
    @Bindable var model: AppModel
    let request: ProfileRenameRequest
    @State private var name: String
    @State private var error: String?
    @FocusState private var focused: Bool
    init(model: AppModel, request: ProfileRenameRequest) {
        self.model = model; self.request = request; _name = State(initialValue: request.name)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Rename Profile", systemImage: "pencil").font(.headline)
            TextField("Profile name", text: $name).textFieldStyle(.roundedBorder).focused($focused).onSubmit(save)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { model.renameRequest = nil }.keyboardShortcut(.cancelAction)
                Button("Rename", action: save).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 340).onAppear { focused = true }
    }
    private func save() {
        if model.renameProfile(request.id, to: name) { model.renameRequest = nil }
        else { error = model.draftError ?? "This profile cannot be renamed." }
    }
}
