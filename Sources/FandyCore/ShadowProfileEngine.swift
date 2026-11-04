import Foundation

/// Display-only demand and input provenance.
public struct ProfilePreview: Sendable, Equatable {
    public let profileID: String
    public let snapshotID: UUID
    public let percent: Double
    public let safetyPercent: Double
    public let byCurve: [CurveInput: Double]
    public let targetPercent: Double?
    public let usesCandidates: Bool
}
public enum ShadowProfileEngine {
    public static func evaluate(_ profile: Profile, snapshot: HardwareSnapshot, now: Double, chipPolicy: ChipControlPolicy = .cpuGPU) throws -> ProfilePreview {
        var informational = snapshot
        let candidates = snapshot.sensors.contains { profile.requiredSensors(chipPolicy: chipPolicy).contains($0.role) && $0.health == .unverified }
        // Promote candidates only in this preview copy, never in a control snapshot.
        for index in informational.sensors.indices where informational.sensors[index].health == .unverified {
            informational.sensors[index].health = .valid
        }
        let demand = try ProfileEngine().evaluate(profile, snapshot: informational, now: now, chipPolicy: chipPolicy)
        return ProfilePreview(profileID: profile.id, snapshotID: snapshot.id, percent: demand.percent,
                              safetyPercent: demand.safetyPercent, byCurve: demand.byCurve, targetPercent: demand.targetPercent, usesCandidates: candidates)
    }
}
