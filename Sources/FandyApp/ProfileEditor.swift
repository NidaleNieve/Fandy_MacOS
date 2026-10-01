import SwiftUI
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
                Button { model.create() } label: { Image(systemName: "plus") }.help("Create profile")
                Button { model.duplicate() } label: { Image(systemName: "square.on.square") }.help("Duplicate profile")
                Button { model.delete() } label: { Image(systemName: "minus") }.disabled(model.edited?.bundled != false).help("Delete profile")
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
                            Button("Use Profile") { model.select(profile.id) }.disabled(!model.canActivate(profile))
                        }
                        if profile.kind == .system { Text(model.simulation ? "macOS controls all fans in simulation." : model.statusText).foregroundStyle(.secondary) }
                        else if profile.kind == .maximum { Text("Uses each fan’s reported maximum RPM.").foregroundStyle(.secondary) }
                        else {
                            CurveSection(profile: profile, input: .chip, model: model)
                            Divider()
                            Text("Chassis").font(.headline)
                            Picker("Sensor", selection: $model.curveInput) {
                                Text("Trackpad").tag(CurveInput.trackpad)
                                Text("Actuator").tag(CurveInput.actuator)
                                Text("Airflow").tag(CurveInput.airflow)
                            }.pickerStyle(.segmented).onAppear { if model.curveInput == .chip { model.curveInput = .trackpad } }
                            CurveSection(profile: profile, input: model.curveInput == .chip ? .trackpad : model.curveInput, model: model)
                            HStack {
                                Text("Minimum airflow")
                                Slider(value: Binding(get: { profile.floor }, set: { var next = profile; next.floor = $0.rounded(); model.update(next) }), in: 0...100)
                                Text("\(Int(profile.floor))%").monospacedDigit().frame(width: 40)
                            }
                            Toggle("Use Apple auto at idle", isOn: Binding(get: { profile.automaticAtIdle }, set: { var next = profile; next.automaticAtIdle = $0; model.update(next) }))
                        }
                        if !model.simulation && profile.kind != .system {
                            if let preview = model.preview {
                                Text("Preview: \(Int(preview.percent.rounded()))% · \(preview.usesCandidates ? "candidate sensors" : "verified sensors") · no fan commands")
                                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("profile.shadow-demand")
                            } else { Text("Preview unavailable: required readings are missing or unreliable.").font(.caption).foregroundStyle(.secondary) }
                            if let reason = model.eligibility(profile).reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                        }
                        if let error = model.draftError { Text(error).foregroundStyle(.red).font(.caption).accessibilityIdentifier("curve.validation-error") }
                        HStack {
                            if profile.bundled && !profile.protected { Button("Reset to Default") { model.reset() } }
                            if !profile.bundled { Button { model.move(-1) } label: { Image(systemName: "arrow.up") }; Button { model.move(1) } label: { Image(systemName: "arrow.down") } }
                            Spacer()
                        }
                        Divider()
                        SensorStatus(model: model)
                    }.padding(20)
                }.onAppear { name = profile.name }.onChange(of: profile.id) { _, _ in name = profile.name }.onChange(of: profile.name) { _, new in name = new }
            } else { ContentUnavailableView("Select a profile", systemImage: "fan") }
        }.frame(minWidth: 680, minHeight: 560)
        .toolbar { ToolbarItem { Text(model.simulation ? "Simulation" : "Hardware Monitoring").foregroundStyle(.secondary).font(.caption) } }
    }
}
struct CurveSection: View {
    let profile: Profile
    let input: CurveInput
    @Bindable var model: AppModel
    var curve: FanCurve { profile.curves.first { $0.input == input } ?? FanCurve(input, input == .chip ? [(45,0),(85,100)] : input == .airflow ? [(33,0),(60,100)] : [(27,0),(42,100)], enabled: false) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(input.label, isOn: Binding(get: { curve.enabled }, set: { var next = curve; next.enabled = $0; commit(next) }))
                Spacer()
                Button("Reset Curve") { resetCurve() }.font(.caption)
            }
            CurveEditor(curve: curve, onChange: commit).id(profile.id + input.rawValue).disabled(!curve.enabled).opacity(curve.enabled ? 1 : 0.5)
        }
    }
    func resetCurve() {
        let original = BuiltInProfiles.all.first { $0.id == profile.id }
        var defaults = original?.curves.first { $0.input == input } ?? [BuiltInProfiles.chip, BuiltInProfiles.trackpad, BuiltInProfiles.actuator, BuiltInProfiles.airflow].first { $0.input == input }!
        defaults.enabled = curve.enabled; commit(defaults)
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
    private let primary: [SensorRole] = [.cpuAverage,.gpuAverage,.trackpad,.airflowLeft,.airflowTop,.airflowRight]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 5) {
                ForEach(primary) { role in GridRow { Text(role.name); Text(value(role)).monospacedDigit().foregroundStyle(.secondary) } }
                ForEach(model.snapshot?.fans ?? []) { fan in GridRow { Text("Fan \(fan.id + 1)"); Text("\(Int(fan.actualRPM.rounded())) RPM").monospacedDigit().foregroundStyle(.secondary) } }
            }
            DisclosureGroup("Details") {
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 5) {
                    ForEach([SensorRole.actuator,.charger,.powerSupply,.wireless]) { role in GridRow { Text(role.name); Text(value(role)).monospacedDigit() } }
                }.padding(.top, 5)
            }
            Text(model.statusText).font(.caption).foregroundStyle(.secondary)
            if let error = model.hardwareError ?? model.machine.fault ?? model.issues.first { Text(error).font(.caption).foregroundStyle(.orange) }
        }
    }
    func value(_ role: SensorRole) -> String {
        guard let reading = model.snapshot?.sensors.first(where: { $0.role == role }), let value = reading.celsius, value.isFinite else { return "Unavailable" }
        return String(format: "%.1f°C%@", value, reading.health == .unverified ? " · candidate" : reading.health == .valid ? "" : " · unreliable")
    }
}
struct SettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Section("Backend") {
                Toggle("Simulation", isOn: Binding(get: { model.simulation }, set: model.setSimulation))
                Text("Monitoring uses real readings. Curve previews do not command the fans.").font(.caption).foregroundStyle(.secondary)
                if model.simulation {
                    Picker("Scenario", selection: $model.scenario) { ForEach(MockScenario.allCases) { Text($0.rawValue).tag($0) } }
                    Button("Simulate Helper Restart") { model.simulateRestart() }
                    Button("Simulate Sleep / Wake") { model.powerTransition() }
                }
            }
            Section("Fan Helper") {
                Text(model.helperRegistrationText)
                if HelperManager.service.status == .requiresApproval {
                    Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Text(model.capabilities.canRestore ? "System can restore Apple automatic control. Custom profiles await verification." : "Custom profiles await hardware verification.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Hardware verification") {
                    LabeledContent("Sensor roles", value: "\(model.capabilities.verifiedRoles.intersection(HardwareCapabilities.requiredRoles).count) / \(HardwareCapabilities.requiredRoles.count) verified")
                    LabeledContent("Automatic handback", value: model.capabilities.automaticRestoration == .verified ? "Verified" : "Pending")
                    LabeledContent("Manual control and recovery", value: model.capabilities.manualTransaction == .verified ? "Verified" : "Pending")
                }.accessibilityIdentifier("settings.hardwareVerification")
                Text("Startup and wake begin in System. No telemetry or networking.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding().frame(width: 440)
    }
}
