// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SibilDock",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SibilDock",
            path: "Sources/SibilDock",
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns", "Resources/MediaRemoteAdapter"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/SibilDock/Resources/Info.plist"
                ])
            ]
        )
    ]
)
