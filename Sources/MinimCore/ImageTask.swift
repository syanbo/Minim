import Foundation
import UniformTypeIdentifiers

public enum ImageFormat: String, Sendable, CaseIterable {
    case png
    case jpeg
    case gif
    /// 单帧静态 WebP
    case webp
    /// 多帧动图 WebP
    case webpAnimated
    /// APNG 动图（PNG 魔数 + 多帧）
    case apng

    public static func detect(from url: URL) -> ImageFormat? {
        // 先按魔数判断，扩展名兜底
        if let handle = try? FileHandle(forReadingFrom: url),
           let head = try? handle.read(upToCount: 30) {
            try? handle.close()
            if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                return AnimatedImage.isAnimated(url) ? .apng : .png
            }
            if head.starts(with: [0xFF, 0xD8]) { return .jpeg }
            if head.starts(with: [0x47, 0x49, 0x46]) { return .gif }
            if head.count >= 12,
               head.starts(with: [0x52, 0x49, 0x46, 0x46]),          // RIFF
               Array(head[8..<12]) == [0x57, 0x45, 0x42, 0x50] {     // WEBP
                // 容器自己声明的动画标志优先于 ImageIO 的帧数：
                // CGImageSourceGetCount 对部分动图 WebP 会返回 1，
                // 误判成静态会把动画压成单帧且不可恢复
                if webpDeclaresAnimation(head) { return .webpAnimated }
                return AnimatedImage.isAnimated(url) ? .webpAnimated : .webp
            }
        }
        // 兜底不含 webp：读不到魔数就无法区分动/静，误判会走错处理路径
        switch url.pathExtension.lowercased() {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "gif": return .gif
        default: return nil
        }
    }

    /// 扩展格式（VP8X）的 flags 字节 bit1 = ANIM。
    /// 布局：RIFF(4) size(4) WEBP(4) "VP8X"(4) chunkSize(4) flags(1)…
    static func webpDeclaresAnimation(_ head: Data) -> Bool {
        let bytes = [UInt8](head)
        guard bytes.count >= 21,
              Array(bytes[12..<16]) == [0x56, 0x50, 0x38, 0x58]  // "VP8X"
        else { return false }
        return bytes[20] & 0x02 != 0
    }

    /// UI 展示名
    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .gif: "GIF"
        case .webp: "WebP"
        case .webpAnimated: "动图 WebP"
        case .apng: "APNG"
        }
    }

    public var preferredExtension: String {
        switch self {
        case .png, .apng: "png"
        case .jpeg: "jpg"
        case .gif: "gif"
        case .webp, .webpAnimated: "webp"
        }
    }

    /// 多帧格式。静态/动图的划分只在这里定义一次，
    /// 别在别处用 `format == .gif` 之类的条件手工展开这个集合
    public var isAnimated: Bool {
        switch self {
        case .gif, .webpAnimated, .apng: true
        case .png, .jpeg, .webp: false
        }
    }
}

/// 转换开关产生的额外输出（如 basename-jpg.jpg），不替换主输出
public struct ConvertedOutput: Sendable, Hashable, Identifiable {
    public let target: ConversionTarget
    public let url: URL
    public let size: Int64

    public init(target: ConversionTarget, url: URL, size: Int64) {
        self.target = target
        self.url = url
        self.size = size
    }

    public var id: URL { url }
    /// 展示用标签，直接来自目标类型（不从文件名反推）
    public var label: String { target.label }
}

public struct CompressionResult: Sendable {
    public let outputURL: URL
    public let originalSize: Int64
    public let outputSize: Int64
    /// 压缩后不比原图小，输出的是原文件的拷贝
    public let keptOriginal: Bool
    /// 转换开关产生的额外文件，可同时有多个（WebP / JPG / PNG 三者地位相同）
    public let converted: [ConvertedOutput]

    /// 压缩率（节省比例，0-1）
    public var savedRatio: Double {
        guard originalSize > 0 else { return 0 }
        return 1 - Double(outputSize) / Double(originalSize)
    }

    public init(
        outputURL: URL, originalSize: Int64, outputSize: Int64,
        keptOriginal: Bool = false, converted: [ConvertedOutput] = []
    ) {
        self.outputURL = outputURL
        self.originalSize = originalSize
        self.outputSize = outputSize
        self.keptOriginal = keptOriginal
        self.converted = converted
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

    public var isAnimated: Bool { format.isAnimated }

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
