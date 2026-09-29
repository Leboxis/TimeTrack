// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WellbeingCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "WellbeingCore", targets: ["WellbeingCore"])],
    targets: [
        .target(name: "WellbeingCore"),
        .testTarget(name: "WellbeingCoreTests", dependencies: ["WellbeingCore"])
    ]
)
