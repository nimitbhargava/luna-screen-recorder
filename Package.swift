// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Luna",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Luna", targets: ["Luna"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Luna",
            dependencies: [],
            path: "Sources/ScreenRecorder"
        )
    ]
)
