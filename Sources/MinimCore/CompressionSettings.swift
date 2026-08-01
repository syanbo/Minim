import Foundation

/// 质量档位：10% / 30% / 50% / 80% / 默认 / 保真
public enum QualityPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case p10
    case p30
    case p50
    case p80
    case auto
    case lossless

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .p10: "10%"
        case .p30: "30%"
        case .p50: "50%"
        case .p80: "80%"
        case .auto: "默认"
        case .lossless: "保真"
        }
    }

    /// 固定档位对应的 JPEG 输出质量（1-100）；auto/lossless 由质量检测决定
    public var fixedJPEGQuality: Int? {
        switch self {
        case .p10: 10
        case .p30: 30
        case .p50: 50
        case .p80: 80
        case .auto, .lossless: nil
        }
    }

    /// pngquant 的 --quality min-max 参数；lossless 返回 nil（只走无损）
    public var pngquantQualityRange: (min: Int, max: Int)? {
        switch self {
        case .p10: (0, 40)
        case .p30: (20, 60)
        case .p50: (40, 75)
        case .p80: (60, 90)
        case .auto: (65, 90)
        case .lossless: nil
        }
    }

    /// 原版的质量档位偏移量（qualitySelect），转格式候选质量在基础值上减去它
    public var conversionQualityAdjustment: Int {
        switch self {
        case .p10: 80
        case .p30: 60
        case .p50: 40
        case .p80: 20
        case .auto: 0
        case .lossless: -15
        }
    }

    /// gifsicle 参数（-O3 之外的部分）
    public var gifsicleExtraArgs: [String] {
        switch self {
        case .p10: ["--lossy=200", "--colors", "64"]
        case .p30: ["--lossy=120", "--colors", "128"]
        case .p50: ["--lossy=80", "--colors", "192"]
        case .p80: ["--lossy=30"]
        case .auto: ["--lossy=60"]
        case .lossless: []
        }
    }
}

/// 裁剪缩放设置（复刻原版：宽高超过原图时取原图尺寸，不放大）
public struct ResizeSpec: Sendable, Equatable {
    /// 目标宽度，0 表示未设置（取原图宽）
    public var width: Int
    /// 目标高度，0 表示未设置（取原图高）
    public var height: Int
    /// true = 限制宽高比（等比缩放到框内）；false = 缩放后居中裁剪成精确宽×高
    public var keepAspectRatio: Bool

    public init(width: Int, height: Int, keepAspectRatio: Bool = true) {
        self.width = width
        self.height = height
        self.keepAspectRatio = keepAspectRatio
    }

    /// 按原版规则解析目标尺寸：未设置或超过原图的维度取原图值
    public func clampedTarget(originalWidth: Int, originalHeight: Int) -> (width: Int, height: Int) {
        let w = (width <= 0 || width > originalWidth) ? originalWidth : width
        let h = (height <= 0 || height > originalHeight) ? originalHeight : height
        return (w, h)
    }

    /// 相对原始尺寸是否真的会缩小（决定 gifsicle 参数与「产物更大也不回退原图」）
    public func shrinks(originalWidth: Int, originalHeight: Int) -> Bool {
        let target = clampedTarget(originalWidth: originalWidth, originalHeight: originalHeight)
        return target.width < originalWidth || target.height < originalHeight
    }

    /// 直接对文件判定；尺寸读不到时按未缩小处理
    public func shrinks(fileAt url: URL) -> Bool {
        guard let size = ImageResizer.pixelSize(of: url) else { return false }
        return shrinks(originalWidth: size.width, originalHeight: size.height)
    }
}

/// 动图输出格式
public enum AnimOutputFormat: String, Sendable, CaseIterable, Codable {
    /// 默认：GIF 仍走 gifsicle 压缩（动图 WebP 输入则重编码为 WebP）
    case gif
    /// 转出动画 WebP
    case webp
    /// 转出 APNG（无损）
    case apng

    /// UI 与 CLI 共用的展示名
    public var label: String {
        switch self {
        case .gif: "GIF 压缩"
        case .webp: "动画 WebP"
        case .apng: "APNG"
        }
    }

