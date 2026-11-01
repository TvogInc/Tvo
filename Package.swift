// swift-tools-version:5.9
// Builds the Mac menu bar app. The iPhone app is the Xcode project from project.yml.
import PackageDescription

let package = Package(
    name: "Googly",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GooglyMac", targets: ["GooglyMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "GooglyShared", path: "Shared", exclude: ["Fonts"]),
        .executableTarget(
            name: "GooglyMac",
            dependencies: [
                "GooglyShared",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Mac/Sources/GooglyMac"
        ),
    ]
)
