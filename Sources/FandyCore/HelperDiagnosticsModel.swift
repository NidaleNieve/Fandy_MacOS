import Foundation

/// Stable allowlisted failures. Raw localized descriptions never cross the wire or export.
public struct HelperFailure: Error, LocalizedError, Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case authentication, serviceUnavailable, timeout, interrupted, smc, metadata, restoration, sensors, installation, power, unknown }
    public let kind: Kind
    public let domain: String
    public let code: Int
    public let operation: String
    public let key: String?
    public init(kind: Kind, domain: String, code: Int, operation: String, key: String? = nil) {
        self.kind = kind
        self.domain = [NSCocoaErrorDomain, NSOSStatusErrorDomain, "IOKit", "SMC", "Fandy"].contains(domain) ? domain : "Other"
        self.code = code
        self.operation = ["status","restore","targets","lease","connect","fan_discovery","sensor_discovery","smc_open","read_info","read_value","enumerate","transport","signature","listener","power","startup"].contains(operation) ? operation : "unknown"
        self.key = key.flatMap { $0.utf8.count == 4 && $0.utf8.allSatisfy { (32...126).contains($0) } ? $0 : nil }
    }
    public static func connection(_ error: NSError, operation: String) -> Self {
        let kind: Kind
        if error.domain == NSCocoaErrorDomain {
            kind = switch error.code { case 4102: .authentication; case 4099: .serviceUnavailable; case 4097: .interrupted; default: .unknown }
        } else { kind = .unknown }
        return Self(kind: kind, domain: error.domain, code: error.code, operation: operation)
    }
    public static func timeout(operation: String) -> Self { .init(kind: .timeout, domain: "Fandy", code: 1, operation: operation) }
    public var errorDescription: String? {
        switch kind {
        case .authentication: "The fan helper rejected this app's identity. Reinstall the official Fandy release."
        case .serviceUnavailable: "The approved fan helper is not running. Retry the helper or export diagnostics."
        case .timeout: "The fan helper did not respond. Retry or export diagnostics."
        case .interrupted: "The fan helper connection was interrupted."
        case .metadata: "The fan interface is unsupported on this Mac. Export diagnostics."
        case .restoration: "Automatic fan restoration could not be verified."
        case .smc: "Hardware access failed during \(operation). Export diagnostics."
        case .sensors: "Required temperature inputs are unavailable."
        case .installation: "The installed app or helper signature is invalid. Reinstall Fandy in Applications."
        case .power: "The helper could not register sleep notifications."
        case .unknown: "The fan helper failed during \(operation). Export diagnostics."
        }
    }
}
public struct RuntimeDeviceReport: Codable, Sendable, Equatable {
    public let model: String
    public let chip: String
    public let catalog: String
    public let recipe: String?
    public init(model: String, chip: String, catalog: String, recipe: String?) {
        self.model = model; self.chip = chip; self.catalog = catalog; self.recipe = recipe
    }
}
public struct FanMetadataReport: Codable, Sendable, Equatable {
    public var id: Int
    public var modeKey: String?
    public var modeType: String?
    public var modeAttributes: UInt8?
    public var targetType: String?
    public var targetAttributes: UInt8?
    public var minimumRPM: Double?
    public var maximumRPM: Double?
    public init(id: Int) { self.id = id }
}
public struct HelperDiagnosticReport: Codable, Sendable, Equatable {
    public var phase: String
    public var progressAt: Double
    public var failure: HelperFailure?
    public var fans: [FanMetadataReport]
    public var stalled: Bool? = nil
    public var resources: ProcessResourceSample? = nil
    public var work: [BackgroundWorkSample]? = nil
    public init(phase: String, progressAt: Double, failure: HelperFailure? = nil, fans: [FanMetadataReport] = []) {
        self.phase = phase; self.progressAt = progressAt; self.failure = failure; self.fans = fans
    }
}
/// Health publication never calls hardware. The helper's sole hardware queue
/// publishes value snapshots; authenticated ingress reads them under a short lock.
public final class HelperStatusStore: @unchecked Sendable {
    private let lock = NSLock()
    private var status = HelperStatus(automaticVerified: false)
    public init() {}
    public func publish(_ value: HelperStatus, at: Double) {
        var compact = value
        if let cap = value.capabilities {
            compact.capabilities = HardwareCapabilities(model: cap.model, stage: cap.stage,
                sensors: cap.sensors.map { .init(role: $0.role, keys: $0.keys, state: $0.state, source: "compiled-registry", limitation: "", displayName: $0.displayName) },
                topology: cap.topology, automaticRestoration: cap.automaticRestoration,
                manualTransaction: cap.manualTransaction, chipControl: cap.chipControl, evidence: cap.evidence)
        }
        lock.lock(); status = compact; lock.unlock()
    }
    public func read(at now: Double) -> HelperStatus {
        lock.lock(); var copy = status; lock.unlock()
        let stale = copy.snapshot.map { !now.isFinite || now < $0.sampledAt || now - $0.sampledAt > 3 } ?? false
        let initializing = copy.bootstrap?.stage == .initializing || copy.bootstrap?.stage == .restoring
        let stalledStartup = initializing && copy.diagnostic.map { !now.isFinite || now < $0.progressAt || now - $0.progressAt > 3 } == true
        copy.diagnostic?.stalled = stale || stalledStartup
        if stale { copy.automaticVerified = false }
        return copy
    }
}
