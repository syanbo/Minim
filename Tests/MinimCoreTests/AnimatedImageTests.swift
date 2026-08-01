import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MinimCore

final class AnimatedImageTests: XCTestCase {

    private var tempGIF: URL!

    override func setUpWithError() throws {
        tempGIF = FileManager.default.temporaryDirectory
            .appendingPathComponent("anim-test-\(UUID().uuidString).gif")
        try makeGIF(frames: 10, delaySeconds: 0.1, loopCount: 2, to: tempGIF)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempGIF)
    }

    private func makeGIF(frames: Int, delaySeconds: Double, loopCount: Int, to url: URL) throws {
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames, nil
        )!
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount],
        ] as CFDictionary)
        for i in 0..<frames {
            let context = CGContext(
                data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(CGColor(
                red: Double(i) / Double(frames), green: 0.4, blue: 0.8, alpha: 1
            ))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            CGImageDestinationAddImage(dest, context.makeImage()!, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delaySeconds,
                    kCGImagePropertyGIFUnclampedDelayTime: delaySeconds,
                ],
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    func testProbeInfo() {
        let info = AnimatedImage.probe(tempGIF)
        XCTAssertEqual(info?.frameCount, 10)
        XCTAssertEqual(info?.width, 64)
        XCTAssertEqual(info?.height, 64)
        XCTAssertEqual(info?.durationMs, 1000)
        XCTAssertEqual(info?.loopCount, 2)
        XCTAssertEqual(info?.summary, "10 帧 · 10 fps · 1.0 秒 · 循环 2 次 · 64×64")
    }

    func testDecodeFramesAndLoop() {
        XCTAssertTrue(AnimatedImage.isAnimated(tempGIF))
        let anim = AnimatedImage.decode(tempGIF)
        XCTAssertEqual(anim?.frames.count, 10)
        XCTAssertEqual(anim?.loopCount, 2)
        XCTAssertEqual(anim?.totalDurationMs, 1000)
    }

    func testDecimateKeepsDuration() {
        let anim = AnimatedImage.decode(tempGIF)!
        // 每 3 帧保留 2：删掉帧 2,5,8，剩 7 帧
        let decimated = AnimatedImage.decimate(anim, keep: FrameKeep(keep: 2, outOf: 3))
        XCTAssertEqual(decimated.frames.count, 7)
        XCTAssertEqual(decimated.totalDurationMs, 1000)    // 总时长不变
        // 每 2 帧保留 1：剩一半
        XCTAssertEqual(
            AnimatedImage.decimate(anim, keep: FrameKeep(keep: 1, outOf: 2)).frames.count, 5
        )
        // 激进档位：10 帧每 4 帧保留 1 → 帧 0,4,8
        let sparse = AnimatedImage.decimate(anim, keep: FrameKeep(keep: 1, outOf: 4))
        XCTAssertEqual(sparse.frames.count, 3)
        XCTAssertEqual(sparse.totalDurationMs, 1000)
        // 不抽帧
        XCTAssertEqual(AnimatedImage.decimate(anim, keep: .all).frames.count, 10)
    }

    func testProbeFPS() {
        let info = AnimatedImage.probe(tempGIF)!
        // 10 帧 / 1 秒
        XCTAssertEqual(info.fps, 10, accuracy: 0.01)
        XCTAssertTrue(info.summary.contains("10 fps"), info.summary)
    }

    func testEncodeAnimatedWebP() throws {
        let anim = AnimatedImage.decode(tempGIF)!
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("anim-test-\(UUID().uuidString).webp")
        defer { try? FileManager.default.removeItem(at: out) }
        try AnimEncoder.encodeWebP(anim, loopCount: 3, preset: .p80, to: out)

        XCTAssertEqual(ImageFormat.detect(from: out), .webpAnimated)
        let decoded = AnimatedImage.decode(out)
        XCTAssertEqual(decoded?.frames.count, 10)
        XCTAssertEqual(decoded?.loopCount, 3)
        XCTAssertEqual(decoded?.frames.first?.image.width, 64)
    }

    func testEncodeAPNG() async throws {
        let anim = AnimatedImage.decode(tempGIF)!
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("anim-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: out) }
        try await AnimEncoder.encodeAPNG(anim, loopCount: 0, preset: .lossless, to: out)

        let decoded = AnimatedImage.decode(out)
        XCTAssertEqual(decoded?.frames.count, 10)
        XCTAssertEqual(decoded?.loopCount, 0)
        // APNG 应被识别为动图格式而非静态 PNG
        XCTAssertEqual(ImageFormat.detect(from: out), .apng)
    }

    func testStaticImageReturnsNil() {
        let png = FileManager.default.temporaryDirectory
            .appendingPathComponent("static-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: png) }
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let dest = CGImageDestinationCreateWithURL(
            png as CFURL, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, context.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        XCTAssertFalse(AnimatedImage.isAnimated(png))
        XCTAssertNil(AnimatedImage.decode(png))
    }
}
