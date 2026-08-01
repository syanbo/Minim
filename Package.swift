// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Minim",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MinimCore", targets: ["MinimCore"]),
        .executable(name: "MinimApp", targets: ["MinimApp"]),
        .executable(name: "minim-cli", targets: ["MinimCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "MinimCore",
            dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")]
        ),
        .executableTarget(
            name: "MinimApp",
            dependencies: ["MinimCore"]
        ),
        .executableTarget(
            name: "MinimCLI",
            dependencies: ["MinimCore"]
        ),
        .testTarget(
            name: "MinimCoreTests",
            dependencies: ["MinimCore"]
        ),
    ]
)
