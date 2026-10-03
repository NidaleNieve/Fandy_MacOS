import Foundation
/// User-process diagnostics only. The root helper uses unified logging and accepts no paths.
public final class RotatingDiagnostics: @unchecked Sendable {
    private let queue = DispatchQueue(label: "is.dsr.fandy.diagnostics", qos: .utility)
    private let admission = NSLock()
    private let writer = NSLock()
    private var pending = false
    /// At most one outstanding write; diagnostic backpressure never blocks control.
    public func enqueue(profile: String, snapshot: HardwareSnapshot) {
        admission.lock()
        guard !pending else { admission.unlock(); return }
        pending = true; admission.unlock()
        queue.async { [self] in
            defer { admission.lock(); pending = false; admission.unlock() }
            try? record(profile: profile, snapshot: snapshot)
        }
    }
    private let directory:URL
    private let limit:Int
    public init(directory:URL, limit:Int=1_048_576) throws {
        self.directory=directory;self.limit=limit
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    }
    public func record(profile:String,snapshot:HardwareSnapshot) throws {
        writer.lock(); defer { writer.unlock() }
        struct Entry:Encodable { let timestamp:Date;let profile:String;let sensors:[SensorReading];let fans:[Fan];let thermalPressure:ThermalPressure }
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601
        var line=try encoder.encode(Entry(timestamp:Date(),profile:profile,sensors:snapshot.sensors,fans:snapshot.fans,thermalPressure:snapshot.thermalPressure));line.append(10)
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
