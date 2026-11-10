// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwitchTab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SwitchTab",
            path: "Sources/SwitchTab",
            linkerSettings: [
                // SkyLight is needed to bring one specific window (not the whole app) to the front.
                .unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"])
            ]
        )
    ]
)
