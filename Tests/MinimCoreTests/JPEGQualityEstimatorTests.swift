import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MinimCore

final class JPEGQualityEstimatorTests: XCTestCase {

    /// 生成一张带渐变的测试图，用 ImageIO 以指定质量编码为 JPEG
    private func makeJPEG(quality: Double) throws -> Data {
        let width = 256, height = 256
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8(x % 256)
                pixels[i + 1] = UInt8(y % 256)
                pixels[i + 2] = UInt8((x + y) % 256)
                pixels[i + 3] = 255
            }
        }
        let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    func testParsesQuantizationTables() throws {
        let data = try makeJPEG(quality: 0.8)
        let tables = JPEGQualityEstimator.parseQuantizationTables(data)
        XCTAssertNotNil(tables)
        XCTAssertGreaterThanOrEqual(tables!.count, 1)
        XCTAssertEqual(tables![0].count, 64)
        XCTAssertTrue(tables![0].allSatisfy { $0 >= 1 && $0 <= 65535 })
    }

    /// Apple 编码器与 IJG 表不完全一致，只验证估计值单调且在合理区间
    func testEstimateIsMonotonicAndInRange() throws {
        let qualities = [0.3, 0.6, 0.9]
        var estimates: [Int] = []
        for q in qualities {
            let data = try makeJPEG(quality: q)
            let estimated = JPEGQualityEstimator.estimateQuality(of: data)
            XCTAssertNotNil(estimated)
            XCTAssertTrue((1...100).contains(estimated!))
            estimates.append(estimated!)
        }
        XCTAssertTrue(estimates[0] < estimates[1] && estimates[1] < estimates[2],
                      "估计值应随编码质量单调上升: \(estimates)")
    }

    func testIJGScalingFormula() {
        // q=50 时应等于标准表本身
        let base = [16, 11, 10, 99]
        XCTAssertEqual(JPEGQualityEstimator.scaled(base, quality: 50), base)
        // q=100 时全部为 1 或接近最小值
        XCTAssertTrue(JPEGQualityEstimator.scaled(base, quality: 100).allSatisfy { $0 >= 1 && $0 <= 2 })
    }

    func testAutoOutputQualityMapping() {
        XCTAssertEqual(JPEGQualityEstimator.autoOutputQuality(forEstimated: 50), 10)
        XCTAssertEqual(JPEGQualityEstimator.autoOutputQuality(forEstimated: 61), 10)
        XCTAssertEqual(JPEGQualityEstimator.autoOutputQuality(forEstimated: 80), 40)
        XCTAssertEqual(JPEGQualityEstimator.autoOutputQuality(forEstimated: 95), 85)
        XCTAssertEqual(JPEGQualityEstimator.autoOutputQuality(forEstimated: 100), 99)
        XCTAssertEqual(JPEGQualityEstimator.losslessOutputQuality(forEstimated: 99), 95)
        XCTAssertEqual(JPEGQualityEstimator.losslessOutputQuality(forEstimated: 70), 70)
    }

    func testRejectsNonJPEG() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0])
        XCTAssertNil(JPEGQualityEstimator.estimateQuality(of: png))
    }
}
