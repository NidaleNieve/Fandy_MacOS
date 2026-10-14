import Foundation
import Testing
import FandyCore
import FandyHardware
@testable import FandyApp

@MainActor @Test func initialSensorChoicesNeedOnlyCompiledIdentityAndNeverHardwareResolution() {
    let start = ContinuousClock.now
    let menu = SensorMenuModel(identity: .init(model: "Mac14,9", chip: "Apple M2 Pro", appleSilicon: true))
    #expect(menu.choices.count == SensorRole.allCases.count)
    #expect(menu.choices.first { $0.role == .airflowTop }?.name == "Top proximity")
    #expect(!menu.discovering && menu.discoveryError == nil)
    #expect(ContinuousClock.now - start < .milliseconds(50))
}
