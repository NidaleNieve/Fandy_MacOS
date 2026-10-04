import Foundation
import Observation
import FandyCore
import FandyHardware

struct MenuSensor: Identifiable, Sendable {
    let id: String
    let name: String
    let keys: [String]
    let role: SensorRole?
    let estimate: Bool
    var isRaw: Bool { id.hasPrefix("key:") || id.hasPrefix("hid:") }
}

actor DisplaySensorReader {
    private var reader: SMCReader?
    func discover() throws -> (smc: [DiscoveredSensor], hid: [HIDTemperature]) {
        if reader == nil { reader = try SMCReader() }
        let smc = try reader!.enumerate(prefix: "T").filter { ["flt ", "sp78", "ioft"].contains($0.type) && $0.value.map { $0 > 0 && $0 < 150 } == true }
        return (smc, HIDTemperatureReader.read())
    }
    func values(_ keys: [String]) -> [String: Double] {
        guard let reader else { return [:] }
        var result: [String: Double] = [:]
        let hid = keys.contains { $0.hasPrefix("HID:") } ? HIDTemperatureReader.read() : []
        for key in Set(keys) {
            if key.hasPrefix("HID:") {
                let readings = hid.filter { $0.name == String(key.dropFirst(4)) }
                if readings.count == 1 { result[key] = readings[0].celsius }
                continue
            }
            if let sample = try? reader.read(key), let value = sample.value, value > 0, value < 150 { result[key] = value }
        }
        return result
    }
}

@MainActor @Observable final class SensorMenuModel {
    private let reader = DisplaySensorReader()
    private(set) var choices: [MenuSensor] = SensorRole.allCases.map {
        MenuSensor(id: "role:\($0.rawValue)", name: DeviceRegistry.current.capabilities.sensorName($0), keys: [], role: $0, estimate: [.cpuAverage, .gpuAverage, .cpuPeak, .gpuPeak].contains($0))
    }
    private(set) var displayed: [String: String] = [:]
    private var refreshTask: Task<Void, Never>?
    private var publishedAt = Date.distantPast
    private var discovered = false
    private(set) var discovering = false
    var discoveryError: String?
    func discover() async {
        guard !discovered, !discovering else { return }; discovering = true; defer { discovering = false }
        do {
            let catalog = try await reader.discover(); let sensors = catalog.smc
            choices += sensors.map { MenuSensor(id: "key:\($0.key)", name: "\($0.key) · raw temperature", keys: [$0.key], role: nil, estimate: false) }
            let names = Set(catalog.hid.map(\.name)).sorted()
            choices += names.map { MenuSensor(id: "hid:" + $0, name: $0 + " · HID", keys: ["HID:" + $0], role: nil, estimate: false) }
            // Model manifests are display regions, not a claim about physical core numbering.
            if HardwareSnapshotReader.machineModel() == SensorRegistry.model {
                let keys = Set(sensors.map(\.key))
                for (id, name, members) in [("cpu-region", "CPU region average · estimate", SensorRegistry.cpuRegionCandidates),
                                            ("gpu-region", "GPU region average · estimate", SensorRegistry.gpuRegionCandidates),
                                            ("tp-region", "Tp region average · estimate", SensorRegistry.cpuRegionCandidates.filter { $0.hasPrefix("Tp") }),
                                            ("tm-region", "Tm region average · estimate", SensorRegistry.cpuRegionCandidates.filter { $0.hasPrefix("Tm") })] where Set(members).isSubset(of: keys) {
                    choices.append(MenuSensor(id: "group:" + id, name: name, keys: members, role: nil, estimate: true))
                }
            } else if DeviceRegistry.current.identity.supportedNotebook {
                let groups = DeviceRegistry.candidates(for: DeviceRegistry.current.identity)
                let available = Set(DeviceRegistry.current.acquisitionKeys)
                for (id, name, candidates) in [("efficiency", DeviceRegistry.current.identity.family == .m5 ? "Super-core region average · estimate" : "Efficiency-core region average · estimate", groups.efficiency),
                    ("performance", "Performance-core region average · estimate", groups.performance)] {
                    let members = candidates.filter { available.contains($0) }
                    if !members.isEmpty { choices.append(MenuSensor(id: "group:" + id, name: name, keys: members, role: nil, estimate: true)) }
                }
            }
            discovered = true; discoveryError = nil
        } catch { discoveryError = "Read-only sensor discovery unavailable. Try again." }
    }
    func scheduleRefresh(selected: [String], simulation: Bool, snapshot: HardwareSnapshot?) {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.refresh(selected: selected, simulation: simulation, snapshot: snapshot)
            self?.refreshTask = nil
        }
    }
    func refresh(selected: [String], simulation: Bool, snapshot: HardwareSnapshot?) async {
        guard !selected.isEmpty else { displayed = [:]; return }
        if !simulation && !discovered && discoveryError == nil && selected.contains(where: { !$0.hasPrefix("role:") }) { await discover() }
        let chosen = choices.filter { selected.contains($0.id) }
        let raw = simulation ? [:] : await reader.values(chosen.flatMap(\.keys))
        let now = simulation ? snapshot?.sampledAt ?? 0 : ProcessInfo.processInfo.systemUptime
        var next: [String: String] = [:]
        for choice in chosen {
            if let role = choice.role {
                let text = StatusPresentation.temperature(snapshot?.sensors.first { $0.role == role }, now: now, estimate: choice.estimate)
                next[choice.id] = text
            } else {
                let members = choice.keys.compactMap { raw[$0] }
                next[choice.id] = members.count == choice.keys.count && !members.isEmpty
                    ? String(format: "%.0f°C%@", members.reduce(0,+) / Double(members.count), choice.estimate ? " ≈" : "") : "Unavailable"
            }
        }
        for id in selected where next[id] == nil { next[id] = "Unavailable on this Mac" }
        displayed = next; publishedAt = Date()
    }
    func title(for id: String) -> String { choices.first { $0.id == id }?.name ?? id }
    func valueText(for id: String) -> String { Date().timeIntervalSince(publishedAt) <= 3 ? (displayed[id] ?? "Unavailable") : "Unavailable" }
    var compactText: String { choices.compactMap { choice in displayed[choice.id].map { text in
        let short = choice.role.map { role in role == .cpuAverage ? "CPU" : role == .gpuAverage ? "GPU" : choice.name } ?? choice.name.components(separatedBy: " · ").first!
        let fresh = Date().timeIntervalSince(publishedAt) <= 3 ? text : "Unavailable"
        return "\(short) \(fresh.replacingOccurrences(of: " · estimate", with: " ≈").replacingOccurrences(of: " · candidate", with: " ?"))"
    } }.joined(separator: "  ") }
}

