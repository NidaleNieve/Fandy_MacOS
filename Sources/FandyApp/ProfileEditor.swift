import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import FandyCore
import FandyHardware

struct ProfileEditor: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
        ProfileSplitView {
            ProfileSidebarPanel(model: model, importFile: importFile, exportFile: { exportFile() }, exportProfile: exportFile)
        } detail: {
            ProfileWorkspace(model: model)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        if model.needsHelperSetup { Divider(); HelperApprovalNotice(model: model).padding(10).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .sheet(item: $model.scheduleReview) { _ in ScheduleConflictSheet(model: model) }
        .sheet(item: $model.renameRequest) { request in ProfileRenameSheet(model: model, request: request) }
        .disabled(model.savingCollection)
        .toolbar {
            ToolbarItem {
                Button { model.editorHistory.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!model.canUndo || model.savingCollection).help("Undo profile changes").keyboardShortcut("z")
                    .contextMenu { Button("Redo") { model.editorHistory.redo() }.disabled(!model.canRedo || model.savingCollection).keyboardShortcut("z", modifiers: [.command, .shift]) }
            }
        }
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do { let data = try await Task.detached { try ProfileStore.readBounded(url) }.value; model.importProfiles(data) }
                catch { model.draftError = "Profile file could not be read." }
            }
        }
    }
    private func exportFile(_ id: String? = nil) {
        guard let profile = model.profiles.first(where: { $0.id == (id ?? model.editorSelection) }) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Fandy Profile.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let config = model.automation
            Task {
                do { try await Task.detached { try ScheduledProfileInterchange.encode(profile, automation: config).write(to: url, options: .atomic) }.value }
                catch { model.draftError = "Profile file could not be exported." }
            }
        }
    }
}

