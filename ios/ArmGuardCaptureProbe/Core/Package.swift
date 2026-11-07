// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CaptureProbeCore",
    products: [
        .library(name: "CaptureProbeCore", targets: ["CaptureProbeCore"]),
        .executable(name: "CaptureProbeChecks", targets: ["CaptureProbeChecks"])
    ],
    targets: [
        .target(name: "CaptureProbeCore"),
        .executableTarget(name: "CaptureProbeChecks", dependencies: ["CaptureProbeCore"], path: "Checks")
    ]
)
