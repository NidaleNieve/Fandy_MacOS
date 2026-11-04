import Foundation
import FandyCore

/// Export schema: adding a field requires an explicit privacy decision here.
/// Profiles, arbitrary error text, paths and live sensor/RPM readings are excluded.
private struct DiagnosticExport: Encodable {
    let build = FandyBuild.identifier
    let macOS = ProcessInfo.processInfo.operatingSystemVersionString
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
    let registration: String
    let bootstrapStage: String
    let bootstrapFailure: String
    let bootstrapAttempt: Int
    let modeKeys: [String]
    let targetTypes: [String]
    let forceTest: Bool
    let restorationVerified: Bool
    let fanRestoration: [FanRestoration]
    let model: String
    let chip: String
    let observedHelperBuild: String
    let connectionFailure: ConnectionFailure
    let startupPhase: String
    let sensorGroups: [SensorGroup]
    let controllerState: String
    let helperHealth: String
    let hardwareStage: String
    let ownership: String
    let compatibilityEvidence: String
    let simulation: Bool
    let unsavedChanges: Bool
    let failureCodes: [String]
    let installation: InstallationObservation?
    let helperDiagnostic: HelperDiagnosticReport?

    @MainActor init(_ app: AppModel) {
        registration = String(describing: app.helperSetupStatus)
        bootstrapStage = app.helperBootstrap?.stage.rawValue ?? "unreachable"
        bootstrapFailure = app.helperBootstrap?.failureCode ?? app.helperConnectionFailureCode ?? "none"
        bootstrapAttempt = app.helperBootstrap?.attempt ?? 0
        modeKeys = app.helperInterface?.modeKeys ?? []
        targetTypes = app.helperInterface?.targetTypes ?? []
        forceTest = app.helperInterface?.forceTest ?? false
        restorationVerified = app.helperRestoration?.verified ?? false
        fanRestoration = app.helperRestoration?.fans.map(FanRestoration.init) ?? []
        model = app.deviceIdentity.model
        chip = app.deviceIdentity.chip
        observedHelperBuild = app.observedHelperBuild ?? "unreachable"
        connectionFailure = ConnectionFailure(app.helperFailure)
        startupPhase = app.helperDiagnostic?.phase ?? "unreachable"
        sensorGroups = app.capabilities.sensors.map(SensorGroup.init)
        controllerState = app.machine.state.rawValue
        helperHealth = app.helperHealth.rawValue
        hardwareStage = app.capabilities.stage.rawValue
        ownership = app.ownership.rawValue
        compatibilityEvidence = app.capabilities.compatibilityEvidence.rawValue
        simulation = app.simulation
        unsavedChanges = app.unsavedChanges
        failureCodes = [app.hardwareError == nil ? nil : "monitoring_or_control_error",
                        app.saveError == nil ? nil : "persistence_error"].compactMap { $0 }
        installation = app.installationObservation
        helperDiagnostic = app.helperDiagnostic
    }

    struct FanRestoration: Encodable {
        let fanID: Int
        let initialMode: Int
        let observedMode: Int
        let alreadyAutomatic: Bool
        let verified: Bool
        init(_ outcome: FanRestorationOutcome) {
            fanID = outcome.fanID
            initialMode = outcome.initialMode?.rawValue ?? -1
            observedMode = outcome.observedMode?.rawValue ?? -1
            alreadyAutomatic = outcome.alreadyAutomatic == true
            verified = outcome.verified
        }
    }

    // Nil fields deliberately encode as {} when there is no failure, preserving
    // the existing export format without an untyped dictionary.
    struct ConnectionFailure: Encodable {
        let kind: String?
        let domain: String?
        let code: Int?
        let operation: String?
        init(_ failure: HelperFailure?) {
            kind = failure?.kind.rawValue
            domain = failure?.domain
            code = failure?.code
            operation = failure?.operation
        }
    }

    struct SensorGroup: Encodable {
        let role: String
        let keys: [String]
        let state: String
        init(_ evidence: SensorEvidence) {
            role = evidence.role.rawValue
            keys = evidence.keys
            state = evidence.state.rawValue
        }
    }
}

extension AppModel {
    func sanitizedDiagnostics() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(DiagnosticExport(self))
    }
}