@MainActor enum SensorMenuDiagnostics {
    static func run() async -> Int32 {
        do {
            let display = SensorMenuModel()
            let started = ProcessInfo.processInfo.systemUptime
            await display.discover()
            guard display.discoveryError == nil else { throw ControlError.invalidSnapshot }
            let client = FanXPCClient(); let status = try await client.status()
            guard let snapshot = status.snapshot else { throw ControlError.invalidSnapshot }
            let choices = display.choices.filter { $0.role == .cpuAverage || $0.id == "group:cpu-region" || $0.id == "group:gpu-region" }
            guard !choices.isEmpty else { throw ControlError.invalidSnapshot }
            await display.refresh(selected: choices.map(\.id), simulation: false, snapshot: snapshot)
            let okay = choices.allSatisfy { display.displayed[$0.id]?.contains("Unavailable") == false }
            let report: [String: Any] = ["sensorMenuCheck": okay ? "passed" : "failed", "choices": display.choices.count,
                "rawSMC": display.choices.filter { $0.id.hasPrefix("key:") }.count,
                "HID": display.choices.filter { $0.id.hasPrefix("hid:") }.count,
                "displayGroups": display.choices.filter { $0.id.hasPrefix("group:") }.count,
                "discoveryAndCheckSeconds": ProcessInfo.processInfo.systemUptime - started,
                "fanModes": snapshot.fans.map { $0.mode.rawValue }]
            var data = try JSONSerialization.data(withJSONObject: report, options: .sortedKeys); data.append(10); FileHandle.standardOutput.write(data)
            return okay ? 0 : 1
        } catch { print("{\"sensorMenuCheck\":\"failed\"}"); return 1 }
    }
}
