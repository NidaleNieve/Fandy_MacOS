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

@MainActor @Test func legacyMigrationReleasesBeforeRemovalAndSkipsUnregisteredServices() async throws {
    var events: [String] = []
    for state in [SMAppService.Status.enabled, .requiresApproval, .notRegistered, .notFound] {
        try await HelperManager.migrateLegacyRegistration(status: state,
            restore: { events.append("restore") }, unregister: { events.append("remove") })
    }
    #expect(events == ["restore", "remove", "remove"])
}

@MainActor @Test func unreachableLegacyJobCanBeReplacedButFailedHandbackCannot() async throws {
    var removed = false
    try await HelperManager.migrateLegacyRegistration(status: .enabled,
        restore: { throw ControlError.helperUnavailable }, unregister: { removed = true })
    #expect(removed)
    removed = false
    await #expect(throws: ControlError.restorationUnverified) {
        try await HelperManager.migrateLegacyRegistration(status: .enabled,
            restore: { throw ControlError.restorationUnverified }, unregister: { removed = true })
    }
    #expect(!removed)
}

@MainActor @Test func failedLegacyRemovalPreventsMigrationCompletion() async {
    await #expect(throws: ControlError.helperUnavailable) {
        try await HelperManager.migrateLegacyRegistration(status: .requiresApproval,
            restore: { Issue.record("An unapproved job must not receive hardware commands") },
            unregister: { throw ControlError.helperUnavailable })
    }
}
