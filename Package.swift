// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GlassDock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GlassDock",
            path: "Sources/GlassDock",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        )
    ]
)
