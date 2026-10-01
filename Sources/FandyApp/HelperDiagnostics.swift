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
            case .register: try HelperManager.installObservation()
            case .unregister: try await HelperManager.uninstallObservation(client: client)
            case .status, .check: break
            case .registerRestoration:
                guard [.restorationQualification, .recoveryQualification].contains(SensorRegistry.capabilities.stage),
                      SensorRegistry.capabilities.canRestore, !SensorRegistry.capabilities.canControl else { throw ControlError.unauthorized }
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
                if action == .check { report["checks"] = try await client.checkObservationProtocol() }
                if action == .checkRestorationProtocol { report["checks"] = try await client.checkRestorationProtocol() }
                let status = try await client.status()
                guard !status.manualQualified else { throw ControlError.unauthorized }
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
            if (action == .check || action == .checkRestorationProtocol) && state != .enabled { return 2 }
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
    private static func requireRestorationHelper(_ client: FanXPCClient) async throws {
        let status = try await client.status()
        guard [.restorationQualification, .recoveryQualification].contains(SensorRegistry.capabilities.stage),
              !status.observationOnly, !status.manualQualified,
              [.restorationQualification, .recoveryQualification].contains(status.capabilities?.stage ?? .observation),
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
