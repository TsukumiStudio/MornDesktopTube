// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MornDesktopTube",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MornDesktopTube", targets: ["MornDesktopTube"])],
    targets: [
        .executableTarget(name: "MornDesktopTube"),
        .testTarget(name: "MornDesktopTubeTests", dependencies: ["MornDesktopTube"], resources: [.copy("Fixtures")])
    ]
)
