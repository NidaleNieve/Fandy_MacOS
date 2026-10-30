import Foundation
import Darwin

/// Read-only local diagnostics. These counters never authorize a lease or command.
public struct ProcessResourceSample: Codable, Sendable, Equatable {
    public let footprintBytes: UInt64
    public let residentBytes: UInt64
    public let userCPUSeconds: Double
    public let systemCPUSeconds: Double
    public static func capture() throws -> Self {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        var usage = rusage()
        guard result == KERN_SUCCESS, getrusage(RUSAGE_SELF, &usage) == 0 else { throw ControlError.helperUnavailable }
        return Self(footprintBytes: info.phys_footprint, residentBytes: info.resident_size,
            userCPUSeconds: Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6,
            systemCPUSeconds: Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6)
    }
}
