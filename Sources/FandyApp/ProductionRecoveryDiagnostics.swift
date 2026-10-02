import Foundation
import FandyCore
import FandyHardware

/// Fixed modest production recovery tests, independent of qualification authority.
@MainActor enum ProductionRecoveryDiagnostics {
    static func run(_ action: HelperDiagnosticAction) async -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FandyRecovery-\(UUID().uuidString)")
        let client = FanXPCClient()
        let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false, client: client)
        defer { model.stop(); try? FileManager.default.removeItem(at: root) }
        do {
            guard model.capabilities.stage == .qualifiedControl else { throw ControlError.hardwareUnqualified }
            let reader = try SMCReader()
            for _ in 0..<5 { await model.tick() }
            model.select("cool-chassis")
            for _ in 0..<15 {
                await model.tick()
                if model.isSelected("cool-chassis"), try reader.fans().allSatisfy({ $0.mode == .manual && $0.actualRPM >= $0.minimumRPM * 0.9 }) { break }
                try await Task.sleep(for: .seconds(1))
            }
            guard model.isSelected("cool-chassis"), try reader.fans().allSatisfy({ $0.mode == .manual && $0.actualRPM >= $0.minimumRPM * 0.9 }) else { throw ControlError.invalidFan }
            let began = ContinuousClock.now
            emit(["event": "recoveryReady", "action": action.rawValue, "pid": ProcessInfo.processInfo.processIdentifier,
                  "modes": try reader.fans().map { $0.mode.rawValue }])
            if action == .productionHold {
                // A fixed 30s outer bound if the external SIGKILL is never delivered.
                while ContinuousClock.now < began.advanced(by: .seconds(30)) {
                    await model.tick(); try await Task.sleep(for: .seconds(1))
                }
                await model.prepareForTermination()
                throw ControlError.invalidProfile("The external process-kill test was not performed within 30 seconds.")
            }
            if action == .productionDisconnect { client.disconnectForRecoveryTest() }
            if action == .productionQuit { await model.prepareForTermination() }
            let timeout = action == .productionHeartbeat ? 14 : 4
            while ContinuousClock.now < began.advanced(by: .seconds(timeout)) {
                let fans = try reader.fans()
                if fans.allSatisfy({ $0.mode == .automatic }) {
                    let elapsed = began.duration(to: .now).components
                    let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                    let status = try await client.status()
                    guard status.automaticVerified, status.restoration?.fans.allSatisfy(\.releasedManual) == true else { throw ControlError.restorationUnverified }
                    emit(["event": "recoveryPassed", "action": action.rawValue, "seconds": seconds,
                          "modes": fans.map { $0.mode.rawValue }])
                    await model.prepareForTermination(); return 0
                }
                try await Task.sleep(for: .milliseconds(250))
            }
            throw ControlError.restorationUnverified
        } catch {
            await model.prepareForTermination()
            emit(["event": "recoveryFailed", "action": action.rawValue, "error": error.localizedDescription]); return 1
        }
    }
    private static func emit(_ report: [String: Any]) {
        var report = report; report["timestamp"] = ISO8601DateFormatter().string(from: Date())
        guard var bytes = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
        bytes.append(10); FileHandle.standardOutput.write(bytes)
    }
}
