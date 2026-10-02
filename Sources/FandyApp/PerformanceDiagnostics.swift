import Foundation
import FandyCore
import FandyHardware

struct LatencySummary: Codable, Equatable {
    let samples: Int
    let medianMilliseconds: Double
    let p95Milliseconds: Double
    let maximumMilliseconds: Double
    init(seconds: [Double]) throws {
        guard !seconds.isEmpty, seconds.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw ControlError.invalidNumber }
        let values = seconds.sorted().map { $0 * 1000 }
        samples = values.count
        medianMilliseconds = values[(values.count - 1) / 2]
        p95Milliseconds = values[max(0, Int(ceil(Double(values.count) * 0.95)) - 1)]
        maximumMilliseconds = values.last!
    }
}

/// Read-only, paced performance measurements. No stimulus, profile change or lease request.
@MainActor enum PerformanceDiagnostics {
    static func run() async -> Int32 {
        do {
            let reader = try HardwareSnapshotReader(), client = FanXPCClient()
            var acquisition: [Double] = [], rpc: [Double] = [], evaluation: [Double] = []
            for _ in 0..<20 {
                var started = ProcessInfo.processInfo.systemUptime
                let snapshot = try reader.snapshot()
                acquisition.append(ProcessInfo.processInfo.systemUptime - started)
                try snapshot.validate(now: ProcessInfo.processInfo.systemUptime, required: SensorRegistry.capabilities.chipPolicy.required.union(SensorRole.comfort))
                guard snapshot.fans.allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
                started = ProcessInfo.processInfo.systemUptime
                let status = try await client.status()
                rpc.append(ProcessInfo.processInfo.systemUptime - started)
                guard status.automaticVerified, status.snapshot?.fans.allSatisfy({ $0.mode == .automatic }) == true else { throw ControlError.restorationUnverified }
                // Ten normal evaluations per sample amortize the clock's resolution.
                started = ProcessInfo.processInfo.systemUptime
                for _ in 0..<10 {
                    _ = try ProfileEngine().evaluate(BuiltInProfiles.coolChassis, snapshot: snapshot,
                        now: ProcessInfo.processInfo.systemUptime, chipPolicy: SensorRegistry.capabilities.chipPolicy)
                }
                evaluation.append((ProcessInfo.processInfo.systemUptime - started) / 10)
                try await Task.sleep(for: .seconds(1))
            }
            let sensor = try LatencySummary(seconds: acquisition), helper = try LatencySummary(seconds: rpc), engine = try LatencySummary(seconds: evaluation)
            let passed = sensor.p95Milliseconds < 100 && helper.p95Milliseconds < 250 && engine.p95Milliseconds < 10
            struct Report: Encodable { let performanceCheck: String; let sensorAcquisition: LatencySummary; let helperStatus: LatencySummary; let profileEvaluation: LatencySummary }
            var bytes = try JSONEncoder().encode(Report(performanceCheck: passed ? "passed" : "budgetExceeded", sensorAcquisition: sensor, helperStatus: helper, profileEvaluation: engine)); bytes.append(10)
            FileHandle.standardOutput.write(bytes)
            return passed ? 0 : 1
        } catch {
            var bytes = (try? JSONEncoder().encode(["performanceCheck": "failed", "error": error.localizedDescription])) ?? Data(); bytes.append(10)
            FileHandle.standardOutput.write(bytes); return 1
        }
    }
}
