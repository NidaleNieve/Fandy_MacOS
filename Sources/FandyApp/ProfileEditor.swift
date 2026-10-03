import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ServiceManagement
import FandyCore
import FandyHardware

struct ProfileEditor: View {
    @Bindable var model: AppModel
    @State private var name = ""
    var body: some View {
        NavigationSplitView {
            List(selection: $model.editorSelection) {
                Section("Profiles") {
                    ForEach(model.profiles) { profile in
                        HStack {
                            Text(profile.name)
                            Spacer()
                            if model.isSelected(profile.id) { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                        }.tag(profile.id)
                    }
                }
            }.navigationSplitViewColumnWidth(min: 170, ideal: 185)
            HStack {
                Button { model.create() } label: { Image(systemName: "plus") }.help("Create profile").accessibilityLabel("Create profile")
                Button { model.duplicate() } label: { Image(systemName: "square.on.square") }.disabled(model.edited == nil).help("Duplicate profile").accessibilityLabel("Duplicate profile")
                Button { model.delete() } label: { Image(systemName: "minus") }.disabled(model.edited?.bundled != false).help("Delete profile").accessibilityLabel("Delete profile")
                Menu {
                    Button("Import Profiles…") { importFile() }
                    Button("Export Selected Profile…") { exportFile() }.disabled(model.edited == nil)
                } label: { Image(systemName: "ellipsis.circle") }.help("Profile files")
                Spacer()
            }.padding(10)
        } detail: {
            if let profile = model.edited {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            TextField("Profile name", text: $name).font(.headline).textFieldStyle(.plain)
                                .disabled(profile.protected)
                                .onSubmit { var next = profile; next.name = name; model.update(next) }
                                .accessibilityIdentifier("profile.name")
                            Button(model.isSelected(profile.id) ? "Active" : "Use Profile") { model.select(profile.id) }
                                .disabled(model.isSelected(profile.id) || !model.canActivate(profile))
                        }
                        if profile.kind == .system { Text(model.simulation ? "macOS controls all fans in simulation." : model.statusText).foregroundStyle(.secondary) }
                        else if profile.kind == .maximum { Text("Uses each fan’s reported maximum RPM.").foregroundStyle(.secondary) }
                        else {
                            CurveSection(profile: profile, input: .chip, model: model)
                            if !model.simulation && model.capabilities.chipPolicy == .conservativeEnvelope {
                                Text("Chip uses the hottest reading in the reviewed chip-region envelope. CPU/GPU averages are estimates.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Divider()
                            Text("Chassis").font(.headline)
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
                            HStack {
                                Text("Minimum airflow")
                                Slider(value: Binding(get: { profile.floor }, set: { var next = profile; next.floor = $0.rounded(); model.update(next) }), in: 0...100, onEditingChanged: { editing in if editing { model.beginEditGroup() } else { model.endEditGroup() } })
                                Text("\(Int(profile.floor))%").monospacedDigit().frame(width: 40)
                            }
                            Text("0% uses each fan’s minimum RPM. Apple auto at idle can release control instead.").font(.caption).foregroundStyle(.secondary)
                            Toggle("Use Apple auto at idle", isOn: Binding(get: { profile.automaticAtIdle }, set: { var next = profile; next.automaticAtIdle = $0; model.update(next) }))
                        }
                        if !model.simulation && profile.kind != .system {
                            if let preview = model.preview {
                                Text(StatusPresentation.demand(preview, active: model.isSelected(profile.id)) + "\n" + StatusPresentation.breakdown(preview, floor: profile.floor))
                                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("profile.shadow-demand")
                            } else { Text("Preview unavailable: required readings are missing or unreliable.").font(.caption).foregroundStyle(.secondary) }
                            if let reason = model.eligibility(profile).reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                        }
                        if let error = model.draftError { Text(error).foregroundStyle(.red).font(.caption).accessibilityIdentifier("curve.validation-error") }
                        if model.unsavedChanges { Text("Changes not saved").font(.caption).foregroundStyle(.orange) }
                        if let error = model.saveError {
                            HStack { Text(error).font(.caption).foregroundStyle(.orange); Button("Retry") { model.save() } }
                        }
                        HStack {
                            Button("Undo") { model.editorHistory.undo() }.disabled(!model.canUndo).keyboardShortcut("z")
                            Button("Redo") { model.editorHistory.redo() }.disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
                            if profile.bundled && !profile.protected { Button("Reset to Default") { model.reset() } }
                            if !profile.bundled {
                                Button { model.move(-1) } label: { Image(systemName: "arrow.up") }
                                    .disabled(!model.canMove(-1)).help("Move profile up").accessibilityLabel("Move profile up")
                                Button { model.move(1) } label: { Image(systemName: "arrow.down") }
                                    .disabled(!model.canMove(1)).help("Move profile down").accessibilityLabel("Move profile down")
                            }
                            Spacer()
                        }
                        Divider()
                        SensorStatus(model: model)
                    }.padding(20)
                }.onAppear { name = profile.name }.onChange(of: profile.id) { _, _ in name = profile.name }.onChange(of: profile.name) { _, new in name = new }
            } else { ContentUnavailableView("Select a profile", systemImage: "fan") }
        }.frame(minWidth: 680, minHeight: 560)
        .disabled(model.savingCollection)
        .onChange(of: model.editorSelection) { _, _ in model.resetEditorHistory() }
        .toolbar { ToolbarItem { Text(model.simulation ? "Simulation" : "Live").foregroundStyle(.secondary).font(.caption) } }
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
    private func exportFile() {
        guard let profile = model.edited else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Fandy Profile.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do { try await Task.detached { try ProfileInterchange.encode([profile]).write(to: url, options: .atomic) }.value }
                catch { model.draftError = "Profile file could not be exported." }
            }
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
            CurveEditor(curve: curve, resetRevision: resetRevision, currentTemperature: model.curveTemperature(curve), onBegin: { model.beginEditGroup() }, onEnd: { model.endEditGroup() }, onChange: { commit($0) }).id(profile.id + input.rawValue).disabled(!curve.enabled).opacity(curve.enabled ? 1 : 0.5)
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
    private var primary: [SensorRole] { [.cpuAverage,.gpuAverage] + (model.capabilities.chipPolicy == .conservativeEnvelope && !model.simulation ? [.socPeak] : []) + [.trackpad,.airflowLeft,.airflowTop,.airflowRight] }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 5) {
                ForEach(primary) { role in GridRow { Text(model.simulation ? role.name : model.capabilities.sensorName(role)); Text(model.temperatureText(role)).monospacedDigit().foregroundStyle(.secondary) } }
                ForEach(model.snapshot?.fans ?? []) { fan in GridRow { Text("Fan \(fan.id + 1)"); Text("\(Int(fan.actualRPM.rounded())) RPM").monospacedDigit().foregroundStyle(.secondary) } }
            }
            DisclosureGroup("Details") {
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 5) {
                    ForEach([SensorRole.actuator,.charger,.powerSupply,.wireless]) { role in GridRow { Text(role.name); Text(model.temperatureText(role)).monospacedDigit() } }
                }.padding(.top, 5)
            }
            Text(model.statusText).font(.caption).foregroundStyle(.secondary)
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
    @State private var helperStatus = HelperManager.service.status
    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { loginStatus == .enabled }, set: { enabled in
                    do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; refreshRegistration() }
                    catch { model.draftError = "Login setting could not be changed." }
                }))
                Button("Export Diagnostics…") { exportDiagnostics() }
                if loginStatus == .requiresApproval {
                    Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Text("Login starts in System.").font(.caption).foregroundStyle(.secondary)
                if let error = model.draftError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Section("Backend") {
                Toggle("Simulation", isOn: Binding(get: { model.simulation }, set: { model.setSimulation($0) }))
                Text("Live mode reads sensors and runs the selected profile.").font(.caption).foregroundStyle(.secondary)
                if model.simulation {
                    Picker("Scenario", selection: $model.scenario) { ForEach(MockScenario.allCases) { Text($0.rawValue).tag($0) } }
                    Button("Simulate Helper Restart") { model.simulateRestart() }
                    Button("Simulate Sleep / Wake") { model.powerTransition() }
                }
            }
            Section("Fan Helper") {
                Text(model.helperRegistrationText)
                if helperStatus == .requiresApproval {
                    Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Text(model.capabilities.stage == .qualifiedControl ? "Eligible profiles control real fans. System restores Apple automatic control." : model.capabilities.canRestore ? "System and Max are available. Temperature profiles await their required inputs and activation test." : "Custom profiles await hardware verification.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Hardware verification") {
                    LabeledContent("Control inputs", value: "\(model.capabilities.verifiedRoles.intersection(model.capabilities.requiredControlRoles).count) / \(model.capabilities.requiredControlRoles.count) reviewed")
                    LabeledContent("Chip control", value: model.capabilities.chipPolicy == .conservativeEnvelope ? "Conservative envelope" : "CPU/GPU peaks")
                    LabeledContent("Automatic handback", value: model.capabilities.automaticRestoration == .verified ? "Verified" : "Pending")
                    LabeledContent("Manual control and recovery", value: model.capabilities.manualTransaction == .verified ? "Verified" : "Pending")
                }.accessibilityIdentifier("settings.hardwareVerification")
                Text("Startup and wake begin in System. No telemetry or networking.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding().frame(width: 440)
        .onAppear { refreshRegistration() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshRegistration() } }
    }
    private func refreshRegistration() { loginStatus = SMAppService.mainApp.status; helperStatus = HelperManager.service.status }
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
