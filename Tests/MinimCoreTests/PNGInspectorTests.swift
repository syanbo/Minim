import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MinimCore

final class PNGInspectorTests: XCTestCase {

    private func makePNG(alpha: Bool) -> Data {
        let width = 16, height = 16
        var pixels = [UInt8](repeating: alpha ? 128 : 255, count: width * height * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 200
        }
        let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: (alpha
                ? CGImageAlphaInfo.premultipliedLast
                : CGImageAlphaInfo.noneSkipLast).rawValue
        )!
        let image = context.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    func testParsesIHDR() {
        let info = PNGInspector.inspect(makePNG(alpha: true))
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.width, 16)
        XCTAssertEqual(info?.height, 16)
        XCTAssertEqual(info?.bitDepth, 8)
        XCTAssertEqual(info?.hasAlphaChannel, true)
        XCTAssertEqual(info?.isIndexed, false)
    }

    func testRejectsNonPNG() {
        XCTAssertNil(PNGInspector.inspect(Data([0xFF, 0xD8, 0xFF])))
        XCTAssertNil(PNGInspector.inspect(Data()))
    }
}
