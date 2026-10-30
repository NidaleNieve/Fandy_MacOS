import FandyCore

/// Cache only successful validation of an identical authenticated report. This
/// contains no readings, leases, preferences or failed-resolution authority.
public struct RuntimeCapabilityCache {
    private let identity: DeviceIdentity
    private let validate: (RuntimeDeviceReport, HardwareCapabilities, DeviceIdentity) throws -> HardwareCapabilities
    private var accepted: (report: RuntimeDeviceReport, input: HardwareCapabilities, result: HardwareCapabilities)?
    public init(identity: DeviceIdentity,
                validate: @escaping (RuntimeDeviceReport, HardwareCapabilities, DeviceIdentity) throws -> HardwareCapabilities = DeviceRegistry.validate) {
        self.identity = identity; self.validate = validate
    }
    public mutating func resolve(report: RuntimeDeviceReport, capabilities: HardwareCapabilities) throws -> HardwareCapabilities {
        if let accepted, accepted.report == report, accepted.input == capabilities { return accepted.result }
        accepted = nil
        let result = try validate(report, capabilities, identity)
        accepted = (report, capabilities, result)
        return result
    }
}
