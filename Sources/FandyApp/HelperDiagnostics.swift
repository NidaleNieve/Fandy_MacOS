import Foundation
import ServiceManagement
import FandyCore
import FandyHardware

/// Fixed-purpose diagnostics in the genuinely signed GUI executable. No RPM/mode arguments.
enum HelperDiagnosticAction: String, CaseIterable {
    case register = "--helper-observation-register"
    case status = "--helper-observation-status"
    case unregister = "--helper-observation-unregister"
    case check = "--helper-observation-check"
    case registerRestoration = "--helper-restoration-register"
    case statusRestoration = "--helper-restoration-status"
    case restore = "--helper-restore"
    case checkRestoration = "--helper-restoration-check"
    case checkRestorationProtocol = "--helper-restoration-protocol-check"
    case unregisterRestoration = "--helper-restoration-unregister"
    case recoveryInitial = "--helper-recovery-initial"
    case recoveryDeadline = "--helper-recovery-deadline"
    case recoveryHeartbeat = "--helper-recovery-heartbeat"
    case recoveryDisconnect = "--helper-recovery-disconnect"
    case recoveryHold = "--helper-recovery-hold"
    case curveCheck = "--profile-curve-check"
    case curveHeartbeat = "--profile-curve-heartbeat-check"
    case curveDisconnect = "--profile-curve-disconnect-check"
    case curveHold = "--profile-curve-hold-check"
    case curveSpinning = "--profile-curve-spinning-check"
    case curveQuit = "--profile-curve-quit-check"
    case productionHeartbeat = "--profiles-recovery-heartbeat"
    case productionDisconnect = "--profiles-recovery-disconnect"
    case productionQuit = "--profiles-recovery-quit"
    case productionHold = "--profiles-recovery-hold"
    case productionSecurity = "--helper-security-check"
    case performance = "--performance-check"
    case profilesSleep = "--profiles-sleep-check"
    case profilesLive = "--profiles-live-check"
    case profilesCalibration = "--profiles-calibration-check"
    case maximumCheck = "--profile-max-check"
    case maximumQuit = "--profile-max-quit-check"
    case maximumHeartbeat = "--profile-max-heartbeat-check"

    static func parse(_ arguments: [String]) throws -> Self? {
        let actions = allCases.filter { arguments.contains($0.rawValue) }
        guard actions.count <= 1, actions.allSatisfy({ action in arguments.filter { $0 == action.rawValue }.count == 1 }) else {
            throw ControlError.malformedMessage
        }
        if let action = actions.first {
            guard arguments.enumerated().allSatisfy({ index, value in
                value == action.rawValue || (index == 0 && !value.hasPrefix("--"))
            }) else { throw ControlError.malformedMessage }
        }
        return actions.first
    }
}

