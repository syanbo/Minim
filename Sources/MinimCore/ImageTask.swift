import Foundation
import UniformTypeIdentifiers

public enum ImageFormat: String, Sendable, CaseIterable {
    case png
    case jpeg
    case gif
    /// 多帧动图 WebP（静态 WebP 不支持输入）
    case webpAnimated
    /// APNG 动图（PNG 魔数 + 多帧）
    case apng

    public static func detect(from url: URL) -> ImageFormat? {
        // 先按魔数判断，扩展名兜底
        if let handle = try? FileHandle(forReadingFrom: url),
           let head = try? handle.read(upToCount: 12) {
            try? handle.close()
            if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                return AnimatedImage.isAnimated(url) ? .apng : .png
            }
            if head.starts(with: [0xFF, 0xD8]) { return .jpeg }
            if head.starts(with: [0x47, 0x49, 0x46]) { return .gif }
            if head.count >= 12,
               head.starts(with: [0x52, 0x49, 0x46, 0x46]),          // RIFF
               Array(head[8..<12]) == [0x57, 0x45, 0x42, 0x50] {     // WEBP
                return AnimatedImage.isAnimated(url) ? .webpAnimated : nil
            }
        }
        switch url.pathExtension.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "gif": return .gif
        default: return nil
        }
    }

    /// UI 展示名
    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .gif: "GIF"
        case .webpAnimated: "动图 WebP"
        case .apng: "APNG"
        }
    }

    public var preferredExtension: String {
        switch self {
        case .png, .apng: "png"
        case .jpeg: "jpg"
        case .gif: "gif"
        case .webpAnimated: "webp"
        }
    }
}

public struct CompressionResult: Sendable {
    public let outputURL: URL
    public let originalSize: Int64
    public let outputSize: Int64
    public let webpURL: URL?
    public let webpSize: Int64?
    /// 压缩后不比原图小，输出的是原文件的拷贝
    public let keptOriginal: Bool
    /// 自动转换格式产生的额外文件（如 basename-jpg.jpg）
    public let convertedURL: URL?
    public let convertedSize: Int64?

    /// 压缩率（节省比例，0-1）
    public var savedRatio: Double {
        guard originalSize > 0 else { return 0 }
        return 1 - Double(outputSize) / Double(originalSize)
    }

    public init(
        outputURL: URL, originalSize: Int64, outputSize: Int64,
        webpURL: URL? = nil, webpSize: Int64? = nil, keptOriginal: Bool = false,
        convertedURL: URL? = nil, convertedSize: Int64? = nil
    ) {
        self.outputURL = outputURL
        self.originalSize = originalSize
        self.outputSize = outputSize
        self.webpURL = webpURL
        self.webpSize = webpSize
        self.keptOriginal = keptOriginal
        self.convertedURL = convertedURL
        self.convertedSize = convertedSize
    }
}

public enum ImageTaskState: Sendable {
    /// 等待用户设置参数后手动开始（动图专用）
    case awaitingStart
    case pending
    case processing
    case done(CompressionResult)
    case failed(String)

    public var result: CompressionResult? {
        if case .done(let result) = self { result } else { nil }
    }

    public var isDone: Bool {
        result != nil
    }

    public var isAwaitingStart: Bool {
        if case .awaitingStart = self { true } else { false }
    }
}

public struct ImageTask: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let format: ImageFormat
    public let originalSize: Int64
    public var state: ImageTaskState
    /// 动图任务的独立参数（拖入时以全局设置为默认值）
    public var animConfig: AnimSettings?
    /// 上次执行时的完整设置快照（含动图参数，用于判断参数是否被修改、提示重试）
    public var lastRunSettings: CompressionSettings?

    public var isAnimated: Bool {
        format == .gif || format == .webpAnimated || format == .apng
    }

    public init?(sourceURL: URL) {
        guard let format = ImageFormat.detect(from: sourceURL) else { return nil }
        let size = sourceURL.fileSizeBytes
        guard size > 0 else { return nil }
        self.id = UUID()
        self.sourceURL = sourceURL
        self.format = format
        self.originalSize = size
        self.state = .pending
    }
}
