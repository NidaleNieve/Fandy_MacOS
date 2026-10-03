import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FandyCore

struct ActivationDefaultsEditor: View {
    @Bindable var model: AppModel
    let profile: Profile
    @State private var applications: [RunningProcess] = []
    var rule: ProfileActivationDefault { model.automation.activationDefaults[profile.id] ?? .init() }
    var body: some View {
        DisclosureGroup("When activated") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Keep this profile active", selection: Binding(get: { rule.kind }, set: { kind in
                    var next = rule; next.kind = kind
                    if kind == .application, next.applicationID.isEmpty {
                        guard let app = applications.first, let id = app.bundleID else { chooseApplication(); return }
                        next.applicationID = id; next.applicationName = app.name
                    }
                    model.setActivationDefault(next, profileID: profile.id)
                })) {
                    Text("Until changed").tag(ProfileActivationDefault.Kind.forever)
                    Text("For a duration").tag(ProfileActivationDefault.Kind.duration)
                    Text("While an application is running").tag(ProfileActivationDefault.Kind.application)
                }
                if rule.kind == .duration {
                    HStack {
                        Stepper("Hours: \(rule.seconds / 3600)", value: Binding(get: { rule.seconds / 3600 }, set: { value in var next = rule; next.seconds = max(60, value * 3600 + (rule.seconds / 60 % 60) * 60); model.setActivationDefault(next, profileID: profile.id) }), in: 0...743)
                        Stepper("Minutes: \(rule.seconds / 60 % 60)", value: Binding(get: { rule.seconds / 60 % 60 }, set: { value in var next = rule; next.seconds = max(60, (rule.seconds / 3600) * 3600 + value * 60); model.setActivationDefault(next, profileID: profile.id) }), in: 0...59)
                    }
                } else if rule.kind == .application {
                    Picker("Application", selection: Binding(get: { rule.applicationID }, set: { id in
                        guard let app = applications.first(where: { $0.bundleID == id }) else { return }
                        var next = rule; next.applicationID = id; next.applicationName = app.name; model.setActivationDefault(next, profileID: profile.id)
                    })) {
                        if !applications.contains(where: { $0.bundleID == rule.applicationID }) { Text(rule.applicationName.isEmpty ? "Choose an application" : rule.applicationName).tag(rule.applicationID) }
                        ForEach(applications) { app in Text(app.name).tag(app.bundleID ?? "") }
                    }
                    Button("Choose Application…") { chooseApplication() }
                }
                Text("Used by manual selections and shortcuts. Schedules keep their own ranges. Menu durations can override this condition.").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }.onAppear { applications = ProcessCatalog.list(includeHelpers: false).filter { $0.bundleID != nil } }
    }
    private func chooseApplication() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
            var next = rule; next.kind = .application; next.applicationID = id
            next.applicationName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent
            model.setActivationDefault(next, profileID: profile.id)
        }
    }
}
