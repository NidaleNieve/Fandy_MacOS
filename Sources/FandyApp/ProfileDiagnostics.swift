import Foundation
import FandyCore
import FandyHardware

/// Fixed native-model integration checks; never edits the user's profile store.
@MainActor enum ProfileDiagnostics {
    static func run(_ action: HelperDiagnosticAction) async -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FandyProfiles-\(UUID().uuidString)")
        let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false)
        do {
            guard model.capabilities.stage == .qualifiedControl else { throw ControlError.hardwareUnqualified }
            let reader = try SMCReader()
            for _ in 0..<5 { await model.tick() }
            var custom = BuiltInProfiles.systemPlus.duplicated()
            custom.id = "diagnostic-custom"; custom.name = "Diagnostic Custom"; custom.floor = 5; custom.automaticAtIdle = false
            model.profiles.append(custom)
            let ids = action == .profilesCalibration ? ["system", "system-plus", "cool-chassis"] : ["system-plus", "gaming", "cool-chassis", "school", custom.id]
            for id in ids {
                guard let profile = model.profiles.first(where: { $0.id == id }), model.canActivate(profile) else { throw ControlError.hardwareUnqualified }
                model.select(id)
                var acknowledged = false
                for _ in 0..<16 {
                    await model.tick()
                    if model.isSelected(id) { acknowledged = true; break }
                    if model.machine.selected.id != id { throw ControlError.invalidProfile(model.hardwareError ?? model.machine.fault ?? "Profile reverted to System.") }
                    try await Task.sleep(for: .milliseconds(500))
                }
                guard acknowledged else { throw ControlError.helperUnavailable }
                let started = ProcessInfo.processInfo.systemUptime
                var observedActuation = false
                repeat {
                    await model.tick()
                    guard model.isSelected(id), let snapshot = model.snapshot else { throw ControlError.restorationUnverified }
                    try snapshot.validate(now: ProcessInfo.processInfo.systemUptime, required: profile.requiredSensors(chipPolicy: model.capabilities.chipPolicy))
                    let fans = try reader.fans()
                    guard fans.allSatisfy({ model.machine.automaticAtIdle || profile.kind == .system ? $0.mode == .automatic : $0.mode == .manual }) else { throw ControlError.restorationUnverified }
                    observedActuation = observedActuation || fans.allSatisfy { $0.actualRPM >= $0.minimumRPM * 0.9 }
                    emit(["event": "profileSample", "profile": id, "percent": model.machine.percent,
                          "automaticAtIdle": model.machine.automaticAtIdle, "snapshot": try encoded(snapshot), "independentFans": try encoded(fans)])
                    try await Task.sleep(for: .seconds(1))
                } while ProcessInfo.processInfo.systemUptime - started < (action == .profilesCalibration ? 300 : 12)
                guard model.machine.automaticAtIdle || profile.kind == .system || observedActuation else { throw ControlError.invalidFan }
                if action == .profilesLive && id == custom.id {
                    var edited = custom; edited.floor = 10
                    model.update(edited)
                    for _ in 0..<5 {
                        await model.tick()
                        guard model.isSelected(custom.id), try reader.fans().allSatisfy({ $0.mode == .manual && $0.actualRPM >= $0.minimumRPM * 0.9 }) else { throw ControlError.restorationUnverified }
                        try await Task.sleep(for: .seconds(1))
                    }
                    emit(["event": "activeCurveEditPassed", "fans": try encoded(reader.fans())])
                    // Exercise the same draft boundary used by the graphical/numeric editor.
                    var draft = CurveDraft(edited.curves[0]); draft.select(edited.curves[0].points[0].id)
                    draft.temperatureText = "85"
                    guard draft.applyNumbers() == nil, model.profiles.first(where: { $0.id == edited.id }) == edited else {
                        throw ControlError.invalidCurve("An invalid editor draft replaced the active profile.")
                    }
                    draft.temperatureText = "45"; draft.percentText = "2.5"
                    guard let validated = draft.applyNumbers(locale: Locale(identifier: "en_US_POSIX")) else {
                        throw ControlError.invalidCurve("The corrected editor draft did not validate.")
                    }
                    edited.curves[0] = validated; model.update(edited); await model.tick()
                    guard model.isSelected(edited.id), try reader.fans().allSatisfy({ $0.mode == .manual }) else { throw ControlError.restorationUnverified }
                    emit(["event": "editorDraftBoundaryPassed"])
                }
                model.select("system")
                try await awaitSystem(model, reader: reader)
                guard try reader.fans().allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
                // Let the independently observed automatic state settle between finite checks.
                try await Task.sleep(for: .seconds(2))
            }
            if action == .profilesLive {
                // A UI state-machine reset must not reuse a stale hardware generation.
                for simulated in [true, false] {
                    model.setSimulation(simulated)
                    for _ in 0..<20 {
                        try await Task.sleep(for: .milliseconds(100)); await model.tick()
                        if model.simulation == simulated && model.machine.state == .system { break }
                    }
                    guard model.simulation == simulated, model.machine.state == .system else { throw ControlError.helperUnavailable }
                }
                model.select(custom.id)
                for _ in 0..<16 {
                    await model.tick()
                    if model.isSelected(custom.id) { break }
                    try await Task.sleep(for: .milliseconds(500))
                }
                guard !model.simulation, model.isSelected(custom.id), try reader.fans().allSatisfy({ $0.mode == .manual }) else { throw ControlError.helperUnavailable }
                emit(["event": "backendRoundTripPassed"])
                model.select("cool-chassis"); model.select("gaming"); model.select("school"); model.select("system")
                try await awaitSystem(model, reader: reader)
                guard model.isSelected("system"), try reader.fans().allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
            }
            await model.prepareForTermination()
            guard model.canTerminate, model.machine.state == .system, try reader.fans().allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
            emit(["event": "profilesPassed", "action": action.rawValue, "profiles": ids])
            return 0
        } catch {
            await model.prepareForTermination()
            emit(["event": "profilesFailed", "error": error.localizedDescription])
            return 1
        }
    }
    private static func awaitSystem(_ model: AppModel, reader: SMCReader) async throws {
        // Keep observation traffic within the production request budget. Rapid UI
        // selection is intentional; a zero-delay status flood is a different test.
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(500))
            await model.tick()
            if model.isSelected("system"), try reader.fans().allSatisfy({ $0.mode == .automatic }) { return }
        }
        throw ControlError.restorationUnverified
    }
    private static func encoded<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
    private static func emit(_ report: [String: Any]) {
        var report = report; report["timestamp"] = ISO8601DateFormatter().string(from: Date())
        guard var data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
        data.append(10); FileHandle.standardOutput.write(data)
    }
}
