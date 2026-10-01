// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Fandy", platforms: [.macOS(.v15)],
    products: [.library(name: "FandyCore", targets: ["FandyCore"]), .library(name: "FandyHardware", targets: ["FandyHardware"]), .executable(name: "Fandy", targets: ["FandyApp"]), .executable(name: "fandy-discover", targets: ["FandyDiscovery"]), .executable(name: "FandyFanHelper", targets: ["FandyHelper"]), .executable(name: "fandy-measure", targets: ["FandyMeasurement"])],
    targets: [
        .target(name: "FandyCore"),
        .target(name: "CSMC", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "FandyHardware", dependencies: ["FandyCore", "CSMC"]),
        .executableTarget(name: "FandyApp", dependencies: ["FandyCore", "FandyHardware"], linkerSettings: [.linkedFramework("ServiceManagement")]),
        .executableTarget(name: "FandyDiscovery", dependencies: ["FandyHardware"]),
        .executableTarget(name: "FandyHelper", dependencies: ["FandyCore", "FandyHardware"], linkerSettings: [.linkedFramework("Security")]),
        .executableTarget(name: "FandyMeasurement", dependencies: ["FandyCore", "FandyHardware"], linkerSettings: [.linkedFramework("Metal")]),
        .testTarget(name: "FandyAppTests", dependencies: ["FandyApp"]),
        .testTarget(name: "FandyCoreTests", dependencies: ["FandyCore"]),
        .testTarget(name: "FandyHardwareTests", dependencies: ["FandyHardware"])
    ]
)
