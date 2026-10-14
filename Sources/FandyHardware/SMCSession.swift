import Foundation
import IOKit
import FandyCore

/// One serialized userspace connection. The GUI constructs it read-only; the
/// helper enables writes only as root and admits them through its fan recipes.
public final class NativeSMCTransport: SMCStructTransport {
    private let connection: io_connect_t
    private let allowWrites: Bool
    public init(allowWrites: Bool = false) throws {
        self.allowWrites = allowWrites
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw HardwareError.smc(kIOReturnNotFound) }
        defer { IOObjectRelease(service) }
        var port: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &port)
        guard result == KERN_SUCCESS else { throw HardwareError.smc(result) }
        connection = port
    }
    deinit { IOServiceClose(connection) }
    public func transact(_ input: [UInt8]) throws -> SMCStructResponse {
        guard input.count == 80, [5,8,9].contains(input[42]) || (input[42] == 6 && allowWrites && geteuid() == 0) else { throw ControlError.unauthorized }
        var output = [UInt8](repeating: 0, count: 80), size = 80
        let result = input.withUnsafeBytes { source in output.withUnsafeMutableBytes { destination in
            IOConnectCallStructMethod(connection, 2, source.baseAddress, 80, destination.baseAddress, &size)
        }}
        guard result == KERN_SUCCESS else { throw HardwareError.smc(result) }
        return .init(bytes: output, count: size)
    }
}
public struct SMCReadFailure: Error, LocalizedError, Sendable {
    public let failure: HelperFailure
    public init(operation: String, key: String?, result: UInt8, status: UInt8) {
        failure = HelperFailure(kind: .smc, domain: "SMC", code: Int(result), operation: operation, key: key)
        self.status = status
    }
    public let status: UInt8
    public var errorDescription: String? { failure.errorDescription }
}
