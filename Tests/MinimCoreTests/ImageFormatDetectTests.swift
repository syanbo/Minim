import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MinimCore

/// 格式识别：静态 WebP 与动图 WebP 必须区分开，
/// 否则静图会被送进动图转换流程（或反过来被静默丢弃）
final class ImageFormatDetectTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        scratch.forEach { try? FileManager.default.removeItem(at: $0) }
        scratch = []
    }

    private func temp(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fmt-\(UUID().uuidString).\(ext)")
        scratch.append(url)
        return url
    }

    /// tint 用来让各帧内容不同——动图编码器开了 minimize_size，
    /// 完全相同的帧会被合并成单帧，编出来就不再是动图了
    private func solidImage(_ size: Int = 32, tint: Double = 0.2) -> CGImage {
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: tint, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    private func writePNG() throws -> URL {
        let url = temp("png")
        try ImageResizer.writePNG(solidImage(), to: url)
        return url
    }

    private func writeAnimatedGIF(frames: Int = 6) throws -> URL {
        let url = temp("gif")
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames, nil
        )!
        for i in 0..<frames {
            CGImageDestinationAddImage(dest, solidImage(tint: Double(i) / Double(frames)), [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1],
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    // MARK: -

    func testStaticWebPIsDetectedAsStaticWebP() throws {
        let webp = temp("webp")
        try WebPEncoder.encode(source: try writePNG(), to: webp, preset: .p80)

        XCTAssertEqual(ImageFormat.detect(from: webp), .webp)
        XCTAssertEqual(ImageFormat.webp.preferredExtension, "webp")
        XCTAssertEqual(ImageFormat.webp.displayName, "WebP")
    }

    func testAnimatedWebPIsStillDetectedAsAnimated() throws {
        let anim = AnimatedImage.decode(try writeAnimatedGIF())!
        let webp = temp("webp")
        try AnimEncoder.encodeWebP(anim, loopCount: 0, preset: .p80, to: webp)

        XCTAssertEqual(ImageFormat.detect(from: webp), .webpAnimated)
    }

    /// 静态 WebP 走静图流程：不能被当成动图，否则会要求用户手动点「开始」
    func testStaticWebPTaskIsNotAnimated() throws {
        let webp = temp("webp")
        try WebPEncoder.encode(source: try writePNG(), to: webp, preset: .p80)

        let task = try XCTUnwrap(ImageTask(sourceURL: webp))
        XCTAssertEqual(task.format, .webp)
        XCTAssertFalse(task.isAnimated)
        // 静图不走动图转换分支
        XCTAssertNil(AnimOutputFormat.webp.resolved(for: .webp))
    }

    /// 扩展名兜底刻意不认 webp：读不到魔数时无法区分动/静，宁可判为不支持
    func testWebPExtensionWithoutMagicIsRejected() throws {
        let fake = temp("webp")
        try Data(repeating: 0x00, count: 64).write(to: fake)

        XCTAssertNil(ImageFormat.detect(from: fake))
    }

    func testOtherFormatsUnaffected() throws {
        XCTAssertEqual(ImageFormat.detect(from: try writePNG()), .png)
        XCTAssertEqual(ImageFormat.detect(from: try writeAnimatedGIF()), .gif)
    }
}
