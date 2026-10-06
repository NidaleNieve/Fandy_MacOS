import Foundation
import AppKit
import FandyCore
import FandyHardware

/// Real native power notifications; never simulates a sleep event or requests a power change.
@MainActor enum SleepDiagnostics {
    @MainActor private final class Observation {
        var slept = false
        var woke = false
        func sleep() { slept = true }
        func wake() { if slept { woke = true } }
    }
    static func run() async -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FandySleep-\(UUID().uuidString)")
        let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false)
        let center = NSWorkspace.shared.notificationCenter, observation = Observation()
        let sleep = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in observation.sleep(); emit(["event": "nativeWillSleep"]) }
        }
        let wake = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in observation.wake(); emit(["event": "nativeDidWake"]) }
        }
        defer { center.removeObserver(sleep); center.removeObserver(wake); model.stop(); try? FileManager.default.removeItem(at: root) }
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
            model.observePower()
            emit(["event": "sleepReady", "profile": "cool-chassis", "modes": try reader.fans().map { $0.mode.rawValue }])
            let deadline = ContinuousClock.now.advanced(by: .seconds(90))
            while !observation.woke && ContinuousClock.now < deadline {
                if model.powerLifecycle == .awake { await model.tick() }
                try await Task.sleep(for: .seconds(1))
            }
            guard observation.slept, observation.woke else { throw ControlError.invalidProfile("No complete native sleep/wake was observed within 90 seconds.") }
            for _ in 0..<10 {
                await model.tick()
                if model.isSelected("cool-chassis"), model.powerLifecycle == .awake { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            guard model.isSelected("cool-chassis"), model.powerLifecycle == .awake else { throw ControlError.restorationUnverified }
            emit(["event": "sleepWakeResumed", "state": model.machine.state.rawValue, "modes": try reader.fans().map { $0.mode.rawValue }])
            await model.prepareForTermination()
            guard try reader.fans().allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
            emit(["event": "sleepWakePassed", "finalModes": try reader.fans().map { $0.mode.rawValue }]); return 0
        } catch {
            await model.prepareForTermination()
            emit(["event": "sleepWakeFailed", "error": error.localizedDescription]); return 1
        }
    }
    private static func emit(_ report: [String: Any]) {
        var report = report; report["timestamp"] = ISO8601DateFormatter().string(from: Date())
        guard var bytes = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
        bytes.append(10); FileHandle.standardOutput.write(bytes)
    }
}
