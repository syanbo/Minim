import Foundation
import CoreGraphics
import ImageIO

/// 动图解码与抽帧（GIF / 动图 WebP，走 ImageIO）
public enum AnimatedImage {

    public struct Frame {
        public var image: CGImage
        /// 该帧展示时长（毫秒）
        public var delayMs: Int
    }

    public struct Animation {
        public var frames: [Frame]
        /// 0 = 无限循环
        public var loopCount: Int

        public var totalDurationMs: Int {
            frames.reduce(0) { $0 + $1.delayMs }
        }
    }

    /// 判断文件是否为多帧动图
    public static func isAnimated(_ url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(src) > 1
    }

    /// 动图基础信息（只读元数据，不解码像素，可安全用于 UI 展示）
    public struct ProbeInfo: Sendable {
        public let frameCount: Int
        public let width: Int
        public let height: Int
        public let durationMs: Int
        /// 0 = 无限循环
        public let loopCount: Int

        /// 平均帧率
        public var fps: Double {
            durationMs > 0 ? Double(frameCount) * 1000 / Double(durationMs) : 0
        }

        /// 如 "12 帧 · 10 fps · 1.2 秒 · 无限循环 · 400×300"
        public var summary: String {
            let seconds = String(format: "%.1f", Double(durationMs) / 1000)
            let loop = loopCount == 0 ? "无限循环" : "循环 \(loopCount) 次"
            return "\(frameCount) 帧 · \(Self.fpsText(fps)) · \(seconds) 秒 · \(loop) · \(width)×\(height)"
        }

        /// 帧率文案：低帧率保留一位小数，高帧率取整
        public static func fpsText(_ fps: Double) -> String {
            String(format: fps < 10 ? "%.1f fps" : "%.0f fps", fps)
        }
    }

    /// 探测动图基础信息；非动图返回 nil
    public static func probe(_ url: URL) -> ProbeInfo? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 1 else { return nil }

