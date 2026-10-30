import Foundation
import AppKit
import ServiceManagement
import Testing
import FandyCore
@testable import FandyApp

private struct BackgroundReading: TemperatureSensorProvider {
    func snapshot() async throws -> HardwareSnapshot {
        HardwareSnapshot(at: 10, sensors: [], fans: [.init(id: 0, min: 1000, max: 6000, actual: 0)])
    }
}
@MainActor private final class BackgroundClient: PrivilegedFanClient {
    var calls = 0
    func status() async throws -> HelperStatus {
        calls += 1
        return HelperStatus(automaticVerified: true, snapshot: try await BackgroundReading().snapshot())
    }
    func restoreAutomatic() async throws {}
    func apply(_ targets: [FanTarget], generation: UInt64) async throws { Issue.record("Monitoring must not write targets") }
    func apply(_ targets: [FanTarget], generation: UInt64, required: Set<SensorRole>) async throws { Issue.record("Monitoring must not write targets") }
}
@MainActor @Test func backgroundPollingUsesItsFreshRegistrationObservationWithoutAnotherNativeQuery() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    var registration = SMAppService.Status.enabled, queries = 0
    let client = BackgroundClient()
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false,
        provider: BackgroundReading(), client: client, capabilities: .init(model: "Test"),
        helperRegistrationStatus: { queries += 1; return registration }, clock: { 10 })
    await model.tick()
    #expect(client.calls == 1 && queries == 2)
    registration = .notRegistered
    await model.tick()
    #expect(client.calls == 1 && queries == 3 && model.helperSetupStatus == .notRegistered)
    model.stop()
}

@Test func steadyAndChangingBackgroundDiagnosticsAreFixedAndRejectCallerControlParameters() throws {
    for name in ["--performance-steady-background", "--performance-changing-background"] {
        #expect(try HelperDiagnosticAction.parse(["Fandy", name]) != nil)
        #expect(throws: ControlError.malformedMessage) { try HelperDiagnosticAction.parse(["Fandy", name, "--rpm", "5000"]) }
    }
}

@MainActor @Test func backgroundRegistrationPollingReleasesNativeTemporariesWithoutWaitingForUIEvents() {
    struct WeakObject { weak var value: NSObject? }
    var transient: [WeakObject] = []
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let model = AppModel(storeURL: dir.appendingPathComponent("profiles.json"), autoStart: false,
        helperRegistrationStatus: {
            let object = NSObject(); transient.append(.init(value: object))
            _ = Unmanaged.passRetained(object).autorelease()
            return .enabled
        })
    transient.removeAll()
    for _ in 0..<200 { model.refreshHelperSetup() }
    #expect(transient.count == 200 && transient.allSatisfy { $0.value == nil })
    model.stop()
}

@MainActor @Test func backgroundWindowTeardownDoesNotLeaveNativeTemporariesUntilAnotherUIEvent() {
    final class Reference { weak var value: NSObject? }
    final class Content: NSViewController, ReleasableHostingContent {
        let reference: Reference
        init(_ reference: Reference) { self.reference = reference; super.init(nibName: nil, bundle: nil); view = NSView() }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
        func discardContent() {
            let object = NSObject(); reference.value = object
            _ = Unmanaged.passRetained(object).autorelease()
        }
    }
    let reference = Reference()
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let lifecycle = WindowContentLifecycle(window: window) { Content(reference) }
    lifecycle.prepare(); window.close()
    #expect(reference.value == nil && window.contentViewController == nil)
}

@Test func backgroundWorkloadsDistinguishSteadyTargetsFromContinuousSmallChanges() {
    #expect((0..<60).allSatisfy { BackgroundControlDiagnostics.percent(changing: false, tick: $0) == 3 })
    #expect((0..<6).map { BackgroundControlDiagnostics.percent(changing: true, tick: $0) } == [3,4,3,4,3,4])
}
