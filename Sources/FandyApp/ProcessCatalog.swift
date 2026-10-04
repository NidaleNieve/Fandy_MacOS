import AppKit
import Foundation
import Darwin

struct RunningProcess: Identifiable, Equatable {
    let pid: Int32
    let launched: Date
    let name: String
    let bundleID: String?
    let icon: NSImage?
    var id: String { "\(pid):\(launched.timeIntervalSince1970)" }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.name == rhs.name }
}

@MainActor enum ProcessCatalog {
    static func list(includeHelpers: Bool, includeIcons: Bool = true) -> [RunningProcess] {
        let applications = NSWorkspace.shared.runningApplications
        var result = applications.compactMap { app -> RunningProcess? in
            guard includeHelpers || app.activationPolicy == .regular,
                  let launched = startTime(app.processIdentifier) else { return nil }
            return RunningProcess(pid: app.processIdentifier, launched: launched,
                                  name: app.localizedName ?? "Application", bundleID: app.bundleIdentifier, icon: includeIcons ? app.icon : nil)
        }
        if includeHelpers {
            let known = Set(result.map(\.pid))
            for pid in processIDs() where !known.contains(pid) {
                guard let launched = startTime(pid) else { continue }
                var bytes = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                let count = proc_pidpath(pid, &bytes, UInt32(bytes.count))
                guard count > 0 else { continue }
                let path = bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                result.append(RunningProcess(pid: pid, launched: launched, name: URL(fileURLWithPath: path).lastPathComponent, bundleID: nil, icon: nil))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func isRunning(pid: Int32, launched: Date) -> Bool { startTime(pid) == launched }
    private static func startTime(_ pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size, info.pbi_status != UInt32(SZOMB) else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }
    private static func processIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0, count < 100_000 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 128)
        let read = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard read > 0 else { return [] }; return Array(pids.prefix(min(Int(read), pids.count)))
    }
}
