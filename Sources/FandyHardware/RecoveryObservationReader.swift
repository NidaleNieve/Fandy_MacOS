import Foundation
import FandyCore
import CSMC

/// Wider raw-domain guard for finite mechanical testing, never production sensor selection.
/// Prefixes do not establish identity; all candidate labels stay unverified.
public final class RecoveryObservationReader {
    private let sampler: HardwareSnapshotReader
    private let reader: SMCReader
    private let keys: [String]
    public init(sampler: HardwareSnapshotReader) throws {
        self.sampler = sampler; reader = try SMCReader()
        keys = try reader.enumerate(prefix: "T").filter {
            ["Tp", "Tm", "Tg"].contains(String($0.key.prefix(2))) &&
            $0.type == "flt " && $0.size == 4 && $0.error == nil &&
            $0.value.map { $0.isFinite && $0 > 0 && $0 < 150 } == true
        }.map(\.key)
        guard ["Tp", "Tm", "Tg"].allSatisfy({ prefix in keys.contains { $0.hasPrefix(prefix) } }) else {
            throw ControlError.invalidSnapshot
        }
    }
    public func observation() throws -> RecoveryObservation {
        let snapshot = try sampler.snapshot()
        var peak = 0.0
        for key in keys {
            let value = try reader.read(key)
            guard value.type == "flt ", value.size == 4, let celsius = value.value,
                  celsius.isFinite, celsius > 0, celsius < 150 else { throw ControlError.invalidSnapshot }
            peak = max(peak, celsius)
        }
        return RecoveryObservation(snapshot: snapshot, diagnosticPeak: peak, diagnosticKeyCount: keys.count)
    }
}

public enum RecoveryOwnershipProbe {
    /// A known-controller conflict guard, not proof that every possible utility is absent.
    /// Helper-only callers also continuously verify fan ownership and target readback.
    public static func requireNoKnownController() throws {
        guard geteuid() == 0 else { throw ControlError.unauthorized }
        switch fandy_tg_controller_present() {
        case 0: return
        case 1: throw ControlError.invalidProfile("TG Pro's privileged fan helper is running; exclusive fan testing is blocked.")
        default: throw ControlError.invalidProfile("Fan-controller process enumeration unavailable; exclusive testing is blocked.")
        }
    }
}
