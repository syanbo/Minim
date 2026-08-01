import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum JPEGCompressor {
    /// 压缩 JPEG 到指定路径（可选裁剪缩放），返回实际使用的输出质量。
    /// 质量估算始终基于原文件，缩放不影响智能压缩判断
    @discardableResult
    public static func compress(
        source: URL, to destination: URL, preset: QualityPreset, resize: ResizeSpec? = nil
    ) throws -> Int {
        let quality: Int
        if let fixed = preset.fixedJPEGQuality {
            quality = fixed
        } else {
            let estimated = JPEGQualityEstimator.estimateQuality(of: source) ?? 85
            quality = preset == .lossless
                ? JPEGQualityEstimator.losslessOutputQuality(forEstimated: estimated)
                : JPEGQualityEstimator.autoOutputQuality(forEstimated: estimated)
        }
        try reencode(source: source, to: destination, quality: quality, resize: resize)
        return quality
    }

    /// 用 ImageIO 重编码，剥离 EXIF 等 metadata（保留方向）；
    /// 裁剪缩放在解码后、编码前一次完成，避免额外的有损中间产物
    static func reencode(
        source: URL, to destination: URL, quality: Int, resize: ResizeSpec? = nil
    ) throws {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              var image = CGImageSourceCreateImageAtIndex(src, 0, [
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary)
        else {
            throw ExternalToolError(tool: "ImageIO", message: "无法解码 \(source.lastPathComponent)")
        }
        if let resize, let resized = ImageResizer.apply(resize, to: image) {
            image = resized
        }

        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0,
        ]
        // 不拷贝 metadata 即剥离 EXIF，但方向要单独保留，否则图片会转向
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let orientation = props[kCGImagePropertyOrientation] {
            options[kCGImagePropertyOrientation] = orientation
        }

        guard let dest = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw ExternalToolError(tool: "ImageIO", message: "无法创建输出文件")
        }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ExternalToolError(tool: "ImageIO", message: "JPEG 编码失败")
        }
    }
}
