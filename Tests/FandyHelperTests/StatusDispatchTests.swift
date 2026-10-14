import Foundation
import Testing
import FandyCore
@testable import FandyHelper

@Test func productionStatusDispatchBypassesBlockedHardwareWork() async throws {
    let service = HelperService(), connection = HelperConnection(service: service)
    #expect(service.requests.connect(owner: connection.owner))
    var status = HelperStatus(automaticVerified: false, bootstrap: .init())
    status.helperBuild = FandyBuild.identifier
    service.statusCache.publish(status, at: 10)
    let block = DispatchSemaphore(value: 0)
    await withCheckedContinuation { entered in service.queue.async { entered.resume(); block.wait() } }
    defer { block.signal() }
    let began = Date()
    let reply: Data = try await withCheckedThrowingContinuation { continuation in
        connection.status { data, error in
            if let data, error == nil { continuation.resume(returning: data) }
            else { continuation.resume(throwing: ControlError.helperUnavailable) }
        }
    }
    #expect(Date().timeIntervalSince(began) < 0.25)
    let decoded = try Wire.decode(HelperStatus.self, from: reply)
    #expect(decoded.helperBuild == FandyBuild.identifier && decoded.bootstrap?.stage == .initializing)
}
