// swift-tools-version:6.0
// 需要 Swift 6 工具链——代码用到了 count(where:) 等 6.0 才有的标准库 API。
// 但语言模式仍保持 v5（见文件末尾 swiftLanguageModes）：
// 切到 v6 会开启严格并发检查，需要先把 AnimatedImage.Animation 等类型改成 Sendable，
// 那是一次独立的重构，不该混在构建配置里做
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
    ],
    swiftLanguageModes: [.v5]
)
