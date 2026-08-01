import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 自动转换格式（复刻原版 isTypeChange）：
/// - 无透明像素的 PNG → 候选 JPG，比压缩后的 PNG 小才保留
/// - 颜色数 ≤ 30000 的 JPG（疑似图形类误存）→ 候选无损 PNG，更小才保留
/// 转换产物是额外文件（basename-jpg.jpg / basename-png.png），不替换主输出
public enum FormatConverter {

    /// jpg→png 允许转换的颜色数上限（原版阈值）
    public static let jpegToPNGColorLimit = 30_000

    public struct Analysis: Sendable {
        public let width: Int
        public let height: Int
        public let hasTransparency: Bool
        /// 不同颜色值数量，超过 30001 截断（阈值判断够用）
        public let uniqueColors: Int
        public var area: Int { width * height }
    }

    /// 解码（含裁剪缩放）并统计透明度与颜色数；返回像素分析和解码后的图像
    public static func analyze(source: URL, resize: ResizeSpec?) -> (image: CGImage, analysis: Analysis)? {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              var image = CGImageSourceCreateImageAtIndex(src, 0, [
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary)
        else { return nil }
        if let resize, let resized = ImageResizer.apply(resize, to: image) {
            image = resized
        }

        let width = image.width
        let height = image.height
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        guard let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: stride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hasTransparency = false
        var colors = Set<UInt32>()
        let colorCap = jpegToPNGColorLimit + 1
        pixels.withUnsafeBytes { raw in
            let words = raw.bindMemory(to: UInt32.self)
            for word in words {
                // RGBA 小端内存里 alpha 在最高字节
                if word & 0xFF00_0000 != 0xFF00_0000 { hasTransparency = true }
                if colors.count < colorCap { colors.insert(word) }
            }
        }
        return (image, Analysis(
            width: width, height: height,
            hasTransparency: hasTransparency,
            uniqueColors: colors.count
        ))
    }

    /// 把带透明的图像平铺到白底（转 JPG 前用，JPG 不支持透明）
    public static func flattenOnWhite(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// png→jpg 候选质量（复刻原版启发式 + 档位偏移）
    public static func pngToJPEGQuality(analysis: Analysis, preset: QualityPreset) -> Int {
        var quality = 93
        if analysis.uniqueColors > 10_000 { quality = 90 }
        if analysis.area > 1024 * 1024 || analysis.uniqueColors > 30_000 {
            quality = analysis.uniqueColors < 3_000 ? 92 : 90
        }
        quality -= preset.conversionQualityAdjustment
        return min(max(quality, 10), 99)
    }

    /// 把已解码图像编码为 JPEG 候选文件
    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Int) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw ExternalToolError(tool: "ImageIO", message: "无法创建 JPEG 输出")
        }
        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ExternalToolError(tool: "ImageIO", message: "JPEG 编码失败")
        }
    }
}
