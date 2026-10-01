import Foundation
import CSMC
public struct HIDTemperature: Codable, Sendable { public var name: String; public var celsius: Double }
public enum HIDTemperatureReader {
    public static func read() -> [HIDTemperature] {
        guard let values = fandy_hid_temperatures() as? [[String: Any]] else { return [] }
        return values.compactMap { value in
            guard let name=value["name"] as? String, let celsius=value["celsius"] as? Double, celsius.isFinite, celsius>0,celsius<150 else { return nil }
            return HIDTemperature(name:name,celsius:celsius)
        }
    }
}