        var width = 0
        var height = 0
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        }
        var durationMs = 0
        for i in 0..<count {
            durationMs += frameDelayMs(src, index: i)
        }
        return ProbeInfo(
            frameCount: count, width: width, height: height,
            durationMs: durationMs, loopCount: containerLoopCount(src)
        )
    }

    /// 解码动图全部帧与循环次数；单帧或解码失败返回 nil
    public static func decode(_ url: URL) -> Animation? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 1 else { return nil }

        var frames: [Frame] = []
        frames.reserveCapacity(count)
        for i in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(src, i, [
                kCGImageSourceShouldCache: false,
            ] as CFDictionary) else { continue }
            frames.append(Frame(image: image, delayMs: frameDelayMs(src, index: i)))
        }
        guard frames.count > 1 else { return nil }
        return Animation(frames: frames, loopCount: containerLoopCount(src))
    }

    /// 帧延时下限：过短的延时会触发浏览器钳制（<11ms 被当 100ms 播，反而变慢）
    public static let minDelayMs = 20

    /// 保留下来的帧及其新延时
    public struct PlannedFrame: Sendable, Equatable {
        /// 在原动画中的帧序号
        public let sourceIndex: Int
        public let delayMs: Int
    }

    /// 抽帧 + 调速的唯一规则实现（GIF 与 WebP/APNG 两条路径共用）：
    /// 每 keep.outOf 帧保留前 keep.keep 帧，被删帧延时累加到前一保留帧（总时长不变），
    /// 再按速度倍数统一缩短各帧延时（下限 minDelayMs）
    public static func plan(delaysMs: [Int], keep: FrameKeep, speed: Double) -> [PlannedFrame] {
        var kept: [(index: Int, delay: Int)] = []
        kept.reserveCapacity(delaysMs.count)
        for (i, delay) in delaysMs.enumerated() {
            if !keep.isIdentity, i % keep.outOf >= keep.keep, !kept.isEmpty {
                kept[kept.count - 1].delay += delay
            } else {
                kept.append((i, delay))
            }
        }
        guard speed > 0, speed != 1 else {
            return kept.map { PlannedFrame(sourceIndex: $0.index, delayMs: $0.delay) }
        }
        return kept.map {
            PlannedFrame(
                sourceIndex: $0.index,
                delayMs: max(minDelayMs, Int((Double($0.delay) / speed).rounded()))
            )
        }
    }

    /// 抽帧：每 keep.outOf 帧保留前 keep.keep 帧，
    /// 被删帧的延时累加到前一保留帧（总时长不变）
    public static func decimate(_ animation: Animation, keep: FrameKeep) -> Animation {
        guard !keep.isIdentity else { return animation }
        return applying(plan(delaysMs: animation.frames.map(\.delayMs), keep: keep, speed: 1),
                        to: animation)
    }

    /// 播放加速：各帧延时统一除以速度倍数（下限 minDelayMs）
    public static func retime(_ animation: Animation, speed: Double) -> Animation {
        guard speed > 0, speed != 1 else { return animation }
        var result = animation
        for i in result.frames.indices {
            result.frames[i].delayMs = max(
                minDelayMs, Int((Double(result.frames[i].delayMs) / speed).rounded())
            )
        }
        return result
    }

    /// 逐帧替换图像（缩放等变换共用）；transform 返回 nil 时保留原帧
    public static func mapImages(
        _ animation: Animation, _ transform: (CGImage) -> CGImage?
    ) -> Animation {
        var result = animation
        for i in result.frames.indices {
            if let replaced = transform(result.frames[i].image) {
                result.frames[i].image = replaced
            }
        }
        return result
    }

    /// 读取各帧延时（毫秒）。clampShort = false 时保留文件原始延时，
    /// 不做浏览器式的「过短按 100ms 处理」（gifsicle 路径需要原值）
    public static func frameDelaysMs(_ url: URL, clampShort: Bool = true) -> [Int]? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else { return nil }
        let count = CGImageSourceGetCount(src)
        guard count > 1 else { return nil }
        return (0..<count).map { frameDelayMs(src, index: $0, clampShort: clampShort) }
    }

    // MARK: - 内部

    /// 按计划重建帧数组
    private static func applying(_ planned: [PlannedFrame], to animation: Animation) -> Animation {
        var frames: [Frame] = []
        frames.reserveCapacity(planned.count)
        for item in planned where item.sourceIndex < animation.frames.count {
            frames.append(Frame(
                image: animation.frames[item.sourceIndex].image, delayMs: item.delayMs
            ))
        }
        return Animation(frames: frames, loopCount: animation.loopCount)
    }

    private static func frameDelayMs(
        _ src: CGImageSource, index: Int, clampShort: Bool = true
    ) -> Int {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any]
        else { return 100 }
        let dicts: [(container: CFString, unclamped: CFString, clamped: CFString)] = [
            (kCGImagePropertyGIFDictionary,
             kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyWebPDictionary,
             kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyPNGDictionary,
             kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
        ]
        for entry in dicts {
            guard let dict = props[entry.container] as? [CFString: Any] else { continue }
            let seconds = (dict[entry.unclamped] as? Double)
                ?? (dict[entry.clamped] as? Double) ?? 0
            guard clampShort else { return max(0, Int((seconds * 1000).rounded())) }
            // 浏览器惯例：过短的帧延时按 100ms 处理
            return seconds > 0.011 ? Int(seconds * 1000) : 100
        }
        return 100
    }

    private static func containerLoopCount(_ src: CGImageSource) -> Int {
        guard let props = CGImageSourceCopyProperties(src, nil) as? [CFString: Any]
        else { return 0 }
        let entries: [(container: CFString, loop: CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFLoopCount),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPLoopCount),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGLoopCount),
        ]
        for entry in entries {
            if let dict = props[entry.container] as? [CFString: Any],
               let loop = dict[entry.loop] as? Int {
                return loop
            }
        }
        return 0
    }
}
