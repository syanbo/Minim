import XCTest
@testable import MinimCore

/// 三个转换开关的适用性规则与命名规则。
/// 这些以前只靠人工端到端验证，加格式时没有任何测试会失败来提示行为变化
final class ConversionTargetTests: XCTestCase {

    /// 同格式不产出候选——否则候选与主输出同名，会把主输出覆盖掉
    func testNeverTargetsItsOwnFormat() {
        XCTAssertFalse(ConversionTarget.webp.applies(to: .webp))
        XCTAssertFalse(ConversionTarget.jpeg.applies(to: .jpeg))
        XCTAssertFalse(ConversionTarget.png.applies(to: .png))
    }

    /// 动图一律不适用：三个开关都只针对静态图
    func testAnimatedInputsNeverApply() {
        for format in [ImageFormat.gif, .webpAnimated, .apng] {
            for target in ConversionTarget.allCases {
                XCTAssertFalse(
                    target.applies(to: format),
                    "\(target) 不应对动图 \(format) 生效"
                )
            }
        }
    }

    /// 静态图之间两两互转
    func testStaticCrossFormatCombinations() {
        XCTAssertTrue(ConversionTarget.webp.applies(to: .png))
        XCTAssertTrue(ConversionTarget.webp.applies(to: .jpeg))
        XCTAssertTrue(ConversionTarget.jpeg.applies(to: .png))
        XCTAssertTrue(ConversionTarget.jpeg.applies(to: .webp))
        XCTAssertTrue(ConversionTarget.png.applies(to: .jpeg))
        XCTAssertTrue(ConversionTarget.png.applies(to: .webp))
    }

    /// 每种静态输入恰好产出两个候选（全开时）
    func testEachStaticFormatYieldsTwoCandidates() {
        for format in [ImageFormat.png, .jpeg, .webp] {
            let applicable = ConversionTarget.allCases.filter { $0.applies(to: format) }
            XCTAssertEqual(applicable.count, 2, "\(format) 应有 2 个可用转换目标")
        }
    }

    func testNamingRules() {
        XCTAssertEqual(ConversionTarget.jpeg.nameSuffix, "-jpg")
        XCTAssertEqual(ConversionTarget.png.nameSuffix, "-png")
        XCTAssertEqual(ConversionTarget.jpeg.fileExtension, "jpg")
        XCTAssertEqual(ConversionTarget.png.fileExtension, "png")
        XCTAssertEqual(ConversionTarget.webp.fileExtension, "webp")
    }

    /// fileExtension 必须与 ImageFormat.preferredExtension 对齐，
    /// 否则 applies(to:) 的「目标 ≠ 输入自身」判断会失效
    func testExtensionsAlignWithImageFormat() {
        XCTAssertEqual(ConversionTarget.webp.fileExtension, ImageFormat.webp.preferredExtension)
        XCTAssertEqual(ConversionTarget.jpeg.fileExtension, ImageFormat.jpeg.preferredExtension)
        XCTAssertEqual(ConversionTarget.png.fileExtension, ImageFormat.png.preferredExtension)
    }

    /// WebP 候选与静态 WebP 输入共用 `<原名>.webp`——这正是覆盖用户源文件的根因，
    /// 冲突预判必须与实际落盘用同一个路径函数
    func testWebPCandidateCollidesWithWebPInputPath() {
        let source = URL(fileURLWithPath: "/tmp/pics/logo.png")
        let output = URL(fileURLWithPath: "/tmp/pics/minim/logo.png")
        let webpTarget = CompressionEngine.candidateURL(.webp, source: source, outputURL: output)

        XCTAssertEqual(webpTarget.lastPathComponent, "logo.webp")
        XCTAssertEqual(webpTarget.deletingLastPathComponent(), output.deletingLastPathComponent())
        // JPG / PNG 带后缀，不会与任何同名输入撞车
        XCTAssertEqual(
            CompressionEngine.candidateURL(.jpeg, source: source, outputURL: output)
                .lastPathComponent, "logo-jpg.jpg"
        )
        XCTAssertEqual(
            CompressionEngine.candidateURL(.png, source: source, outputURL: output)
                .lastPathComponent, "logo-png.png"
        )
    }

    /// 覆盖模式下 WebP 候选的目标就是源文件所在目录，必须靠 protectedPaths 兜住
    func testOverwriteModeWebPCandidateLandsNextToSource() {
        let source = URL(fileURLWithPath: "/tmp/pics/logo.png")
        let target = CompressionEngine.candidateURL(.webp, source: source, outputURL: source)
        XCTAssertEqual(target, URL(fileURLWithPath: "/tmp/pics/logo.webp"))
    }

    func testRawValuesAreStableForPersistence() {
        // UserDefaults 里存的是 rawValue，改动会让用户设置丢失
        XCTAssertEqual(ConversionTarget.webp.rawValue, "webp")
        XCTAssertEqual(ConversionTarget.jpeg.rawValue, "jpeg")
        XCTAssertEqual(ConversionTarget.png.rawValue, "png")
        XCTAssertEqual(ConversionTarget(rawValue: "jpeg"), .jpeg)
        XCTAssertNil(ConversionTarget(rawValue: "avif"))
    }
}
