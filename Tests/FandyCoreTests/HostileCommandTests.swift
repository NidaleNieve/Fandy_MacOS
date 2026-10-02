import Foundation
import Testing
@testable import FandyCore

@Test func productionCommandsRejectUnknownFieldsAndWrongContainers() throws {
    let bytes = try Wire.encode(LeaseRequest(generation: 1, required: SensorRole.safety))
    var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    #expect(try Wire.decodeCommand(LeaseRequest.self, from: bytes).generation == 1)
    for field in ["qualified", "duration", "rpm", "key", "path", "command"] {
        var bad = object; bad[field] = true
        #expect(throws: ControlError.malformedMessage) { try Wire.decodeCommand(LeaseRequest.self, from: JSONSerialization.data(withJSONObject: bad)) }
    }
    object.removeValue(forKey: "required")
    for bad in [Data("[]".utf8), Data("null".utf8), try JSONSerialization.data(withJSONObject: object)] {
        #expect(throws: ControlError.malformedMessage) { try Wire.decodeCommand(LeaseRequest.self, from: bad) }
    }
}

@Test func productionCommandNumbersCannotOverflowOrCoerceAuthority() {
    for generation in ["-1", "18446744073709551616", "1.5", "null", "true", "\"1\""] {
        let bytes = Data("{\"version\":2,\"generation\":\(generation),\"required\":[]}".utf8)
        #expect(throws: ControlError.malformedMessage) { try Wire.decodeCommand(LeaseRequest.self, from: bytes) }
    }
    for size in [0, Wire.maxBytes + 1] {
        #expect(throws: ControlError.malformedMessage) { try Wire.decodeCommand(LeaseRequest.self, from: Data(repeating: 32, count: size)) }
    }
}

@Test func productionTargetCommandRequiresOnlyItsClosedShape() throws {
    let request = TargetRequest(leaseID: UUID(), generation: 1, snapshotID: UUID(), targets: [FanTarget(0, 3000)])
    let bytes = try Wire.encode(request)
    #expect(try Wire.decodeCommand(TargetRequest.self, from: bytes).targets == request.targets)
    var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any]); object["authority"] = "root"
    #expect(throws: ControlError.malformedMessage) { try Wire.decodeCommand(TargetRequest.self, from: JSONSerialization.data(withJSONObject: object)) }
}

@Test func strangersCannotRenewOrRevokeTheOwnersLease() throws {
    let spy = FanSpy(); let (coordinator, lease, owner) = try leasedCoordinator(spy)
    let snapshot = try #require(coordinator.status().snapshot)
    try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id,
        targets: [FanTarget(0, 3000), FanTarget(1, 3000)]), owner: owner)
    let calls = spy.calls
    let stranger = UUID()
    #expect(throws: (any Error).self) {
        try coordinator.apply(TargetRequest(leaseID: lease.id, generation: 1, snapshotID: snapshot.id,
            targets: [FanTarget(0, 3100), FanTarget(1, 3100)]), owner: stranger)
    }
    coordinator.reject(owner: stranger); coordinator.disconnected(owner: stranger)
    #expect(spy.calls == calls); #expect(spy.fans.allSatisfy { $0.mode == .manual })
    spy.now += 10; coordinator.watchdog()
    #expect(spy.fans.allSatisfy { $0.mode == .automatic })
}
