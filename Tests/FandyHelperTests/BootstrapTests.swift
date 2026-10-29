import Foundation
import Testing
import FandyCore
import FandyHardware
@testable import FandyHelper

/// Synthetic reference-derived packet fixture, not a physical device recording.
private final class StartupPackets: SMCStructTransport {
    let identity: DeviceIdentity
    var values: [String: (String, UInt8, [UInt8])] = [:]
    var operations: [(String, UInt8)] = []
    init(_ identity: DeviceIdentity) {
        self.identity = identity
        values["FNum"] = ("ui8 ", 128, [2])
        for id in 0..<2 {
            values["F\(id)md"] = ("ui8 ", 208, [0])
            for (suffix, rpm) in [("Mn", 1200.0), ("Mx", 6500.0), ("Ac", 0.0), ("Tg", 2000.0)] {
                values["F\(id)\(suffix)"] = ("flt ", 212, Self.bytes(rpm))
            }
        }
        let chip = DeviceRegistry.candidates(for: identity)
        var keys = chip.efficiency + chip.performance + chip.gpu
        if identity.model == SensorRegistry.model { keys += SensorRegistry.chipEnvelopeKeys }
        keys += ["Ts0P", "Ts1P", "TaLP", "TaTP", "TaRF", "TW0P"]
        for key in keys { values[key] = ("flt ", 128, Self.bytes(35)) }
    }
    static func bytes(_ n: Double) -> [UInt8] { let bits = Float(n).bitPattern; return (0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) } }
    func transact(_ input: [UInt8]) throws -> SMCStructResponse {
        let key = String(bytes: input[0..<4].reversed(), encoding: .ascii)!
        operations.append((key, input[42]))
        var output = [UInt8](repeating: 0, count: 80)
        guard let item = values[key] else { output[40] = 0x84; return .init(bytes: output, count: 80) }
        switch input[42] {
        case 9: output[28] = UInt8(item.2.count); output.replaceSubrange(32..<36, with: item.0.utf8.reversed()); output[36] = item.1
        case 5: output.replaceSubrange(48..<(48 + item.2.count), with: item.2)
        case 6: values[key] = (item.0, item.1, Array(input[48..<(48 + item.2.count)]))
        default: throw HardwareError.invalidMetadata
        }
        return .init(bytes: output, count: 80)
    }
}
@Test(arguments: [DeviceIdentity(model: "MacBookPro18,3", chip: "Apple M1 Pro", appleSilicon: true),
    .init(model: "Mac14,9", chip: "Apple M2 Pro", appleSilicon: true),
    .init(model: "Mac15,6", chip: "Apple M3 Pro", appleSilicon: true),
    .init(model: "Mac16,8", chip: "Apple M4 Pro", appleSilicon: true),
    .init(model: "Mac17,9", chip: "Apple M5 Pro", appleSilicon: true)])
func actualHelperBootstrapRestoresBeforeSensorDiscovery(_ identity: DeviceIdentity) async throws {
    let packets = StartupPackets(identity)
    let service = HelperService(hardwareFactory: { _ in
        try AppleFanHardware(reader: SMCReader(transport: packets), identity: identity)
    })
    await withCheckedContinuation { done in service.queue.async { service.startBackend(); done.resume() } }
    let value = service.statusCache.read(at: ProcessInfo.processInfo.systemUptime)
    if identity.model == SensorRegistry.model {
        // The tested direct recipe always writes modes. Production root checks
        // intentionally reject it in this unprivileged unit-test process.
        #expect(value.bootstrap?.stage == .failed && !value.automaticVerified)
        #expect(!packets.operations.contains { $0.1 == 6 })
        #expect(!packets.operations.contains { $0.0.hasPrefix("T") })
        return
    }
    #expect(value.bootstrap?.stage == .ready && value.automaticVerified)
    #expect(value.deviceReport?.model == identity.model)
    #expect(try Wire.encode(value).count <= Wire.maxBytes)
    let firstTemperature = try #require(packets.operations.firstIndex { $0.0.hasPrefix("T") })
    let prior = packets.operations[..<firstTemperature]
    #expect(prior.contains { $0.0 == "F1md" && $0.1 == 5 })
    if identity.model == SensorRegistry.model {
        #expect(prior.filter { $0.1 == 6 }.map(\.0) == ["F0md", "F1md"])
    } else { #expect(!prior.contains { $0.1 == 6 }) }
}

@Test func transientStartupFailureCanRetryAfterWakeWithoutCreatingControl() async throws {
    let packets = StartupPackets(.init(model: "Mac14,9", chip: "Apple M2 Pro", appleSilicon: true))
    var attempts = 0
    let service = HelperService(hardwareFactory: { _ in
        attempts += 1
        if attempts == 1 { throw HardwareError.smc(5) }
        return try AppleFanHardware(reader: SMCReader(transport: packets), identity: packets.identity)
    })
    await withCheckedContinuation { done in service.queue.async { service.startBackend(); done.resume() } }
    #expect(service.statusCache.read(at: ProcessInfo.processInfo.systemUptime).bootstrap?.stage == .failed)
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in service.queue.async { service.retryBackendAfterWake(); done.resume() } }
    #expect(service.statusCache.read(at: ProcessInfo.processInfo.systemUptime).bootstrap?.stage == .ready)
    #expect(!packets.operations.contains { $0.1 == 6 })
}

@Test func unsupportedModeMetadataIsReportedByAHealthyObservationBackend() async throws {
    let packets = StartupPackets(.init(model: "Mac14,9", chip: "Apple M2 Pro", appleSilicon: true))
    packets.values["F0md"] = ("ui8 ", 128, [0])
    let service = HelperService(hardwareFactory: { _ in
        try AppleFanHardware(reader: SMCReader(transport: packets), identity: packets.identity)
    })
    await withCheckedContinuation { done in service.queue.async { service.startBackend(); done.resume() } }
    let report = service.statusCache.read(at: ProcessInfo.processInfo.systemUptime)
    #expect(report.bootstrap?.stage == .ready && report.observationOnly)
    #expect(report.diagnostic?.fans.first { $0.id == 0 }?.modeAttributes == 128)
    #expect(report.diagnostic?.failure?.kind == .metadata)
    #expect(!packets.operations.contains { $0.1 == 6 })
}

@Test func realHelperTimerSwitchesAtLeaseAdmissionAndRetainsFastRestorationRetries() async throws {
    let packets = StartupPackets(.init(model: "Mac14,9", chip: "Apple M2 Pro", appleSilicon: true))
    let service = HelperService(hardwareFactory: { _ in
        try AppleFanHardware(reader: SMCReader(transport: packets), identity: packets.identity)
    }, controllerPresence: ControllerPresenceObservation(inspect: {}))
    try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
        service.queue.async {
            let timer = DispatchSource.makeTimerSource(queue: service.queue)
            timer.setEventHandler {}; timer.resume(); service.timer = timer
            defer { timer.cancel() }
            do {
                service.startBackend()
                #expect(service.pollingInterval == 1)
                let coordinator = try service.requireCoordinator()
                for _ in 0..<5 { _ = coordinator.status() }
                _ = try coordinator.begin(LeaseRequest(generation: 1, required: SensorRole.safety), owner: UUID())
                service.publishStatus(); #expect(service.pollingInterval == 0.1)
                #expect(coordinator.restore())
                service.publishStatus(); #expect(service.pollingInterval == 1)
                packets.values.removeValue(forKey: "F0md")
                #expect(!coordinator.restore())
                service.publishStatus(); #expect(service.pollingInterval == 0.1)
                done.resume()
            } catch { done.resume(throwing: error) }
        }
    }
}
