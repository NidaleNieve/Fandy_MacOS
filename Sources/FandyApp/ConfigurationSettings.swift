import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import FandyCore

struct ConfigurationSettings: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var incoming: Data?
    @State private var importSummary = ""
    @State private var confirming = false
    @State private var loginStatus = SMAppService.mainApp.status
    var body: some View {
        Section("Preferences") {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                .accessibilityIdentifier("settings.version")
            Toggle("Launch at login", isOn: Binding(get: { model.automation.preferences.launchAtLogin }, set: { enabled in
                model.setPreferences { $0.launchAtLogin = enabled }; model.configureLogin(); loginStatus = SMAppService.mainApp.status
            }))
            if loginStatus == .requiresApproval { Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() } }
            Toggle("Use 24-hour time", isOn: Binding(get: { model.automation.preferences.use24HourTime }, set: { enabled in model.setPreferences { $0.use24HourTime = enabled } }))
        }
        Section("Menu Bar Menu") {
            Toggle("Show fan speed bar", isOn: Binding(get: { model.automation.preferences.showFanSpeedBar }, set: { value in model.setPreferences { $0.showFanSpeedBar = value } }))
            Toggle("Show fan percentage and RPM", isOn: Binding(get: { model.automation.preferences.showFanSpeedNumbers }, set: { value in model.setPreferences { $0.showFanSpeedNumbers = value } }))
            Text("Temperatures").font(.subheadline)
            NativeSearchField(placeholder: "Search sensors", text: $search).frame(height: 24)
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(visibleChoices) { choice in
                        if choice.id == firstRawID { Divider().padding(.vertical, 4); Text("Raw temperature sensors").font(.caption).foregroundStyle(.secondary) }
                        Toggle(choice.name + (choice.estimate && !choice.name.contains("estimate") ? " · estimate" : ""), isOn: Binding(get: { model.automation.preferences.menuSensors.contains(choice.id) }, set: { enabled in
                            model.setPreferences { prefs in
                                if enabled && prefs.menuSensors.count < 16 { prefs.menuSensors.append(choice.id) }
                                else if !enabled { prefs.menuSensors.removeAll { $0 == choice.id } }
                            }
                        })).disabled(!model.automation.preferences.menuSensors.contains(choice.id) && model.automation.preferences.menuSensors.count >= 16)
                    }
                    ForEach(model.automation.preferences.menuSensors.filter { id in !model.sensorMenu.choices.contains { $0.id == id } }, id: \.self) { id in
                        HStack { Text("\(id) · unavailable on this Mac").font(.caption); Button("Remove") { model.setPreferences { $0.menuSensors.removeAll { $0 == id } } } }
                    }
                }.padding(.vertical, 4)
            }.frame(height: 160)
            Text("Up to 16 readouts. Raw keys and region estimates are display-only. Physical core/cluster identities are not certified on this model.").font(.caption).foregroundStyle(.secondary)
            if model.sensorMenu.discovering { ProgressView("Finding temperature sensors…") }
            if let error = model.sensorMenu.discoveryError { Text(error).font(.caption); Button("Retry Discovery") { Task { await model.sensorMenu.discover() } } }
        }
        ShortcutSettings(model: model)
        Section("Configuration Files") {
            HStack { Button("Export All Settings…") { exportFile() }; Button("Import All Settings…") { importFile() } }
            Text("Includes profiles, schedules, pauses and preferences. Import replaces the entire configuration and returns fans to System. Timers, watched processes and hardware authority are excluded.").font(.caption).foregroundStyle(.secondary)
        }
        .alert("Replace All Settings?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) { incoming = nil }
            Button("Replace", role: .destructive) { if let incoming { model.importConfiguration(incoming) }; incoming = nil }
        } message: { Text(importSummary) }
        .task { loginStatus = SMAppService.mainApp.status; if !model.simulation { await model.sensorMenu.discover() } }
    }
    private var visibleChoices: [MenuSensor] {
        let matched = model.sensorMenu.choices.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        return matched.filter { !$0.isRaw } + matched.filter { $0.isRaw }
    }
    private var firstRawID: String? { visibleChoices.first { $0.isRaw }?.id }
    private func exportFile() {
        let panel = ExportSavePanel.make(filename: "Fandy Configuration.json")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try model.exportConfiguration()
                Task {
                    do { try await Task.detached { try data.write(to: url, options: .atomic) }.value }
                    catch { model.draftError = "Configuration export failed." }
                }
            } catch { model.draftError = error.localizedDescription }
        }
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    let data = try await Task.detached { try ProfileStore.readBounded(url) }.value
                    let config = try ConfigurationInterchange.decode(data)
                    incoming = data
                    importSummary = "Replace your current configuration with \(config.profiles.count) profiles, \(config.automation.periods.count) schedule ranges and \(config.automation.pauses.count) pauses?"
                    confirming = true
                } catch { model.draftError = "Import rejected: \(error.localizedDescription)" }
            }
        }
    }
}
