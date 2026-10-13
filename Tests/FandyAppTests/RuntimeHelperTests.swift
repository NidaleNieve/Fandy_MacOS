import Foundation
import ServiceManagement
import Testing
import FandyCore
import FandyHardware
@testable import FandyApp

@MainActor private final class BootstrapClient: PrivilegedFanClient {
    var reply: HelperStatus
    init(_ reply: HelperStatus) { self.reply = reply }
    func status() async throws -> HelperStatus { reply }
    func apply(_ targets: [FanTarget], generation: UInt64) async throws {}
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) async throws {}
    func restoreAutomatic() async throws {}
}
@MainActor @Test func approvedStartingHelperIsNotMisreportedAsDeadOrUnapproved() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let identity = DeviceIdentity(model: "Mac14,9", chip: "Apple M2 Pro", appleSilicon: true)
    var reply = HelperStatus(automaticVerified: false, bootstrap: .init())
    reply.diagnostic = .init(phase: "fan_discovery", progressAt: 10)
    reply.deviceReport = .init(model: identity.model, chip: identity.chip, catalog: DeviceRegistry.statsRevision, recipe: nil)
    let client = BootstrapClient(reply)
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false, client: client,
        helperAvailable: { true }, helperRegistrationStatus: { .enabled }, deviceIdentity: identity, clock: { 10 })
    await model.tick()
    #expect(!model.shouldPresentHelperApproval && !model.needsHelperAttention)
    #expect(!model.canActivate(BuiltInProfiles.maximum))
    client.reply.bootstrap = .init(stage: .failed)
    client.reply.diagnostic = .init(phase: "fan_discovery", progressAt: 10, failure: .init(kind: .metadata, domain: "Fandy", code: 1, operation: "fan_discovery"))
    await model.tick()
    #expect(model.needsHelperAttention && !model.shouldPresentHelperApproval)
    #expect(model.helperSetupMessage.contains("interface"))
    let report = try JSONSerialization.jsonObject(with: model.sanitizedDiagnostics()) as! [String: Any]
    #expect(report["chip"] as? String == "Apple M2 Pro")
    #expect(report["connectionFailure"] != nil)
    await model.prepareForTermination()
}

@MainActor @Test(arguments: [HelperDiagnosticAction.profilesLive, .productionDisconnect, .profilesSleep, .maximumCheck])
func nativeProfileDiagnosticsWaitForAuthenticatedRuntimeCapabilities(_ action: HelperDiagnosticAction) async throws {
    let identity = DeviceIdentity(model: "Mac14,9", chip: "Apple M2 Pro", appleSilicon: true)
    let groups = DeviceRegistry.candidates(for: identity)
    let cap = HardwareCapabilities(model: identity.model, stage: .qualifiedControl,
        sensors: [.init(role: .cpuPeak, keys: [groups.efficiency[0], groups.performance[0]], state: .referenceSupported, source: "fixture", limitation: "synthetic"),
                  .init(role: .gpuPeak, keys: [groups.gpu[0]], state: .referenceSupported, source: "fixture", limitation: "synthetic")],
        topology: .referenceSupported, automaticRestoration: .referenceSupported, manualTransaction: .referenceSupported,
        chipControl: .cpuGPU, evidence: .referenceSupported)
    var status = HelperStatus(automaticVerified: true, manualQualified: true,
        snapshot: HardwareSnapshot(at: 10, sensors: [.init(.cpuPeak, 35, at: 10), .init(.gpuPeak, 35, at: 10)],
            fans: [.init(id: 0, min: 1000, max: 6000, actual: 0)]), capabilities: cap, bootstrap: .init(stage: .ready))
    status.deviceReport = .init(model: identity.model, chip: identity.chip, catalog: DeviceRegistry.statsRevision, recipe: "reference-direct")
    status.helperBuild = FandyBuild.identifier
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false,
        client: BootstrapClient(status), helperAvailable: { true }, deviceIdentity: identity, clock: { 10 })
    #expect(model.capabilities.stage == .observation)
    try await HelperDiagnostics.prepare(model, action: action, pause: {})
    #expect(model.capabilities.stage == .qualifiedControl && model.canActivate(BuiltInProfiles.systemPlus))
    await model.prepareForTermination()
}
