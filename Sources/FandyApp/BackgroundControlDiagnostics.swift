import Foundation
import FandyCore
import FandyHardware

/// Fixed, quiet background workloads with all normal sensor and helper checks.
/// No UI is opened; no caller can supply speed, duration or authority.
@MainActor enum BackgroundControlDiagnostics {
    nonisolated static func percent(changing: Bool, tick: Int) -> Double { changing && tick % 2 != 0 ? 4 : 3 }
    static func run(changing: Bool) async -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FandyBackground-\(UUID().uuidString)")
        let client = FanXPCClient()
        let model = AppModel(storeURL: root.appendingPathComponent("profiles.json"), autoStart: false, client: client,
            helperAvailable: { true }, helperRegistrationStatus: { .enabled })
        defer { model.stop(); try? FileManager.default.removeItem(at: root) }
        do {
            model.observePower()
            let generation = model.powerTransitionCount
            let reader = try HardwareSnapshotReader()
            guard try reader.snapshot().appleOwnershipObserved else { throw ControlError.restorationUnverified }
            for _ in 0..<6 { await model.tick(); try await Task.sleep(for: .seconds(1)) }
            guard generation == model.powerTransitionCount, model.hardwareError == nil,
                  model.activateCustomFanSpeed(percent: 3, seconds: changing ? 240 : 660) else { throw ControlError.helperUnavailable }
            // A warmup excludes admission, startup and initial fan inertia from
            // the steady-state window. The helper's own deadline stays bounded.
            for _ in 0..<12 { await model.tick(); try await Task.sleep(for: .seconds(1)) }
            let began = ContinuousClock.now
            let deadline = began.advanced(by: .seconds(changing ? 180 : 600))
            var ticks = 0
            while ContinuousClock.now < deadline {
                if changing { _ = model.updateCustomFanSpeed(percent: percent(changing: true, tick: ticks)) }
                await model.tick()
                guard model.powerTransitionCount == generation, model.hardwareError == nil,
                      model.machine.state == .customActive, let snapshot = model.snapshot,
                      snapshot.fans.allSatisfy({ $0.mode == .manual }) else { throw ControlError.helperUnavailable }
                try snapshot.validate(now: ProcessInfo.processInfo.systemUptime, required: model.capabilities.chipPolicy.required)
                guard try model.capabilities.chipPolicy.temperature(in: snapshot, now: ProcessInfo.processInfo.systemUptime) < MeasurementSafety.ceilingC else { throw ControlError.thermalPressure }
                struct Row: Encodable {
                    let elapsedSeconds: Double
                    let tick: Int
                    let demand: Double
                    let targetRPM: [Double?]
                    let actualRPM: [Double]
                    let modes: [Int]
                    let app: ProcessResourceSample
                    let helper: ProcessResourceSample?
                    let work: [BackgroundWorkSample]?
                }
                let elapsed = began.duration(to: .now).components
                let row = Row(elapsedSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
                    tick: ticks, demand: model.machine.percent, targetRPM: snapshot.fans.map(\.targetRPM),
                    actualRPM: snapshot.fans.map(\.actualRPM), modes: snapshot.fans.map { $0.mode.rawValue },
                    app: try ProcessResourceSample.capture(), helper: model.helperDiagnostic?.resources, work: model.helperDiagnostic?.work)
                try autoreleasepool {
                    var data = try JSONEncoder().encode(row); data.append(10); FileHandle.standardOutput.write(data)
                }
                ticks += 1
                try await Task.sleep(for: .seconds(1))
            }
            await model.prepareForTermination()
            guard try reader.snapshot().appleOwnershipObserved else { throw ControlError.restorationUnverified }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Background diagnostic: \(error); state=\(model.machine.state); powerChanges=\(model.powerTransitionCount); error=\(model.hardwareError ?? "none").\n".utf8))
            await model.prepareForTermination()
            FileHandle.standardError.write(Data("Background session stopped; automatic restoration requested.\n".utf8))
            return 1
        }
    }
}