private struct ProfileSidebarPanel: View {
    @Bindable var model: AppModel
    let importFile: () -> Void
    let exportFile: () -> Void
    let exportProfile: (String) -> Void
    var body: some View {
        VStack(spacing: 0) {
            Text("Profiles").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            ProfileSidebar(model: model, profiles: model.profiles, selection: model.editorSelection, activeID: model.menuSelectionID, exportProfile: exportProfile)
            Divider()
            HStack(spacing: 6) {
                Button { model.create() } label: { Image(systemName: "plus").frame(width: 16, height: 16) }.help("Create profile").accessibilityLabel("Create profile")
                Button { model.duplicate() } label: { Image(systemName: "square.on.square").frame(width: 16, height: 16) }.disabled(model.edited == nil).help("Duplicate profile").accessibilityLabel("Duplicate profile")
                Button { model.delete() } label: { Image(systemName: "minus").frame(width: 16, height: 16) }.disabled(model.edited?.bundled != false).help("Delete profile").accessibilityLabel("Delete profile")
                Menu {
                    Button("Import Profiles…", action: importFile)
                    Button("Export Selected Profile…", action: exportFile).disabled(model.edited == nil)
                } label: { Image(systemName: "ellipsis.circle") }.help("Profile files")
                Spacer(minLength: 0)
            }.buttonStyle(.bordered).controlSize(.small).padding(10)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial).disabled(model.savingCollection)
    }
}
private struct ProfileWorkspace: View {
    @State private var showingSchedule = false
    @Bindable var model: AppModel
    var body: some View {
        ProfileDetailSplitView {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("See Schedule", systemImage: "calendar") { showingSchedule = true }
                        .controlSize(.small).accessibilityIdentifier("schedule.overview")
                }.padding(.horizontal, 16).padding(.top, 10)
                ProfileDetail(model: model).frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }.frame(minWidth: 0, maxWidth: .infinity)
        } monitoring: {
            ScrollView { SensorStatus(model: model).padding(14).frame(maxWidth: .infinity, alignment: .leading) }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial)
        }.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity).disabled(model.savingCollection)
        .sheet(isPresented: $showingSchedule) { WeeklyScheduleOverview(model: model) }
    }
}
private struct ProfileDetail: View {
    @Bindable var model: AppModel
    @State private var tab = EditorTab.curves
    @State private var chipExpanded = true
    @State private var chassisExpanded = true
    enum EditorTab: String, CaseIterable { case curves = "Fan Curves", schedule = "Schedule", pauses = "Pause Schedule", activation = "When Activated" }
    var body: some View {
        if let profile = model.edited {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(profile.name).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    Button { model.requestRename(profile.id) } label: { Label("Rename", systemImage: "pencil") }
                        .disabled(profile.protected).help(profile.protected ? "System and Max cannot be renamed" : "Rename profile")
                        .accessibilityIdentifier("profile.rename")
                    Button(model.isSelected(profile.id) ? "Active" : "Use Profile") { model.select(profile.id) }
                        .disabled(model.isSelected(profile.id) || !model.canActivate(profile))
                }
                ViewThatFits(in: .horizontal) {
                    Picker("Profile section", selection: $tab) {
                        ForEach(EditorTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).controlSize(.small).labelsHidden().fixedSize(horizontal: true, vertical: false)
                    Picker("Profile section", selection: $tab) {
                        ForEach(EditorTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).labelsHidden()
                }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch tab {
                        case .curves: fanControls(profile)
                        case .schedule: ScheduleEditor(model: model, profile: profile).id(profile.id)
                        case .pauses: PauseScheduleEditor(model: model, profile: profile).id(profile.id)
                        case .activation: ActivationDefaultsEditor(model: model, profile: profile).id(profile.id)
                        }
                        if let reason = model.activationConditionNote(profile) { Text(reason).font(.caption).foregroundStyle(.secondary) }
                        if let error = model.draftError { Text(error).foregroundStyle(.red).font(.caption).accessibilityIdentifier("curve.validation-error") }
                        if let error = model.saveError {
                            HStack { Text(error).font(.caption).foregroundStyle(.orange); Button("Retry") { model.save() } }
                        }

                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
                }.scrollIndicators(.hidden)
            }.padding(16)
                .onAppear { expandUsedSections(profile) }
                .onChange(of: profile.id) { _, _ in expandUsedSections(profile) }
                .onChange(of: profile.targetTemperature?.input) { _, input in
                    guard let input else { return }
                    if input == .chip { chipExpanded = true }
                    else { chassisExpanded = true; model.curveInput = input }
                }

        } else { ContentUnavailableView("Select a profile", systemImage: "fan") }
    }
    private func expandUsedSections(_ profile: Profile) {
        chipExpanded = profile.curves.contains { $0.input == .chip && $0.enabled } || profile.targetTemperature?.input == .chip
        chassisExpanded = profile.curves.contains { $0.input != .chip && $0.enabled } || profile.targetTemperature.map { $0.input != .chip } == true
        if let input = profile.targetTemperature?.input, input != .chip { model.curveInput = input }
    }
    @ViewBuilder private func fanControls(_ profile: Profile) -> some View {
        if profile.kind == .system { Text("Returns all fans to Apple automatic control.").foregroundStyle(.secondary) }
        else if profile.kind == .maximum { Text("Uses each fan’s reported maximum RPM.").foregroundStyle(.secondary) }
        else {
            DisclosureGroup("Chip", isExpanded: $chipExpanded) {
                CurveSection(profile: profile, input: .chip, model: model)
                if !model.simulation && model.capabilities.chipPolicy == .conservativeEnvelope {
                    Text("Chip uses the hottest reading in the reviewed chip-region envelope. CPU/GPU averages are estimates.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            DisclosureGroup("Chassis", isExpanded: $chassisExpanded) {
                Picker("Sensor", selection: $model.curveInput) {
                    Text("Trackpad").tag(CurveInput.trackpad)
                    Text("Actuator").tag(CurveInput.actuator)
                    Text("Airflow").tag(CurveInput.airflow)
                }.pickerStyle(.segmented).onAppear { if model.curveInput == .chip { model.curveInput = .trackpad } }
                CurveSection(profile: profile, input: model.curveInput == .chip ? .trackpad : model.curveInput, model: model)
                if !model.simulation && model.capabilities.sensorName(.airflowTop) == "Top proximity" {
                    Text("Airflow uses the hottest of Left, Right and the Top proximity input.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text("Minimum airflow")
                Slider(value: Binding(get: { profile.floor }, set: { var next = profile; next.floor = $0.rounded(); model.update(next) }), in: 0...100, onEditingChanged: { editing in if editing { model.beginEditGroup() } else { model.endEditGroup() } })
                Text("\(Int(profile.floor))%").monospacedDigit().frame(width: 40)
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    var next = profile; next.floor = BuiltInProfiles.all.first { $0.id == profile.id }?.floor ?? 0; model.update(next)
                }.help("Reset minimum airflow").controlSize(.small)
            }
            Text("0% uses each fan’s minimum RPM. Apple auto at idle can release control instead.").font(.caption).foregroundStyle(.secondary)
            Toggle("Use Apple auto at idle", isOn: Binding(get: { profile.automaticAtIdle }, set: { var next = profile; next.automaticAtIdle = $0; model.update(next) }))
            Divider()
            TemperatureTargetEditor(model: model, profile: profile)
        }

        if !model.simulation && profile.kind != .system {
            if let preview = model.preview {
                Text(StatusPresentation.demand(preview, active: model.isSelected(profile.id)) + "\n" + StatusPresentation.breakdown(preview, floor: profile.floor))
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("profile.shadow-demand")
            }
            if let reason = model.eligibility(profile).reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
        }
        HStack {
            if profile.bundled && !profile.protected { Button("Reset to Default") { model.reset() } }
            if !profile.bundled {
                Button { model.move(-1) } label: { Image(systemName: "arrow.up") }.disabled(!model.canMove(-1)).help("Move profile up")
                Button { model.move(1) } label: { Image(systemName: "arrow.down") }.disabled(!model.canMove(1)).help("Move profile down")
            }
            Spacer()
        }
    }
}
struct CurveSection: View {
    let profile: Profile
    let input: CurveInput
    @Bindable var model: AppModel
    @State private var resetRevision: UInt64 = 0
    var curve: FanCurve { profile.curves.first { $0.input == input } ?? FanCurve(input, input == .chip ? [(45,0),(85,100)] : input == .airflow ? [(33,0),(60,100)] : [(27,0),(42,100)], enabled: false) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(input.label, isOn: Binding(get: { curve.enabled }, set: { var next = curve; next.enabled = $0; commit(next) }))
                Spacer()
                Button("Reset Curve") { resetCurve() }.font(.caption)
            }
            CurveEditor(curve: curve, request: CurveRequestPreview(floor: profile.floor, target: profile.targetTemperature), resetRevision: resetRevision, currentTemperature: model.curveTemperature(curve), onBegin: { model.beginEditGroup() }, onEnd: { model.endEditGroup() }, onChange: { commit($0) }).id(profile.id + input.rawValue).disabled(!curve.enabled)
        }
    }
    func resetCurve() {
        let original = BuiltInProfiles.all.first { $0.id == profile.id }
        var defaults = original?.curves.first { $0.input == input } ?? [BuiltInProfiles.chip, BuiltInProfiles.trackpad, BuiltInProfiles.actuator, BuiltInProfiles.airflow].first { $0.input == input }!
        defaults.enabled = curve.enabled; commit(defaults); resetRevision &+= 1
    }
    func commit(_ curve: FanCurve) {
        var next = profile
        if let index = next.curves.firstIndex(where: { $0.input == input }) { next.curves[index] = curve }
        else { next.curves.append(curve) }
        model.update(next)
    }
}
struct SensorStatus: View {
    @Bindable var model: AppModel
    private func label(_ role: SensorRole) -> String {
        if role == .cpuAverage { return "CPU" }
        if role == .gpuAverage { return "GPU" }
        if role == .socPeak { return "Chip peak" }
        return model.simulation ? role.name : model.capabilities.sensorName(role)
    }
    private var primary: [SensorRole] { [.cpuAverage,.gpuAverage] + (model.capabilities.chipPolicy == .conservativeEnvelope && !model.simulation ? [.socPeak] : []) + [.trackpad,.airflowLeft,.airflowTop,.airflowRight] }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current").font(.headline)
            Text(model.machine.selected.name).font(.subheadline)
            Text(model.statusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            FanSpeedReadout(model: model)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                ForEach(primary) { role in GridRow { Text(label(role)); Text(model.temperatureText(role)).monospacedDigit().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }
                ForEach(model.snapshot?.fans ?? []) { fan in GridRow { Text("Fan \(fan.id + 1)"); Text("\(Int(fan.actualRPM.rounded())) RPM").monospacedDigit().foregroundStyle(.secondary) } }
            }
            DisclosureGroup("Details") {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                    ForEach([SensorRole.actuator,.charger,.powerSupply,.wireless]) { role in GridRow { Text(role.name); Text(model.temperatureText(role)).monospacedDigit() } }
                }.padding(.top, 5)
            }
            if let error = model.hardwareError ?? model.machine.fault ?? model.issues.first, error != model.statusText {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var confirmingReset = false
    @State private var helperStatus = HelperManager.service.status
    var body: some View {
        ScrollView { Form {
            ConfigurationSettings(model: model)
            Section("Backend") {
                Toggle("Simulation", isOn: Binding(get: { model.simulation }, set: { model.setSimulation($0) }))
                Text("Use simulated temperatures and fans for testing. Physical fan control is disabled.").font(.caption).foregroundStyle(.secondary)
                if model.simulation {
                    Picker("Scenario", selection: $model.scenario) { ForEach(MockScenario.allCases) { Text($0.rawValue).tag($0) } }
                    Button("Simulate Helper Restart") { model.simulateRestart() }
                    Button("Simulate Sleep / Wake") { model.powerTransition() }
                }
            }
            Section("Fan Helper") {
                Text(model.helperRegistrationText)
                if model.needsHelperSetup { HelperApprovalNotice(model: model) }
                Text(model.capabilities.stage == .qualifiedControl ? "Eligible profiles control real fans. System restores Apple automatic control." : model.capabilities.canRestore ? "System and Max are available. Temperature profiles await their required inputs and activation test." : "Custom profiles await hardware verification.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Hardware verification") {
                    LabeledContent("Compatibility", value: model.capabilities.compatibilityEvidence == .locallyTested ? "Locally tested" : model.capabilities.compatibilityEvidence == .referenceSupported ? "Reference supported" : "Monitoring only")
                    LabeledContent("Control inputs", value: "\(model.capabilities.verifiedRoles.intersection(model.capabilities.requiredControlRoles).count) / \(model.capabilities.requiredControlRoles.count) reviewed")
                    LabeledContent("Chip control", value: model.capabilities.chipPolicy == .conservativeEnvelope ? "Conservative envelope" : "CPU/GPU peaks")
                    LabeledContent("Automatic handback", value: model.capabilities.automaticRestoration == .verified ? "Locally verified" : model.capabilities.automaticRestoration.supported ? "Reference supported" : "Unavailable")
                    LabeledContent("Manual control and recovery", value: model.capabilities.manualTransaction == .verified ? "Locally verified" : model.capabilities.manualTransaction.supported ? "Reference supported" : "Unavailable")
                }.accessibilityIdentifier("settings.hardwareVerification")
                Text("Startup and wake begin in System. No telemetry or networking.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Maintenance") {
                Button("Export Diagnostics…") { exportDiagnostics() }
                Button("Reset to Defaults…", role: .destructive) { confirmingReset = true }
                    .disabled(model.savingCollection)
                if let error = model.draftError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }.formStyle(.grouped).padding() }.frame(width: 500, height: 640)
        .alert("Reset Fandy to Defaults?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { model.resetToDefaults() }
        } message: { Text("Removes custom profiles, schedules, activation conditions and shortcuts, resets preferences, and returns fans to System.") }
        .onAppear { refreshRegistration() }
        .task { if !model.simulation { await model.sensorMenu.discover() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshRegistration() } }
    }
    private func refreshRegistration() { model.refreshHelperSetup(); loginStatus = SMAppService.mainApp.status; helperStatus = HelperManager.service.status }
    private func exportDiagnostics() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Fandy Diagnostics.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do { let data = try model.sanitizedDiagnostics(); try await Task.detached { try data.write(to: url, options: .atomic) }.value }
                catch { model.draftError = "Diagnostics could not be exported." }
            }
        }
    }

}
