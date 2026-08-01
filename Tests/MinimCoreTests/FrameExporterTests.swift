import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MinimCore

final class FrameExporterTests: XCTestCase {

    private var gif: URL!
    private var outputs: [URL] = []

    override func setUpWithError() throws {
        gif = FileManager.default.temporaryDirectory
            .appendingPathComponent("frame-export-\(UUID().uuidString).gif")
        try makeGIF(frames: 12, to: gif)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: gif)
        for url in outputs { try? FileManager.default.removeItem(at: url) }
        outputs = []
    }

    /// 每帧一个纯色，便于验证导出的是指定那一帧而不是第一帧
    private func makeGIF(frames: Int, to url: URL) throws {
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames, nil
        )!
        for i in 0..<frames {
            let context = CGContext(
                data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(CGColor(
                red: Double(i) / Double(frames), green: 0, blue: 0, alpha: 1
            ))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
            CGImageDestinationAddImage(dest, context.makeImage()!, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1],
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    private func destination(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("frame-out-\(UUID().uuidString).\(ext)")
        outputs.append(url)
        return url
    }

    func testFrameCount() {
        XCTAssertEqual(FrameExporter.frameCount(of: gif), 12)
    }

    func testSuggestedNameIsOneBasedAndPadded() {
        XCTAssertEqual(
            FrameExporter.suggestedName(
                source: URL(fileURLWithPath: "/tmp/loading.gif"),
                frameIndex: 2, frameCount: 12, format: .png
            ),
            "loading-frame-03.png"
        )
        // 位数跟随总帧数
        XCTAssertEqual(
            FrameExporter.suggestedName(
                source: URL(fileURLWithPath: "/tmp/loading.gif"),
                frameIndex: 9, frameCount: 120, format: .jpeg
            ),
            "loading-frame-010.jpg"
        )
    }

    func testExportPNGKeepsOriginalSize() throws {
        let out = destination("png")
        let size = try FrameExporter.export(
            source: gif, frameIndex: 5, format: .png, to: out
        )
        XCTAssertGreaterThan(size, 0)
        XCTAssertEqual(ImageFormat.detect(from: out), .png)
        XCTAssertFalse(AnimatedImage.isAnimated(out))
        let pixels = ImageResizer.pixelSize(of: out)
        XCTAssertEqual(pixels?.width, 40)
        XCTAssertEqual(pixels?.height, 30)
    }

    func testExportedFrameIsTheRequestedOne() throws {
        let out = destination("png")
        try FrameExporter.export(source: gif, frameIndex: 6, format: .png, to: out)
        // 第 6 帧（0 起）红色分量应为 6/12
        let exported = try FrameExporter.decodeFrame(source: out, index: 0)
        let source = try FrameExporter.decodeFrame(source: gif, index: 6)
        XCTAssertEqual(red(of: exported), red(of: source), accuracy: 2)
        XCTAssertNotEqual(
            red(of: exported), red(of: try FrameExporter.decodeFrame(source: gif, index: 0)),
            accuracy: 2
        )
    }

    func testExportJPEGAndWebP() throws {
        let jpg = destination("jpg")
        try FrameExporter.export(source: gif, frameIndex: 1, format: .jpeg, to: jpg)
        XCTAssertEqual(ImageFormat.detect(from: jpg), .jpeg)

        let webp = destination("webp")
        try FrameExporter.export(source: gif, frameIndex: 1, format: .webp, to: webp)
        // 单帧 WebP，不能是动图
        XCTAssertEqual(ImageFormat.detect(from: webp), .webp)
    }

    func testExportOverwritesExistingFile() throws {
        let out = destination("png")
        try Data("占位".utf8).write(to: out)
        try FrameExporter.export(source: gif, frameIndex: 0, format: .png, to: out)
        XCTAssertEqual(ImageFormat.detect(from: out), .png)
    }

    func testOutOfRangeIndexThrowsAndLeavesNoFile() {
        let out = destination("png")
        XCTAssertThrowsError(
            try FrameExporter.export(source: gif, frameIndex: 99, format: .png, to: out)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: out.path))
    }

    func testFormatDetectFromExtension() {
        XCTAssertEqual(FrameExporter.Format.detect(fileExtension: "PNG"), .png)
        XCTAssertEqual(FrameExporter.Format.detect(fileExtension: "jpeg"), .jpeg)
        XCTAssertEqual(FrameExporter.Format.detect(fileExtension: "webp"), .webp)
        XCTAssertNil(FrameExporter.Format.detect(fileExtension: "gif"))
    }

    /// 取左上角像素的红色分量（0-255）
    private func red(of image: CGImage) -> Double {
        let pixels = CGImagePixels.straightRGBA(of: image)
        return Double(pixels.first ?? 0)
    }
}
