import Foundation
public struct ControlDiagnostic: Codable, Sendable {
    public let profileDemand: Double?
    public let rawGuardDemand: Double?
    public let enforcedGuardDemand: Double?
    public let governedPercent: Double
    public let byCurve: [CurveInput: Double]?
    public let targets: [FanTarget]
    public let automaticAtIdle: Bool
    public let state: ControllerState
    public let reason: String
    public init(machine: ControlMachine, snapshot: HardwareSnapshot) {
        profileDemand = machine.lastDemand?.profilePercent; rawGuardDemand = machine.guardReading?.rawPercent
        enforcedGuardDemand = machine.guardReading?.enforcedPercent; governedPercent = machine.percent
        byCurve = machine.lastDemand?.byCurve; automaticAtIdle = machine.automaticAtIdle; state = machine.state; reason = machine.transitionReason
        targets = machine.state == .customActive && !machine.automaticAtIdle ? snapshot.fans.compactMap { fan in
            (try? fan.rpm(percent: machine.percent)).map { FanTarget(fan.id, $0) }
        } : []
    }
}
/// User-process diagnostics only. The root helper uses unified logging and accepts no paths.
public final class RotatingDiagnostics: @unchecked Sendable {
    private let queue = DispatchQueue(label: "is.dsr.fandy.diagnostics", qos: .utility)
    private let admission = NSLock()
    private let writer = NSLock()
    private var pending = false
    /// At most one outstanding write; diagnostic backpressure never blocks control.
    public func enqueue(profile: String, snapshot: HardwareSnapshot, control: ControlDiagnostic? = nil, profileID: String? = nil) {
        admission.lock()
        guard !pending else { admission.unlock(); return }
        pending = true; admission.unlock()
        queue.async { [self] in
            defer { admission.lock(); pending = false; admission.unlock() }
            try? record(profile: profile, snapshot: snapshot, control: control, profileID: profileID)
        }
    }
    private let directory:URL
    private let limit:Int
    private let surges: SurgeRecorder
    public init(directory:URL, limit:Int=1_048_576) throws {
        self.directory=directory;self.limit=limit
        self.surges = try SurgeRecorder(directory: directory.appendingPathComponent("surges"))
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    }
    public func record(profile:String,snapshot:HardwareSnapshot,control:ControlDiagnostic? = nil, profileID: String? = nil) throws {
        writer.lock(); defer { writer.unlock() }
        if let control { try? surges.record(FanSurgeSample(timestamp: Date(), profileID: profileID ?? profile, snapshot: snapshot, control: control)) }
        struct Entry:Encodable { let timestamp:Date;let profile:String;let sensors:[SensorReading];let fans:[Fan];let thermalPressure:ThermalPressure;let control:ControlDiagnostic? }
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601
        var line=try encoder.encode(Entry(timestamp:Date(),profile:profile,sensors:snapshot.sensors,fans:snapshot.fans,thermalPressure:snapshot.thermalPressure,control:control));line.append(10)
        let file=directory.appendingPathComponent("diagnostics.jsonl"),manager=FileManager.default
        let bytes=(try? manager.attributesOfItem(atPath:file.path)[.size] as? NSNumber)?.intValue ?? 0
        if bytes+line.count>limit {
            try? manager.removeItem(at:directory.appendingPathComponent("diagnostics.3.jsonl"))
            for index in stride(from:2,through:1,by:-1) {
                let source=directory.appendingPathComponent("diagnostics.\(index).jsonl")
                if manager.fileExists(atPath:source.path) { try manager.moveItem(at:source,to:directory.appendingPathComponent("diagnostics.\(index+1).jsonl")) }
            }
            if manager.fileExists(atPath:file.path) { try manager.moveItem(at:file,to:directory.appendingPathComponent("diagnostics.1.jsonl")) }
        }
        if !manager.fileExists(atPath:file.path) { guard manager.createFile(atPath:file.path,contents:nil,attributes:[.posixPermissions:0o600]) else { throw ControlError.invalidProfile("Cannot create diagnostic log") } }
        let handle=try FileHandle(forWritingTo:file);defer { try? handle.close() };try handle.seekToEnd();try handle.write(contentsOf:line)
    }
}
