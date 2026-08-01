import XCTest
import CoreGraphics
@testable import MinimCore

final class ImageResizerTests: XCTestCase {

    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    func testClampedTargetFollowsOriginalRules() {
        let spec = ResizeSpec(width: 0, height: 5000, keepAspectRatio: true)
        // 0 → 原图宽；超过原图 → 原图高
        let target = spec.clampedTarget(originalWidth: 800, originalHeight: 600)
        XCTAssertEqual(target.width, 800)
        XCTAssertEqual(target.height, 600)
    }

    func testFitKeepsAspectRatio() {
        let image = makeImage(width: 800, height: 400)
        let result = ImageResizer.apply(
            ResizeSpec(width: 400, height: 400, keepAspectRatio: true), to: image
        )
        XCTAssertEqual(result?.width, 400)
        XCTAssertEqual(result?.height, 200)
    }

    func testCoverCropProducesExactSize() {
        let image = makeImage(width: 800, height: 400)
        let result = ImageResizer.apply(
            ResizeSpec(width: 300, height: 300, keepAspectRatio: false), to: image
        )
        XCTAssertEqual(result?.width, 300)
        XCTAssertEqual(result?.height, 300)
    }

    func testNoUpscaleReturnsNil() {
        let image = makeImage(width: 100, height: 100)
        // 目标大于原图：等比模式不放大，无需处理
        XCTAssertNil(ImageResizer.apply(
            ResizeSpec(width: 500, height: 500, keepAspectRatio: true), to: image
        ))
        XCTAssertNil(ImageResizer.apply(
            ResizeSpec(width: 500, height: 500, keepAspectRatio: false), to: image
        ))
    }
}
