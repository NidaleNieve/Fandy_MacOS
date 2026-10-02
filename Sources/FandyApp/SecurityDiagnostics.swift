import Foundation
import FandyCore

/// Fixed invalid inputs only; no command-line payload, key, RPM or trust-policy selection.
enum ProductionSecurityProbe {
    enum Method { case begin, targets, recovery }
    struct Case { let name: String; let method: Method; let data: Data }
    static func cases() throws -> [Case] {
        let invalidJSON = Data("not JSON".utf8)
        let role = SensorRole.socPeak.rawValue
        var wrongVersion = LeaseRequest(generation: 1, required: [.socPeak]); wrongVersion.version = -1
        let forged = TargetRequest(leaseID: UUID(), generation: 1, snapshotID: UUID(), targets: [FanTarget(Int.max, 30_001)])
        return [
            Case(name: "malformedJSON", method: .begin, data: invalidJSON),
            Case(name: "oversizedJSON", method: .begin, data: Data(repeating: 32, count: Wire.maxBytes + 1)),
            Case(name: "unknownRole", method: .begin, data: Data("{\"version\":2,\"generation\":1,\"required\":[\"notASensor\"]}".utf8)),
            Case(name: "generationOverflow", method: .begin, data: Data("{\"version\":2,\"generation\":18446744073709551616,\"required\":[]}".utf8)),
            Case(name: "wrongVersion", method: .begin, data: try Wire.encode(wrongVersion)),
            Case(name: "callerAuthority", method: .begin, data: Data("{\"version\":2,\"generation\":1,\"required\":[\"\(role)\"],\"qualified\":true}".utf8)),
            Case(name: "forgedTarget", method: .targets, data: try Wire.encode(forged)),
            Case(name: "obsoleteQualification", method: .recovery, data: try Wire.encode(RecoveryTrialRequest(.initial)))
        ]
    }
}
