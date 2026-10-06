import Foundation

public struct FanSurgeSample: Codable, Sendable {
    public let timestamp: Date
    public let profileID: String
    public let snapshot: HardwareSnapshot
    public let control: ControlDiagnostic
    public var observedPercent: Double { snapshot.fans.compactMap { try? $0.percent(rpm: $0.actualRPM) }.max() ?? 0 }
    public init(timestamp: Date, profileID: String, snapshot: HardwareSnapshot, control: ControlDiagnostic) {
        self.timestamp = timestamp; self.profileID = profileID; self.snapshot = snapshot; self.control = control
    }
}
public struct FanSurgeEvent: Codable, Sendable {
    public let id: UUID
    public let triggeredAt: Date
    public let samples: [FanSurgeSample]
}
/// Fixed windows: repeated surges never extend capture indefinitely.
public struct SurgeDetector: Sendable {
    private var history: [FanSurgeSample] = []
    private var capture: [FanSurgeSample] = []
    private var trigger: Date?
    private var triggerElapsed: Double?
    private var last: Double?
    public init() {}
    public mutating func observe(_ sample: FanSurgeSample) -> FanSurgeEvent? {
        let now = sample.snapshot.sampledAt
        guard now.isFinite, sample.control.governedPercent.isFinite else { reset(); return nil }
        if let last {
            if now <= last { if now < last { reset() }; return nil }
            if now - last > 10 { reset() }
        }
        last = now
        if let trigger {
            capture.append(sample)
            if let started = triggerElapsed, now - started >= 60 {
                let event = FanSurgeEvent(id: UUID(), triggeredAt: trigger, samples: capture)
                self.trigger = nil; triggerElapsed = nil; capture = []
                appendHistory(sample); return event
            }
        } else {
            let recent = history.filter { now - $0.snapshot.sampledAt <= 10 && $0.profileID == sample.profileID && $0.snapshot.fans.map(\.id) == sample.snapshot.fans.map(\.id) }
            let increased = recent.contains {
                sample.control.governedPercent - $0.control.governedPercent >= 10 || sample.observedPercent - $0.observedPercent >= 10
            }
            if increased { trigger = sample.timestamp; triggerElapsed = now; capture = history.filter { now - $0.snapshot.sampledAt <= 30 } + [sample] }
        }
        appendHistory(sample)
        return nil
    }
    private mutating func appendHistory(_ sample: FanSurgeSample) {
        history.append(sample)
        history.removeAll { sample.snapshot.sampledAt - $0.snapshot.sampledAt > 30 }
        if history.count > 300 { history.removeFirst(history.count - 300) }
        if capture.count > 900 { reset() } // malformed/high-rate callers cannot grow memory indefinitely
    }
    private mutating func reset() { history = []; capture = []; trigger = nil; triggerElapsed = nil; last = nil }
}
/// Local user-process storage; no helper paths or hardware effects.
public final class SurgeRecorder {
    private let directory: URL
    private let maxEvents: Int, maxBytes: Int
    private let maxAge: TimeInterval
    private var detector = SurgeDetector()
    private var lastPrunedAt: Date?
    public init(directory: URL, maxEvents: Int = 32, maxBytes: Int = 8_388_608, maxAge: TimeInterval = 604_800) throws {
        self.directory = directory; self.maxEvents = max(1, maxEvents); self.maxBytes = max(1, maxBytes); self.maxAge = max(0, maxAge)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try prune(now: Date())
    }
    public func record(_ sample: FanSurgeSample) throws {
        if lastPrunedAt.map({ sample.timestamp.timeIntervalSince($0) >= 60 || sample.timestamp < $0 }) ?? true { try prune(now: sample.timestamp); lastPrunedAt = sample.timestamp }
        guard let event = detector.observe(sample) else { return }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        guard data.count <= maxBytes else { return }
        let file = directory.appendingPathComponent("surge-\(event.id.uuidString).json")
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600, .modificationDate: sample.timestamp], ofItemAtPath: file.path)
        try prune(now: sample.timestamp)
    }
    public func prune(now: Date) throws {
        let manager = FileManager.default
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            .filter { $0.lastPathComponent.hasPrefix("surge-") && $0.pathExtension == "json" }
        var retained: [(URL, Date, Int)] = []
        for file in files {
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let date = values.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(date) > maxAge { try manager.removeItem(at: file) }
            else { retained.append((file, date, values.fileSize ?? 0)) }
        }
        retained.sort { $0.1 > $1.1 }
        var bytes = 0
        for (index, entry) in retained.enumerated() {
            if index >= maxEvents || bytes + entry.2 > maxBytes { try manager.removeItem(at: entry.0) }
            else { bytes += entry.2 }
        }
    }
}
