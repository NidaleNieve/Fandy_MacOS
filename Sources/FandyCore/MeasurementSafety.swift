import Foundation

/// Diagnostic stimulus admission only. This never grants fan-control authority.
public enum MeasurementSafety {
    public static let ceilingC = 75.0
    public static func validate(_ snapshot: HardwareSnapshot, now: Double) throws {
        try snapshot.validateFans(now: now)
        guard snapshot.fans.allSatisfy({ $0.mode == .automatic }),
              snapshot.thermalPressure == .nominal || snapshot.thermalPressure == .fair else { throw ControlError.restorationUnverified }
        // Candidate labels are deliberately still unqualified. Require a complete, fresh
        // documented chip domain for this conservative measurement ceiling.
        let roles = SensorRole.safety.union(snapshot.sensors.contains { $0.role == .socPeak } ? [.socPeak] : [])
        for role in roles {
            let matches = snapshot.sensors.filter { $0.role == role }
            guard matches.count == 1, let reading = matches.first,
                  reading.health == .valid || reading.health == .unverified,
                  let value = reading.celsius, value.isFinite, value > 0, value < ceilingC,
                  reading.sampledAt <= now, now - reading.sampledAt <= 2 else { throw ControlError.invalidSnapshot }
        }
    }
}
public enum MeasurementPhase: String, Codable, Sendable {
    case baseline, cpu, cpuCooldown, gpu, gpuCooldown, chassis
    public static func at(_ elapsed: Double) -> Self? {
        guard elapsed.isFinite, elapsed >= 0 else { return nil }
        switch elapsed {
        case ..<60: return .baseline
        case ..<90: return .cpu
        case ..<210: return .cpuCooldown
        case ..<240: return .gpu
        case ..<360: return .gpuCooldown
        case ..<660: return .chassis
        default: return nil
        }
    }
}
