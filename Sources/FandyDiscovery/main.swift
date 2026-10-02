import Foundation
import FandyHardware
struct Report: Codable {
    let timestamp: String
    let model: String
    let os: String
    let fans: [FandyCore.Fan]
    let keys: [DiscoveredSensor]
    let hid: [HIDTemperature]
    let note: String
}
import FandyCore
let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--help") { print("fandy-discover [--prefix T|F] [--samples N] [--interval seconds]\nfandy-discover --fans-only\nRead-only SMC discovery. JSON lines on stdout; no fan writes."); exit(0) }
if args == ["--fans-only"] {
    do {
        let reader = try SMCReader()
        let report = Report(timestamp: ISO8601DateFormatter().string(from: Date()), model: HardwareSnapshotReader.machineModel(),
                            os: ProcessInfo.processInfo.operatingSystemVersionString, fans: try reader.fans(), keys: [], hid: [],
                            note: "Independent read-only fan observation; no helper connection or fan writes.")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(report); data.append(10); FileHandle.standardOutput.write(data); exit(0)
    } catch { FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1) }
}
func option(_ name: String) -> String? { guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }; return args[i+1] }
let samples = Int(option("--samples") ?? "1") ?? 0
let interval = Double(option("--interval") ?? "1") ?? .nan
let prefix = option("--prefix") ?? "T"
guard (1...3600).contains(samples), interval.isFinite, (0.25...60).contains(interval), ["T","F"].contains(prefix), args.enumerated().allSatisfy({ $0.offset % 2 == 0 ? ["--prefix","--samples","--interval"].contains($0.element) : true }), args.count % 2 == 0 else {
    FileHandle.standardError.write(Data("Invalid discovery options. Use --help.\n".utf8)); exit(2)
}
do {
    let reader = try SMCReader()
    var size: size_t = 0; sysctlbyname("hw.model", nil, &size, nil, 0)
    var buffer = [CChar](repeating: 0, count: size); sysctlbyname("hw.model", &buffer, &size, nil, 0)
    let model = String(bytes: buffer.dropLast().map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? "unknown"
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    for i in 0..<samples {
        let report = Report(timestamp: ISO8601DateFormatter().string(from: Date()), model: model, os: ProcessInfo.processInfo.operatingSystemVersionString, fans: try reader.fans(), keys: try reader.enumerate(prefix: prefix), hid: HIDTemperatureReader.read(), note: "Sensor names are candidates, not qualified control inputs. ioft decoding is exploratory.")
        var line = try encoder.encode(report); line.append(10); FileHandle.standardOutput.write(line)
        if i+1 < samples { Thread.sleep(forTimeInterval: interval) }
    }
} catch { FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1) }
