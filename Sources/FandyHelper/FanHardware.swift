import Foundation
import FandyCore
import FandyHardware
import IOKit

/// Private writer in the helper executable only. No arbitrary keys are accepted over IPC.
final class AppleFanHardware: FanHardwareIO, @unchecked Sendable {
    private let reader: SMCReader
    private let connection: io_connect_t
    init() throws {
        reader = try SMCReader()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw HardwareError.invalidMetadata }; defer { IOObjectRelease(service) }
        var port: io_connect_t = 0
        let result = IOServiceOpen(service,mach_task_self_,0,&port)
        guard result == KERN_SUCCESS else { throw HardwareError.smc(result) }; connection = port
    }
    deinit { IOServiceClose(connection) }
    func enumerateFans() throws -> [Fan] {
        let fans = try reader.fans()
        guard Set(fans.map(\.id)) == Set(SensorRegistry.observedFanIDs) else { throw ControlError.invalidFan }
        return fans
    }
    func fanIDsForRestoration() throws -> [Int] {
        guard HardwareSnapshotReader.machineModel() == SensorRegistry.model else { throw ControlError.hardwareUnqualified }
        // Model-scoped topology independently observed in discovery. Corrupt RPM/ranges/count
        // must not prevent a release attempt. New models need their own qualified topology.
        return SensorRegistry.observedFanIDs
    }
    func readMode(fanID: Int) throws -> FanMode {
        let value = try reader.read(qualifiedModeKey(fanID))
        guard let mode = SMCDecoder.fanMode(type: value.type, bytes: value.bytes) else { throw HardwareError.invalidMetadata }; return mode
    }
    func setAutomatic(fanID: Int) throws {
        guard SensorRegistry.capabilities.canRestore, HardwareSnapshotReader.machineModel() == SensorRegistry.model else { throw ControlError.hardwareUnqualified }
        let key = try qualifiedModeKey(fanID), mode = try reader.read(key)
        guard mode.type == "ui8 ", mode.size == 1, mode.bytes.count == 1 else { throw HardwareError.invalidMetadata }
        try SMCAutomaticModeWriter.restore(fanID: fanID, metadata: mode, transport: self)
    }
    // Phase 6 implementations intentionally deferred until physical automatic restoration passes.
    // Flipping a preference/qualification flag cannot introduce an arbitrary target writer here.
    func setManual(fanID: Int) throws { throw ControlError.hardwareUnqualified }
    func setTarget(fanID: Int, rpm: Double) throws { throw ControlError.hardwareUnqualified }
    private func qualifiedModeKey(_ id: Int) throws -> String {
        guard let key = SensorRegistry.observedModeKeys[id] else { throw ControlError.invalidFan }
        return key
    }
    func transact(_ input: [UInt8]) throws -> SMCStructResponse {
        guard geteuid() == 0, SensorRegistry.capabilities.forMachine(HardwareSnapshotReader.machineModel()).canRestore,
              input.count == 80 else { throw ControlError.unauthorized }
        var output = [UInt8](repeating: 0, count: 80)
        var outputSize = 80
        let result = input.withUnsafeBytes { source in output.withUnsafeMutableBytes { destination in
            IOConnectCallStructMethod(connection, 2, source.baseAddress, 80, destination.baseAddress, &outputSize)
        }}
        guard result == KERN_SUCCESS else { throw ControlError.restorationUnverified }
        return SMCStructResponse(bytes: output, count: outputSize)
    }
}
extension AppleFanHardware: SMCStructTransport {}
