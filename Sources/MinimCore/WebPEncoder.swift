import Foundation
import CoreGraphics
import ImageIO
import libwebp

/// 系统 ImageIO 只能解码 WebP 不能编码，编码走 libwebp。
/// 策略：同时生成「无损」与「有损(sharp YUV)」两个候选取更小者——
/// 扁平图形自然落到无损（清晰且通常比 PNG 小），照片落到有损（体积优势大）。
public enum WebPEncoder {
    public static func encode(
        source: URL, to destination: URL, preset: QualityPreset, resize: ResizeSpec? = nil
    ) throws {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              var image = CGImageSourceCreateImageAtIndex(src, 0, [
                  kCGImageSourceShouldCache: false,
              ] as CFDictionary)
        else {
            throw ExternalToolError(tool: "WebP", message: "无法解码 \(source.lastPathComponent)")
        }
        if let resize, let resized = ImageResizer.apply(resize, to: image) {
            image = resized
        }
        try encode(image: image, to: destination, preset: preset)
    }

    /// 编码已解码的单帧图像（动图导出单帧走这条，不需要再读一次文件）
    public static func encode(image: CGImage, to destination: URL, preset: QualityPreset) throws {
        let pixels = CGImagePixels.straightRGBA(of: image)
        let width = Int32(image.width)
        let height = Int32(image.height)

        let losslessData = try encodeData(
            pixels, width: width, height: height, lossless: true, quality: 75
        )
        if preset == .lossless {
            try losslessData.write(to: destination)
            return
        }
        let lossyData = try encodeData(
            pixels, width: width, height: height,
            lossless: false, quality: Float(preset.fixedJPEGQuality ?? 85)
        )
        try chooseCandidate(lossless: losslessData, lossy: lossyData).write(to: destination)
    }

    /// 无损体积不超过有损 4 倍就选无损（图形/UI 类实测在 3 倍内，杜绝模糊；
    /// 照片类无损通常大 5 倍以上，仍然落到有损）。
    /// originalSizeHint 非空时，无损候选还不得比源文件更大
    static func chooseCandidate(
        lossless: Data, lossy: Data, originalSizeHint: Int? = nil
    ) -> Data {
        let losslessFitsOriginal = originalSizeHint.map { lossless.count < $0 } ?? true
        if lossless.count <= lossy.count * losslessSizeRatioLimit, losslessFitsOriginal {
            return lossless
        }
        return lossy.count <= lossless.count ? lossy : lossless
    }

    static let losslessSizeRatioLimit = 4

    /// libwebp 高级 API 编码一帧
    static func encodeData(
        _ pixels: [UInt8], width: Int32, height: Int32,
        lossless: Bool, quality: Float
    ) throws -> Data {
        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0 else {
            throw ExternalToolError(tool: "WebP", message: "编码配置初始化失败")
        }
        if lossless {
            config.lossless = 1
            config.quality = quality        // 无损模式下代表压缩努力程度
        } else {
            config.quality = quality
            config.use_sharp_yuv = 1        // 锐化色度转换，避免硬边缘发糊
            config.method = 5
        }

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else {
            throw ExternalToolError(tool: "WebP", message: "画布初始化失败")
        }
        defer { WebPPictureFree(&picture) }
        picture.width = width
        picture.height = height
        picture.use_argb = 1

        let imported = pixels.withUnsafeBufferPointer {
            WebPPictureImportRGBA(&picture, $0.baseAddress, width * 4)
        }
        guard imported != 0 else {
            throw ExternalToolError(tool: "WebP", message: "像素导入失败")
        }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        picture.writer = WebPMemoryWrite
        let encoded = withUnsafeMutablePointer(to: &writer) { writerPtr -> Int32 in
            picture.custom_ptr = UnsafeMutableRawPointer(writerPtr)
            return WebPEncode(&config, &picture)
        }
        guard encoded != 0, writer.size > 0, let mem = writer.mem else {
            throw ExternalToolError(tool: "WebP", message: "编码失败（错误码 \(picture.error_code.rawValue)）")
        }
        return Data(bytes: mem, count: writer.size)
    }

}
