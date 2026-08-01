import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 动图单帧导出：把动图的某一帧按**原始分辨率**存成静态图。
/// 与压缩流水线无关——导出是「取素材」，默认偏保真，不做抽帧/调速那套变换
public enum FrameExporter {

    /// 导出格式（保存面板的可选类型也来自这里）
    public enum Format: String, Sendable, CaseIterable, Identifiable {
        case png
        case jpeg
        case webp

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .png: "PNG"
            case .jpeg: "JPG"
            case .webp: "WebP"
            }
        }

        public var fileExtension: String {
            switch self {
            case .png: "png"
            case .jpeg: "jpg"
            case .webp: "webp"
            }
        }

        public var contentType: UTType {
            switch self {
            case .png: .png
            case .jpeg: .jpeg
            case .webp: .webP
            }
        }

        /// 按扩展名反查：保存面板里用户可以手改文件名，格式以最终扩展名为准
        public static func detect(fileExtension: String) -> Format? {
            switch fileExtension.lowercased() {
            case "png": .png
            case "jpg", "jpeg": .jpeg
            case "webp": .webp
            default: nil
            }
        }
    }

    /// 导出单帧默认的 JPG 质量：素材用途，比压缩流水线的候选更保真
    public static let defaultJPEGQuality = 92

    /// 源文件的帧数；非动图返回 nil
    public static func frameCount(of source: URL) -> Int? {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else { return nil }
        let count = CGImageSourceGetCount(src)
        return count > 1 ? count : nil
    }

    /// 建议文件名：`<原名>-frame-03.png`。
    /// frameIndex 从 0 开始，文件名里用从 1 开始的序号（与界面「第 N 帧」一致），
    /// 序号按总帧数补零，方便按名排序
    public static func suggestedName(
        source: URL, frameIndex: Int, frameCount: Int, format: Format
    ) -> String {
        let digits = max(2, String(max(frameCount, 1)).count)
        let number = String(format: "%0\(digits)d", frameIndex + 1)
        let base = source.deletingPathExtension().lastPathComponent
        return "\(base)-frame-\(number).\(format.fileExtension)"
    }

    /// 解码指定帧（原始分辨率）。index 从 0 开始
    public static func decodeFrame(source: URL, index: Int) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw ExternalToolError(
                tool: "导出帧", message: "无法读取 \(source.lastPathComponent)"
            )
        }
        let count = CGImageSourceGetCount(src)
        guard index >= 0, index < count else {
            throw ExternalToolError(tool: "导出帧", message: "帧序号超出范围（共 \(count) 帧）")
        }
        guard let image = CGImageSourceCreateImageAtIndex(src, index, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else {
            throw ExternalToolError(tool: "导出帧", message: "第 \(index + 1) 帧解码失败")
        }
        return image
    }

    /// 导出某一帧到指定文件，返回产物字节数。
    /// 先写临时文件再落位，编码失败不会在目标路径留下半截文件
    @discardableResult
    public static func export(
        source: URL, frameIndex: Int, format: Format,
        quality: QualityPreset = .auto, to destination: URL
    ) throws -> Int64 {
        let image = try decodeFrame(source: source, index: frameIndex)
        let fm = FileManager.default
        let temp = fm.temporaryDirectory
            .appendingPathComponent("minim-frame-\(UUID().uuidString)")
            .appendingPathExtension(format.fileExtension)
        defer { try? fm.removeItem(at: temp) }

        switch format {
        case .png:
            try ImageResizer.writePNG(image, to: temp)
        case .jpeg:
            // JPG 不支持透明，动图常有透明背景，先平铺到白底
            let flattened = hasAlpha(image) ? FormatConverter.flattenOnWhite(image) : image
            try FormatConverter.writeJPEG(
                flattened, to: temp,
                quality: quality.fixedJPEGQuality ?? defaultJPEGQuality
            )
        case .webp:
            try WebPEncoder.encode(image: image, to: temp, preset: quality)
        }

        guard temp.fileSizeBytes > 0 else {
            throw ExternalToolError(tool: "导出帧", message: "\(format.label) 编码失败")
        }
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: temp, to: destination)
        return destination.fileSizeBytes
    }

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }
}
