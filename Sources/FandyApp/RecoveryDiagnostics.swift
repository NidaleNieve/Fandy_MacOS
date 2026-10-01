import Foundation
import FandyCore
import FandyHardware

/// Fixed signed-app diagnostics. No caller-selected RPM, fan key, duration or trust policy.
@MainActor enum RecoveryDiagnostics {
    static func run(_ action: HelperDiagnosticAction, client: FanXPCClient) async -> Int32 {
        do {
            let health = try await client.status()
            guard SensorRegistry.capabilities.canQualifyRecovery, !health.manualQualified,
                  health.capabilities?.canQualifyRecovery == true, health.automaticVerified else { throw ControlError.hardwareUnqualified }
            if let blocker = health.recoveryBlocker { throw ControlError.invalidProfile(blocker) }
            let reader = try SMCReader()
            emit(["event": "baseline", "fans": try encoded(reader.fans())])
            let trial = try await client.recovery(RecoveryTrialRequest(action == .recoveryInitial ? .initial : .recovery))
            emit(["event": "active", "pid": ProcessInfo.processInfo.processIdentifier, "trial": try encoded(trial), "fans": try encoded(reader.fans())])
            var heartbeatAt = ProcessInfo.processInfo.systemUptime + 1
            var disconnected = false
            let until = trial.deadline + 3
            repeat {
                try await Task.sleep(for: .milliseconds(250))
                let now = ProcessInfo.processInfo.systemUptime
                let fans = try reader.fans()
                emit(["event": "observation", "elapsed": now - trial.startedAt, "fans": try encoded(fans)])
                if fans.allSatisfy({ $0.mode == .automatic }) {
                    let final = try await client.status()
                    guard final.automaticVerified, let recovery = final.recovery, !recovery.active,
                          recovery.id == trial.id, recovery.restoration?.verified == true,
                          recovery.restoration?.fans.allSatisfy(\.releasedManual) == true else { throw ControlError.restorationUnverified }
                    // Status and independent mode reads, rather than RPM, prove handback.
                    emit(["event": "result", "passed": true, "trial": try encoded(recovery), "fans": try encoded(reader.fans())])
                    return 0
                }
                guard fans.allSatisfy({ $0.mode == .manual }) else { throw ControlError.restorationUnverified }
                if action == .recoveryDisconnect && !disconnected && now - trial.startedAt >= 1 {
                    client.disconnectForRecoveryTest(); disconnected = true
                    emit(["event": "disconnected", "elapsed": now - trial.startedAt])
                }
                if (action == .recoveryDeadline || action == .recoveryHold) && now >= heartbeatAt && now < trial.deadline {
                    _ = try await client.recovery(RecoveryTrialRequest(.heartbeat, sessionID: trial.id))
                    heartbeatAt = now + 1
                    emit(["event": "heartbeat", "elapsed": now - trial.startedAt])
                }
            } while ProcessInfo.processInfo.systemUptime < until
            throw ControlError.restorationUnverified
        } catch {
            do { try await client.restoreAutomatic() }
            catch { emit(["event": "restoreFailure", "error": error.localizedDescription]) }
            if let final = try? await client.status(), let recovery = final.recovery,
               let encoded = try? encoded(recovery) { emit(["event": "failedTrial", "trial": encoded]) }
            emit(["event": "failure", "action": action.rawValue, "error": error.localizedDescription])
            return 1
        }
    }
    private static func encoded<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
    private static func emit(_ value: [String: Any]) {
        var value = value; value["timestamp"] = ISO8601DateFormatter().string(from: Date())
        if var data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            data.append(10); FileHandle.standardOutput.write(data)
        }
    }
}
