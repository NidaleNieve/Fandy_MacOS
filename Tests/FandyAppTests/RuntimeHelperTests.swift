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
