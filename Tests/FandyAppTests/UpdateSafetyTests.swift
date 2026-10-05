import Foundation
import Testing
import FandyCore
import Sparkle
@testable import FandyApp

private actor UpdateClient: PrivilegedFanClient {
    var releaseFails = false
    var readbackFails = false
    var calls: [String] = []
    func configure(release: Bool, readback: Bool) { releaseFails = release; readbackFails = readback }
    func events() -> [String] { calls }
    func status() throws -> HelperStatus {
        calls.append("readback")
        let data = Data("{\"fans\":[{\"fanID\":0,\"initialMode\":1,\"commandSucceeded\":true,\"immediateMode\":0,\"observedMode\":0}]}".utf8)
        return HelperStatus(automaticVerified: !readbackFails, restoration: readbackFails ? nil : try Wire.decode(RestorationReport.self, from: data))
    }
    func restoreAutomatic() throws {
        calls.append("release")
        if releaseFails { throw ControlError.restorationUnverified }
    }
    func apply(_ targets: [FanTarget], generation: UInt64) { calls.append("apply") }
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) { calls.append("apply") }
}
@MainActor @Test func updateRequiresActualReleaseAndVerifiedReadback() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let client = UpdateClient()
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
        client: client, helperAvailable: { true }, clock: { 10 })
    try await model.prepareForUpdate()
    #expect(await client.events() == ["release", "readback"])
    #expect(model.preparingUpdate && model.machine.selected.id == "system")
    #expect(!model.canActivate(BuiltInProfiles.maximum))
    model.select("max"); await model.tick()
    #expect(await client.events() == ["release", "readback"])
    try await model.prepareForUpdate()
    #expect(await client.events() == ["release", "readback"])
    await model.prepareForTermination()
    #expect(model.canTerminate)
    #expect(await client.events() == ["release", "readback"])
}
@MainActor @Test func releaseFailureAndMissingAcknowledgementBlockReplacement() async throws {
    for (release, readback) in [(true, false), (false, true)] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = UpdateClient(); await client.configure(release: release, readback: readback)
        let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
            client: client, helperAvailable: { true }, clock: { 10 })
        do { try await model.prepareForUpdate(); Issue.record("Unsafe update allowed") } catch {}
        model.stop()
        #expect(!model.preparingUpdate && !model.canTerminate)
        await client.configure(release: false, readback: false)
        try await model.prepareForUpdate()
        #expect(model.preparingUpdate)
        model.stop()
    }
}
@MainActor @Test func disconnectedCustomControlCannotAuthorizeUpdate() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = AppModel(storeURL: directory.appendingPathComponent("profiles.json"), autoStart: false,
        client: UpdateClient(), helperAvailable: { false })
    _ = try model.machine.select(BuiltInProfiles.maximum)
    do { try await model.prepareForUpdate(); Issue.record("Lost helper authorized replacement") } catch {}
    model.stop()
    #expect(!model.preparingUpdate && !model.canTerminate)
}

@MainActor @Test func acceptedDownloadNeedsNoSecondInstallConfirmation() {
    let driver = AcceptedUpdateDriver(hostBundle: .main, delegate: nil)
    driver.acceptedInstallation = true
    var installed = false
    driver.showReady(toInstallAndRelaunch: { installed = $0 == .install })
    #expect(installed)
    driver.dismissUpdateInstallation()
    #expect(!driver.acceptedInstallation)
}
