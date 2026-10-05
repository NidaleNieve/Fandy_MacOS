import ServiceManagement
import Testing
import FandyCore
@testable import FandyApp

@MainActor @Test func helperRemovalHandlesExplicitRegistrationStates() async throws {
    for state in [SMAppService.Status.enabled, .requiresApproval, .notRegistered, .notFound] {
        var events: [String] = []
        try await HelperManager.remove(status: state, restore: { events.append("restore") }, unregister: { events.append("remove") })
        let expected = state == .enabled ? ["restore", "remove"] : state == .requiresApproval ? ["remove"] : []
        #expect(events == expected)
    }
}
@MainActor @Test func failedAutomaticHandbackBlocksEnabledHelperRemoval() async {
    var removed = false
    await #expect(throws: ControlError.restorationUnverified) {
        try await HelperManager.remove(status: .enabled, restore: { throw ControlError.restorationUnverified }, unregister: { removed = true })
    }
    #expect(!removed)
}
