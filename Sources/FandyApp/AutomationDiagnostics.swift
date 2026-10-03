import Foundation
import AppKit
import FandyCore
import FandyHardware

/// Fixed, bounded real-controller check. No user-supplied profile, RPM, PID or duration.
@MainActor enum AutomationDiagnostics {
    static func run() async -> Int32 {
        let client = FanXPCClient()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FandyAutomation-\(UUID().uuidString)")
        let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false, client: client)
        defer { try? FileManager.default.removeItem(at: root) }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep"); process.arguments = ["12"]
        var timerPassed = false, processPassed = false
        do {
            try await client.restoreAutomatic()
            await model.tick()
            guard model.ownership == .appleObserved, model.helperHealth == .controlReady,
                  let snapshot = model.snapshot, try snapshot.value(.socPeak, now: ProcessInfo.processInfo.systemUptime) < 75 else { throw ControlError.invalidSnapshot }
            model.select("cool-chassis")
            for _ in 0..<8 {
                await model.tick(); if model.isSelected("cool-chassis") { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard model.isSelected("cool-chassis") else { throw ControlError.helperUnavailable }
            model.activateFor(seconds: 3)
            for _ in 0..<10 {
                await model.tick(); try await Task.sleep(for: .milliseconds(500))
                if model.manualIntent == nil && model.machine.state == .system { break }
            }
            let timed = try await client.status()
            timerPassed = model.manualIntent == nil && timed.automaticVerified && timed.snapshot?.fans.allSatisfy { $0.mode == .automatic } == true
            guard timerPassed else { throw ControlError.restorationUnverified }
            try process.run()
            guard let instance = ProcessCatalog.list(includeHelpers: true).first(where: { $0.pid == process.processIdentifier }) else { throw ControlError.staleSession }
            model.select("cool-chassis"); model.activateWhile(instance)
            for _ in 0..<8 {
                await model.tick(); if model.isSelected("cool-chassis") { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard model.isSelected("cool-chassis") else { throw ControlError.helperUnavailable }
            process.terminate()
            for _ in 0..<10 {
                await model.tick(); try await Task.sleep(for: .milliseconds(500))
                if model.manualIntent == nil && model.machine.state == .system { break }
            }
            let observed = try await client.status()
            processPassed = model.manualIntent == nil && observed.automaticVerified && observed.snapshot?.fans.allSatisfy { $0.mode == .automatic } == true
            await model.prepareForTermination()
            print("{\"automationCheck\":\"\(timerPassed && processPassed ? "passed" : "failed")\",\"timerExpiry\":\(timerPassed),\"processExit\":\(processPassed),\"fanModes\":\(observed.snapshot?.fans.map { $0.mode.rawValue } ?? [])}")
            return timerPassed && processPassed ? 0 : 1
        } catch {
            if process.isRunning { process.terminate() }
            await model.prepareForTermination(); try? await client.restoreAutomatic()
            print("{\"automationCheck\":\"failed\",\"timerExpiry\":\(timerPassed),\"processExit\":\(processPassed)}")
            return 1
        }
    }
}