@MainActor enum HelperDiagnostics {
    static func run(_ action: HelperDiagnosticAction) async -> Int32 {
        let client = FanXPCClient()
        do {
            switch action {
            case .curveCheck, .curveHeartbeat, .curveDisconnect, .curveHold, .curveQuit: return await checkCurve(action)
            case .curveSpinning: return await checkSpinningCurve()
            case .productionHeartbeat, .productionDisconnect, .productionQuit, .productionHold: return await ProductionRecoveryDiagnostics.run(action)
            case .performance: return await PerformanceDiagnostics.run()
            case .profilesSleep: return await SleepDiagnostics.run()
            case .profilesLive, .profilesCalibration: return await ProfileDiagnostics.run(action)
            case .maximumCheck, .maximumQuit, .maximumHeartbeat: return await checkMaximum(action)
            case .register: try HelperManager.installObservation()
            case .unregister: try await HelperManager.uninstallObservation(client: client)
            case .status, .check, .productionSecurity: break
            case .registerRestoration:
                guard [.restorationQualification, .recoveryQualification, .maximumControl, .curveQualification, .qualifiedControl].contains(SensorRegistry.capabilities.stage),
                      SensorRegistry.capabilities.canRestore else { throw ControlError.unauthorized }
                try HelperManager.install()
            case .unregisterRestoration: try await HelperManager.uninstall(client: client)
            case .statusRestoration: break
            case .restore:
                try await requireRestorationHelper(client)
                try await client.restoreAutomatic()
            case .checkRestoration: return try await checkRestoration(client)
            case .checkRestorationProtocol:
                try await requireRestorationHelper(client)
            case .recoveryInitial, .recoveryDeadline, .recoveryHeartbeat, .recoveryDisconnect, .recoveryHold:
                return await RecoveryDiagnostics.run(action, client: client)
            }
            let state = HelperManager.service.status
            var report: [String: Any] = ["action": action.rawValue, "registration": name(state),
                "physicalWritesEnabled": SensorRegistry.capabilities.canRestore,
                "manualWritesEnabled": SensorRegistry.capabilities.canControl]
            report["recoveryTrialsEnabled"] = SensorRegistry.capabilities.canQualifyRecovery
            if state == .enabled {
                if action == .productionSecurity { report["checks"] = try await client.checkProductionProtocol() }
                if action == .check { report["checks"] = try await client.checkObservationProtocol() }
                if action == .checkRestorationProtocol { report["checks"] = try await client.checkRestorationProtocol() }
                let status = try await client.status()
                report["observationOnly"] = status.observationOnly
                report["physicalWritesEnabled"] = status.capabilities?.canRestore ?? false
                report["automaticObserved"] = status.automaticVerified
                if let snapshot = status.snapshot {
                    report["fans"] = snapshot.fans.map { ["id": $0.id, "mode": $0.mode.rawValue, "rpm": $0.actualRPM] as [String: Any] }
                    report["sensorCount"] = snapshot.sensors.count
                }
                if let fault = status.fault { report["fault"] = fault }
                report["helperStatus"] = try encoded(status)
            }
            emit(report)
            if (action == .check || action == .checkRestorationProtocol || action == .productionSecurity) && state != .enabled { return 2 }
            return state == .requiresApproval ? 2 : state == .notFound ? 1 : 0
        } catch {
            if (action == .register || action == .registerRestoration) && HelperManager.service.status == .requiresApproval {
                emit(["action": action.rawValue, "registration": "requiresApproval", "approvalRequired": true,
                      "physicalWritesEnabled": SensorRegistry.capabilities.canRestore])
                return 2
            }
            emit(["action": action.rawValue, "registration": name(HelperManager.service.status), "error": error.localizedDescription])
            return 1
        }
    }
    /// Fixed curve trial in the signed qualification build; the root lease owns its 15s deadline.
    /// No caller-provided keys, RPM, duration, profile or authority are accepted.
    private static func checkCurve(_ action: HelperDiagnosticAction) async -> Int32 {
        let client = FanXPCClient()
        var writeAdmitted = false
        do {
            guard SensorRegistry.capabilities.canQualifyCurves, HelperManager.installed else { throw ControlError.hardwareUnqualified }
            let reader = try SMCReader()
            // Distinct completed acquisitions; an artificial delay here can let a spinning
            // automatic baseline stop before the transaction we intend to qualify.
            for _ in 0..<5 { _ = try await client.status() }
            let status = try await client.status()
            guard status.capabilities?.canQualifyCurves == true, status.automaticVerified,
                  let snapshot = status.snapshot else { throw ControlError.restorationUnverified }
            let policy = SensorRegistry.capabilities.chipPolicy
            try snapshot.validate(now: ProcessInfo.processInfo.systemUptime, required: policy.required)
            let floors = try snapshot.fans.map { fan -> FanTarget in
                let rpm = max(fan.minimumRPM, fan.actualRPM) + 200
                guard rpm <= fan.maximumRPM else { throw ControlError.invalidFan }
                return FanTarget(fan.id, rpm)
            }
            let started = ProcessInfo.processInfo.systemUptime
            var activated = false, positiveRPM = false, disconnected = false
            while ProcessInfo.processInfo.systemUptime - started < 18 {
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                let fans = try reader.fans()
                if activated && fans.allSatisfy({ $0.mode == .automatic }) {
                    guard action != .curveCheck else { throw ControlError.restorationUnverified }
                    emit(["event": "curveRecovery", "elapsed": elapsed, "fans": try encoded(fans)])
                    try await client.restoreAutomatic()
                    return 0
                }
                if (action == .curveCheck || action == .curveQuit) && elapsed >= (action == .curveQuit ? 12 : 5) {
                    guard activated else { throw ControlError.restorationUnverified }
                    guard positiveRPM else { throw ControlError.invalidProfile("Fan spin-up was not observed within the bounded trial.") }
                    if action == .curveQuit {
                        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FandyCurveQuit-\(UUID().uuidString)")
                        let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false, client: client)
                        await model.prepareForTermination()
                        guard model.canTerminate, model.machine.state == .system else { throw ControlError.restorationUnverified }
                    } else { try await client.restoreAutomatic() }
                    let restored = try reader.fans()
                    guard restored.allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
                    emit(["event": "curveHandback", "elapsed": elapsed, "fans": try encoded(restored)])
                    return 0
                }
                let renew = !activated || action == .curveCheck || action == .curveQuit || (action == .curveHold && elapsed < 12)
                if renew {
                    let current = try await client.status()
                    guard let currentSnapshot = current.snapshot else { throw ControlError.invalidSnapshot }
                    let demand = try ProfileEngine().evaluate(BuiltInProfiles.systemPlus, snapshot: currentSnapshot, now: ProcessInfo.processInfo.systemUptime, chipPolicy: policy)
                    let targets = try currentSnapshot.fans.map { fan -> FanTarget in
                        guard let floor = floors.first(where: { $0.fanID == fan.id }) else { throw ControlError.invalidFan }
                        // A small upward-only target change also exercises repeated target acknowledgement.
                        let step = elapsed >= 2 ? 50.0 : 0.0
                        return FanTarget(fan.id, max(try fan.rpm(percent: demand.percent), min(fan.maximumRPM, floor.rpm + step)))
                    }
                    writeAdmitted = true
                    try await client.apply(targets, generation: 1, required: policy.required)
                    activated = true
                }
                let observed = try reader.fans()
                positiveRPM = positiveRPM || observed.allSatisfy { fan in
                    floors.first(where: { $0.fanID == fan.id }).map { fan.actualRPM >= $0.rpm - 150 } ?? false
                }
                emit(["event": "curveActive", "elapsed": elapsed, "fans": try encoded(observed)])
                if action == .curveDisconnect && activated && !disconnected {
                    client.disconnectForRecoveryTest(); disconnected = true
                }
                try await Task.sleep(for: .milliseconds(500))
            }
            throw ControlError.restorationUnverified
        } catch {
            var report: [String: Any] = ["event": "curveDiagnosticFailed", "error": error.localizedDescription]
            if writeAdmitted {
                do {
                    try await client.restoreAutomatic()
                    let fans = try SMCReader().fans()
                    report["automaticRestorationVerified"] = fans.allSatisfy { $0.mode == .automatic }
                    report["fans"] = try encoded(fans)
                } catch { report["restorationError"] = error.localizedDescription }
            }
            emit(report)
            return 1
        }
    }
    /// Same authenticated connection throughout, so disconnect cleanup cannot erase the
    /// spinning automatic baseline between release and the next bounded admission.
    private static func checkSpinningCurve() async -> Int32 {
        let client = FanXPCClient()
        do {
            guard SensorRegistry.capabilities.canQualifyCurves else { throw ControlError.hardwareUnqualified }
            let reader = try SMCReader()
            for _ in 0..<5 { _ = try await client.status() }
            for generation in 1...2 {
                let status = try await client.status()
                guard status.automaticVerified, let snapshot = status.snapshot else { throw ControlError.restorationUnverified }
                try snapshot.validate(now: ProcessInfo.processInfo.systemUptime, required: SensorRegistry.capabilities.chipPolicy.required)
                if generation == 2 {
                    guard snapshot.fans.allSatisfy({ $0.mode == .automatic && $0.actualRPM > 0 }) else { throw ControlError.invalidProfile("No spinning automatic baseline available.") }
                }
                emit(["event": "curveAdmissionBaseline", "generation": generation, "fans": try encoded(snapshot.fans)])
                let targets = try snapshot.fans.map { fan -> FanTarget in
                    let rpm = max(fan.minimumRPM, fan.actualRPM) + 200
                    guard rpm <= fan.maximumRPM else { throw ControlError.invalidFan }
                    return FanTarget(fan.id, rpm)
                }
                let started = ProcessInfo.processInfo.systemUptime
                var reached = false
                repeat {
                    try await client.apply(targets, generation: UInt64(generation), required: SensorRegistry.capabilities.chipPolicy.required)
                    let fans = try reader.fans()
                    guard fans.allSatisfy({ $0.mode == .manual }) else { throw ControlError.restorationUnverified }
                    reached = reached || fans.allSatisfy { fan in targets.contains { $0.fanID == fan.id && fan.actualRPM >= $0.rpm - 150 } }
                    emit(["event": "curveSpinningActive", "generation": generation, "fans": try encoded(fans)])
                    try await Task.sleep(for: .milliseconds(500))
                } while ProcessInfo.processInfo.systemUptime - started < (generation == 1 ? 8 : 12)
                guard reached else { throw ControlError.invalidProfile("Fan spin-up was not observed within the bounded trial.") }
                try await client.restoreAutomatic()
                guard try reader.fans().allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
            }
            emit(["event": "spinningCurvePassed"])
            return 0
        } catch {
            try? await client.restoreAutomatic()
            emit(["event": "spinningCurveFailed", "error": error.localizedDescription])
            return 1
        }
    }
    private static func checkMaximum(_ action: HelperDiagnosticAction) async -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FandyMaxCheck-\(UUID().uuidString)")
        let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false)
        do {
            guard model.capabilities.permits(BuiltInProfiles.maximum), HelperManager.installed else { throw ControlError.hardwareUnqualified }
            let reader = try SMCReader()
            for _ in 0..<5 { await model.tick(); try await Task.sleep(for: .milliseconds(250)) }
            guard model.ownership == .appleObserved, model.canActivate(BuiltInProfiles.maximum) else { throw ControlError.restorationUnverified }
            model.select("max")
            for _ in 0..<10 {
                await model.tick()
                if model.machine.state == .customActive { break }
                if model.machine.selected.kind == .system { throw ControlError.helperUnavailable }
                try await Task.sleep(for: .seconds(1))
            }
            guard model.machine.state == .customActive, model.isSelected("max") else { throw ControlError.helperUnavailable }
            var reachedMaximum = false
            for _ in 0..<8 {
                let fans = try reader.fans()
                guard fans.allSatisfy({ $0.mode == .manual && $0.targetRPM == $0.maximumRPM }) else { throw ControlError.restorationUnverified }
                reachedMaximum = reachedMaximum || fans.allSatisfy { $0.actualRPM >= $0.maximumRPM * 0.9 }
                emit(["event": "maximumActive", "fans": try encoded(fans), "state": model.machine.state.rawValue])
                try await Task.sleep(for: .seconds(1))
                if action != .maximumHeartbeat { await model.tick() }
            }
            guard reachedMaximum else { throw ControlError.invalidFan }
            if action == .maximumHeartbeat {
                var restored = false
                for _ in 0..<24 {
                    if try reader.fans().allSatisfy({ $0.mode == .automatic }) { restored = true; break }
                    try await Task.sleep(for: .milliseconds(250))
                }
                let status = try await FanXPCClient().status()
                guard restored, status.automaticVerified, status.restoration?.fans.allSatisfy(\.releasedManual) == true else { throw ControlError.restorationUnverified }
                emit(["event": "heartbeatExpired", "restoration": try encoded(status.restoration)])
                await model.prepareForTermination()
            } else if action == .maximumQuit {
                await model.prepareForTermination()
            } else { model.select("system") }
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(100)); await model.tick()
                if model.machine.state == .system { break }
            }
            guard model.machine.state == .system, (action == .maximumCheck ? model.isSelected("system") : model.canTerminate),
                  try reader.fans().allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
            await model.prepareForTermination()
            emit(["event": "result", "productionMaximum": "passed", "action": action.rawValue, "fans": try encoded(reader.fans())])
            return 0
        } catch {
            await model.prepareForTermination()
            emit(["event": "failure", "productionMaximum": "failed", "error": error.localizedDescription])
            return 1
        }
    }
    private static func requireRestorationHelper(_ client: FanXPCClient) async throws {
        let status = try await client.status()
        guard [.restorationQualification, .recoveryQualification, .maximumControl, .curveQualification, .qualifiedControl].contains(SensorRegistry.capabilities.stage),
              !status.observationOnly,
              [.restorationQualification, .recoveryQualification, .maximumControl, .curveQualification, .qualifiedControl].contains(status.capabilities?.stage ?? .observation),
              status.capabilities?.forMachine(HardwareSnapshotReader.machineModel()).canRestore == true else { throw ControlError.unauthorized }
    }
    private static func checkRestoration(_ client: FanXPCClient) async throws -> Int32 {
        try await requireRestorationHelper(client)
        let reader = try SMCReader()
        let initial = try await client.status()
        emit(["event": "initial", "helperStatus": try encoded(initial), "independentFans": try encoded(reader.fans())])
        // The startup report retains a real pre-write mode even if startup already released it.
        var transition = initial.startupRestoration?.fans.allSatisfy(\.releasedManual) == true
        for attempt in 1...3 {
            try await client.restoreAutomatic()
            let status = try await client.status()
            guard status.automaticVerified, status.restoration?.verified == true else { throw ControlError.restorationUnverified }
            transition = transition || status.restoration?.fans.allSatisfy(\.releasedManual) == true
            try verifyIndependentModes(reader)
            emit(["event": "idempotence", "attempt": attempt, "helperStatus": try encoded(status), "independentFans": try encoded(reader.fans())])
            try await Task.sleep(for: .seconds(1))
        }
        let started = ProcessInfo.processInfo.systemUptime
        repeat {
            let status = try await client.status()
            guard status.automaticVerified, !status.manualQualified, status.fault == nil else { throw ControlError.restorationUnverified }
            try verifyIndependentModes(reader)
            emit(["event": "observation", "elapsed": ProcessInfo.processInfo.systemUptime - started, "independentFans": try encoded(reader.fans())])
            try await Task.sleep(for: .seconds(1))
        } while ProcessInfo.processInfo.systemUptime - started < 60
        try verifyIndependentModes(reader)
        emit(["event": "result", "automaticStableSeconds": 60, "idempotentRequests": 3,
              "manualToAutomaticProven": transition, "gatePassed": transition])
        return transition ? 0 : 2
    }
    private static func verifyIndependentModes(_ reader: SMCReader) throws {
        for id in SensorRegistry.observedFanIDs {
            let mode = try reader.read("F\(id)md")
            guard mode.type == "ui8 ", mode.size == 1, mode.attributes == 208, mode.bytes == [0] else { throw ControlError.restorationUnverified }
        }
    }
    private static func encoded<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
    static func name(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown"
        }
    }
    private static func emit(_ report: [String: Any]) {
        var report = report; report["timestamp"] = ISO8601DateFormatter().string(from: Date())
        if var data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            data.append(10); FileHandle.standardOutput.write(data)
        }
    }
}