    /// 按输入格式解析实际输出格式；nil = 走 GIF 原生压缩流程（gifsicle）。
    /// 非 GIF 输入没有「GIF 压缩」档，默认矫正为自身格式的重编码
    public func resolved(for format: ImageFormat) -> AnimOutputFormat? {
        switch format {
        case .gif:
            return self == .gif ? nil : self
        case .webpAnimated:
            return self == .apng ? .apng : .webp
        case .apng:
            return self == .webp ? .webp : .apng
        case .png, .jpeg, .webp:
            // 静态图不走动图转换路径
            return nil
        }
    }
}

/// 抽帧比例：每 outOf 帧保留前 keep 帧，被删帧的时长并入前一保留帧（总时长不变）
public struct FrameKeep: Sendable, Hashable {
    public var keep: Int
    public var outOf: Int

    public init(keep: Int, outOf: Int) {
        self.keep = max(1, keep)
        self.outOf = max(1, outOf)
    }

    public static let all = FrameKeep(keep: 1, outOf: 1)

    public var isIdentity: Bool { keep >= outOf }

    /// 保留比例（0-1）
    public var ratio: Double { isIdentity ? 1 : Double(keep) / Double(outOf) }

    public var label: String {
        isIdentity ? "不抽帧" : "保留 \(keep)/\(outOf)"
    }

    /// 可选档位：从保守到激进（1/2 以上为删掉多数帧）
    public static let presets: [FrameKeep] = [
        .all,
        FrameKeep(keep: 3, outOf: 4),
        FrameKeep(keep: 2, outOf: 3),
        FrameKeep(keep: 1, outOf: 2),
        FrameKeep(keep: 1, outOf: 3),
        FrameKeep(keep: 1, outOf: 4),
        FrameKeep(keep: 1, outOf: 5),
        FrameKeep(keep: 1, outOf: 6),
    ]
}

/// 动图转换设置
public struct AnimSettings: Sendable, Equatable {
    public var output: AnimOutputFormat
    /// 抽帧比例（默认全保留）
    public var frameKeep: FrameKeep
    /// 播放速度倍数（1 = 原速）。与抽帧解耦：
    /// 抽帧先合并延时保持总时长，再按倍数统一缩短各帧延时
    public var speed: Double
    /// 循环次数覆盖：nil = 保留原图设置，0 = 无限循环，N = 循环 N 次
    public var loopOverride: Int?

    public init(
        output: AnimOutputFormat = .gif, frameKeep: FrameKeep = .all,
        speed: Double = 1, loopOverride: Int? = nil
    ) {
        self.output = output
        self.frameKeep = frameKeep
        self.speed = speed
        self.loopOverride = loopOverride
    }

    /// 时间轴是否被改动（抽帧或调速）——两条动图路径共用的「发生了实际变换」判定
    public var transformsTimeline: Bool {
        !frameKeep.isIdentity || speed != 1
    }
}

public enum OutputMode: Sendable, Equatable {
    /// 输出到源目录下的固定名称子文件夹，文件名保持不变
    /// （整个文件夹压完可直接替换回项目）
    case fixedSubdir(String)
    /// 覆盖源文件
    case overwrite
    /// 输出到指定目录
    case customDir(URL)

    /// 默认输出文件夹名
    public static let defaultSubdirName = "minim"
}

public struct CompressionSettings: Sendable, Equatable {
    public var quality: QualityPreset
    public var generateWebP: Bool
    public var outputMode: OutputMode
    public var resize: ResizeSpec?
    /// 转 JPG：PNG / 静态 WebP 额外输出一份 JPG（透明填白底），不替换主输出
    public var autoConvert: Bool
    /// 转 PNG：JPG / 静态 WebP 额外输出一份无损 PNG，不替换主输出
    public var convertToPNG: Bool
    /// 动图转换设置
    public var anim: AnimSettings

    public init(
        quality: QualityPreset = .auto,
        generateWebP: Bool = false,
        outputMode: OutputMode = .fixedSubdir(OutputMode.defaultSubdirName),
        resize: ResizeSpec? = nil,
        autoConvert: Bool = false,
        convertToPNG: Bool = false,
        anim: AnimSettings = AnimSettings()
    ) {
        self.quality = quality
        self.generateWebP = generateWebP
        self.outputMode = outputMode
        self.resize = resize
        self.autoConvert = autoConvert
        self.convertToPNG = convertToPNG
        self.anim = anim
    }
}
