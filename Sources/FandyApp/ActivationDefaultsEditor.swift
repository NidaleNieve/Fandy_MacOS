import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FandyCore

struct ActivationDefaultsEditor: View {
    @Bindable var model: AppModel
    let profile: Profile
    @State private var showingProcesses = false
    @State private var enableLaunchAfterChoosing = false
    @State private var enableClosingAfterChoosing = false
    var rule: ProfileActivationDefault { model.automation.activationDefaults[profile.id] ?? .init() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Activate when any selected application opens", isOn: Binding(get: { rule.launchWhenOpened }, set: { enabled in
                if enabled && rule.applications.isEmpty { enableLaunchAfterChoosing = true; showingProcesses = true; return }
                var next = rule; next.launchWhenOpened = enabled; save(next)
            }))
            if !rule.applications.isEmpty {
                ForEach(rule.applications, id: \.matchingIdentifier) { application in
                    HStack {
                        Label(application.name, systemImage: application.kind == .process ? "terminal" : "app")
                        Spacer()
                        Button { remove(application) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Remove \(application.name)")
                    }
                }
            }
            Menu("Add Applications…") {
                Button("Installed Applications…") { chooseInstalledApplications() }
                Button("Running Applications and Processes…") { showingProcesses = true }
            }.fixedSize()
            if rule.launchWhenOpened {
                Toggle("Turn off when all selected applications close", isOn: Binding(get: { rule.kind == .application }, set: { enabled in
                    var next = rule; next.kind = enabled ? .application : .forever; save(next)
                }))
                Text("Manual selections take priority. Applications already open at startup or wake do not trigger activation.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Picker("Keep this profile active", selection: Binding(get: { rule.kind }, set: { kind in
                if kind == .application && rule.applications.isEmpty { enableClosingAfterChoosing = true; showingProcesses = true; return }
                var next = rule; next.kind = kind; save(next)
            })) {
                Text("Until changed").tag(ProfileActivationDefault.Kind.forever)
                Text("For a duration").tag(ProfileActivationDefault.Kind.duration)
                Text("While any selected application is running").tag(ProfileActivationDefault.Kind.application)
            }
            if rule.kind == .duration {
                HStack {
                    Stepper("Hours: \(rule.seconds / 3600)", value: Binding(get: { rule.seconds / 3600 }, set: { value in var next = rule; next.seconds = max(60, value * 3600 + (rule.seconds / 60 % 60) * 60); save(next) }), in: 0...743)
                    Stepper("Minutes: \(rule.seconds / 60 % 60)", value: Binding(get: { rule.seconds / 60 % 60 }, set: { value in var next = rule; next.seconds = max(60, (rule.seconds / 3600) * 3600 + value * 60); save(next) }), in: 0...59)
                }
            }
            Text("Used by manual selections and shortcuts. Schedules keep their own ranges. Menu durations can override this condition.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.top, 8)
            .sheet(isPresented: $showingProcesses, onDismiss: { enableLaunchAfterChoosing = false; enableClosingAfterChoosing = false }) {
                ProfileApplicationsPicker { add($0) }
            }
    }
    private func save(_ next: ProfileActivationDefault) { model.setActivationDefault(next, profileID: profile.id) }
    private func remove(_ application: ProfileApplication) {
        var next = rule; next.applications.removeAll { $0.matchingIdentifier == application.matchingIdentifier }
        if next.applications.isEmpty { next.launchWhenOpened = false; if next.kind == .application { next.kind = .forever } }
        save(next)
    }
    private func add(_ applications: [ProfileApplication]) {
        guard !applications.isEmpty else { return }
        var next = rule
        for app in applications where !next.applicationIdentifiers.contains(app.matchingIdentifier) { next.applications.append(app) }
        if enableLaunchAfterChoosing { next.launchWhenOpened = true }
        if enableClosingAfterChoosing { next.kind = .application }
        save(next)
    }
    private func chooseInstalledApplications() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            add(panel.urls.compactMap { url in
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? url.deletingPathExtension().lastPathComponent
                return ProfileApplication(id: id, name: name)
            })
        }
    }
}

private struct ProfileApplicationsPicker: View {
    let add: ([ProfileApplication]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var showHelpers = false
    @State private var entries: [RunningProcess] = []
    @State private var selected = Set<String>()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Applications").font(.headline)
            TextField("Search applications and processes", text: $search).textFieldStyle(.roundedBorder)
            Toggle("Show helper apps and processes", isOn: $showHelpers)
            List(selection: $selected) {
                ForEach(entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }, id: \.activationCondition.matchingIdentifier) { process in
                    HStack {
                        if let icon = process.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                        else { Image(systemName: process.bundleID == nil ? "terminal" : "app").frame(width: 20) }
                        Text(process.name)
                    }.tag(process.activationCondition.matchingIdentifier)
                }
            }.scrollIndicators(.hidden)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { add(entries.filter { selected.contains($0.activationCondition.matchingIdentifier) }.map(\.activationCondition)); dismiss() }
                    .disabled(selected.isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(width: 420, height: 380)
            .onAppear { reload() }.onChange(of: showHelpers) { reload() }
    }
    private func reload() {
        var seen = Set<String>()
        entries = ProcessCatalog.list(includeHelpers: showHelpers).filter {
            (try? $0.activationCondition.validate()) != nil && seen.insert($0.activationCondition.matchingIdentifier).inserted
        }
        selected.formIntersection(Set(entries.map(\.activationCondition.matchingIdentifier)))
    }
}
