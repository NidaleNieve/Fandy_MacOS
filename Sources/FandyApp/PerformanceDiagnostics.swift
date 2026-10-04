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
    /// Fixed thirty-minute ordinary-use session; no caller duration, target or stimulus.
    static func runLong(comfort: Bool) async -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FandyPerformance-\(UUID().uuidString)")
        let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false)
        defer { model.stop(); try? FileManager.default.removeItem(at: root) }
        do {
            model.observePower()
            let powerGeneration = model.powerTransitionCount
            let reader = try HardwareSnapshotReader()
            guard try reader.snapshot().fans.allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
            for _ in 0..<5 { await model.tick() }
            if comfort {
                guard model.powerTransitionCount == powerGeneration else { throw ControlError.restorationUnverified }
                model.select("cool-chassis")
                for _ in 0..<15 { await model.tick(); if model.isSelected("cool-chassis") { break }; try await Task.sleep(for: .seconds(1)) }
                guard model.isSelected("cool-chassis") else { throw ControlError.helperUnavailable }
            }
            let started = ContinuousClock.now
            let deadline = started.advanced(by: .seconds(1800))
            var ticks: [Double] = []
            while ContinuousClock.now < deadline {
                let began = ProcessInfo.processInfo.systemUptime
                await model.tick()
                ticks.append(ProcessInfo.processInfo.systemUptime - began)
                guard model.powerTransitionCount == powerGeneration, model.hardwareError == nil, model.isSelected(comfort ? "cool-chassis" : "system"), let snapshot = model.snapshot else { throw ControlError.helperUnavailable }
                try snapshot.validate(now: ProcessInfo.processInfo.systemUptime, required: DeviceRegistry.current.capabilities.chipPolicy.required.union(SensorRole.comfort))
                if ticks.count % 30 == 0 {
                    let row: [String: Any] = ["event": "performanceSample", "session": comfort ? "comfort" : "system", "ticks": ticks.count,
                        "modes": snapshot.fans.map { $0.mode.rawValue }, "rpm": snapshot.fans.map { $0.actualRPM },
                        "tickMilliseconds": ticks.last! * 1000]
                    var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]); data.append(10); FileHandle.standardOutput.write(data)
                }
                try await Task.sleep(for: .seconds(1))
            }
            await model.prepareForTermination()
            guard try reader.snapshot().fans.allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
            struct Report: Encodable { let event: String; let session: String; let durationSeconds: Int; let tickLatency: LatencySummary }
            var data = try JSONEncoder().encode(Report(event: "longPerformancePassed", session: comfort ? "comfort" : "system", durationSeconds: 1800, tickLatency: LatencySummary(seconds: ticks)))
            data.append(10); FileHandle.standardOutput.write(data); return 0
        } catch {
            await model.prepareForTermination()
            FileHandle.standardError.write(Data("Long performance session failed; System restoration requested.\n".utf8)); return 1
        }
    }
    static func run() async -> Int32 {
        do {
            let reader = try HardwareSnapshotReader(), client = FanXPCClient()
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("FandyResponsiveness-\(UUID().uuidString)")
            let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false)
            defer { model.stop(); try? FileManager.default.removeItem(at: root) }
            var acquisition: [Double] = [], rpc: [Double] = [], evaluation: [Double] = []
            var tick: [Double] = [], mainActorLag: [Double] = []
            for _ in 0..<20 {
                var started = ProcessInfo.processInfo.systemUptime
                let snapshot = try reader.snapshot()
                acquisition.append(ProcessInfo.processInfo.systemUptime - started)
                try snapshot.validate(now: ProcessInfo.processInfo.systemUptime, required: DeviceRegistry.current.capabilities.chipPolicy.required.union(SensorRole.comfort))
                guard snapshot.fans.allSatisfy({ $0.mode == .automatic }) else { throw ControlError.restorationUnverified }
                started = ProcessInfo.processInfo.systemUptime
                let status = try await client.status()
                rpc.append(ProcessInfo.processInfo.systemUptime - started)
                guard status.automaticVerified, status.snapshot?.fans.allSatisfy({ $0.mode == .automatic }) == true else { throw ControlError.restorationUnverified }
                // Ten normal evaluations per sample amortize the clock's resolution.
                started = ProcessInfo.processInfo.systemUptime
                for _ in 0..<10 {
                    _ = try ProfileEngine().evaluate(BuiltInProfiles.coolChassis, snapshot: snapshot,
                        now: ProcessInfo.processInfo.systemUptime, chipPolicy: DeviceRegistry.current.capabilities.chipPolicy)
                }
                evaluation.append((ProcessInfo.processInfo.systemUptime - started) / 10)
                // Sample dispatch delay during the real asynchronous GUI-model polling
                // path. The synchronous read-only discovery measurement above is excluded.
                let probe = Task.detached { () -> [Double] in
                    var delays: [Double] = []
                    for _ in 0..<20 {
                        let submitted = ProcessInfo.processInfo.systemUptime
                        delays.append(await MainActor.run { ProcessInfo.processInfo.systemUptime - submitted })
                        try? await Task.sleep(for: .milliseconds(5))
                    }
                    return delays
                }
                started = ProcessInfo.processInfo.systemUptime
                await model.tick(); tick.append(ProcessInfo.processInfo.systemUptime - started)
                guard model.hardwareError == nil, model.machine.state == .system else { throw ControlError.invalidSnapshot }
                mainActorLag.append(contentsOf: await probe.value)
                try await Task.sleep(for: .seconds(1))
            }
            let sensor = try LatencySummary(seconds: acquisition), helper = try LatencySummary(seconds: rpc), engine = try LatencySummary(seconds: evaluation)
            let modelTick = try LatencySummary(seconds: tick), dispatch = try LatencySummary(seconds: mainActorLag)
            let passed = sensor.p95Milliseconds < 100 && helper.p95Milliseconds < 250 && engine.p95Milliseconds < 10 && dispatch.p95Milliseconds < 50
            struct Report: Encodable { let performanceCheck: String; let sensorAcquisition: LatencySummary; let helperStatus: LatencySummary; let profileEvaluation: LatencySummary; let monitoringTick: LatencySummary; let mainActorDispatch: LatencySummary }
            var bytes = try JSONEncoder().encode(Report(performanceCheck: passed ? "passed" : "budgetExceeded", sensorAcquisition: sensor, helperStatus: helper, profileEvaluation: engine, monitoringTick: modelTick, mainActorDispatch: dispatch)); bytes.append(10)
            FileHandle.standardOutput.write(bytes)
            return passed ? 0 : 1
        } catch {
            var bytes = (try? JSONEncoder().encode(["performanceCheck": "failed", "error": error.localizedDescription])) ?? Data(); bytes.append(10)
            FileHandle.standardOutput.write(bytes); return 1
        }
    }
}
