import Foundation

public enum GIFCompressor {
    public static func compress(
        source: URL, to destination: URL, preset: QualityPreset,
        resize: ResizeSpec? = nil, anim: AnimSettings = AnimSettings()
    ) async throws {
        var optimizeArgs = ["-O3"]
        optimizeArgs += preset.gifsicleExtraArgs

        if let resize, let size = ImageResizer.pixelSize(of: source),
           resize.shrinks(originalWidth: size.width, originalHeight: size.height) {
            let target = resize.clampedTarget(originalWidth: size.width, originalHeight: size.height)
            if resize.keepAspectRatio {
                // 等比缩放：gifsicle 直接支持缩到框内
                optimizeArgs += ["--resize-fit", "\(target.width)x\(target.height)"]
            } else {
                // 居中裁剪：gifsicle 的 --crop 先于 --resize 执行，
                // 所以在原图坐标里按目标宽高比居中裁剪，再精确缩放到目标尺寸（单趟完成）
                let crop = ImageResizer.coverCropRect(
                    originalWidth: size.width, originalHeight: size.height,
                    targetWidth: target.width, targetHeight: target.height
                )
                optimizeArgs += [
                    "--crop", "\(crop.x),\(crop.y)+\(crop.width)x\(crop.height)",
                    "--resize", "\(target.width)x\(target.height)",
                ]
            }
        }

        if let loop = anim.loopOverride {
            optimizeArgs += [loop == 0 ? "--loopcount=forever" : "--loopcount=\(loop)"]
        }

        // 抽帧与加速：规则由 AnimatedImage.plan 统一提供（与转 WebP/APNG 路径同一份实现）。
        // 帧选择必须放在输入文件之后；抽帧时先 -U 解开帧间优化才不会花屏
        var frameArgs: [String] = []
        var dropsFrames = false
        if anim.transformsTimeline,
           let delays = AnimatedImage.frameDelaysMs(source, clampShort: false), delays.count > 1 {
            let planned = AnimatedImage.plan(
                delaysMs: delays, keep: anim.frameKeep, speed: anim.speed
            )
            if planned.count < delays.count {
                optimizeArgs.insert("-U", at: 0)
                dropsFrames = true
            }
            frameArgs.reserveCapacity(planned.count * 2)
            for frame in planned {
                // gifsicle 的延时单位是厘秒（四舍五入，截断会让总时长系统性偏短）；
                // 下限 2cs 对应 AnimatedImage.minDelayMs
                let delayCs = max(
                    AnimatedImage.minDelayMs / 10,
                    Int((Double(frame.delayMs) / 10).rounded())
                )
                frameArgs += ["-d\(delayCs)", "#\(frame.sourceIndex)"]
            }
        }

        let fm = FileManager.default
        var flattened: URL?
        defer { if let flattened { try? fm.removeItem(at: flattened) } }

        // 用局部调色板的 GIF 无法被 -U 展开，删帧后保留的差分帧仍引用已删除的前帧，
        // 画面会出现脏斑残影；先压平成全局调色板再抽帧
        if dropsFrames, await hasLocalColorTables(source) {
            flattened = try await flatten(source, near: destination)
        }

        func runGifsicle(input: URL) async throws -> ExternalTool.RunResult {
            try await ExternalTool.run(
                "gifsicle",
                optimizeArgs + ["-o", destination.path, input.path] + frameArgs
            )
        }
        let result = try await runGifsicle(input: flattened ?? source)

        // 兜底：局部调色板之外的原因（如复杂透明）也会让展开失败，此时压平后重跑
        if dropsFrames, flattened == nil,
           String(data: result.stderr, encoding: .utf8)?.contains("unoptimize") == true {
            let temp = try await flatten(source, near: destination)
            flattened = temp
            _ = try await runGifsicle(input: temp)
        }
    }

    /// 是否含局部调色板（`--info` 只解析结构不解码像素，开销约几十毫秒）
    private static func hasLocalColorTables(_ url: URL) async -> Bool {
        guard let result = try? await ExternalTool.run("gifsicle", ["--info", url.path]),
              let info = String(data: result.stdout, encoding: .utf8)
        else { return false }
        return info.contains("local color table")
    }

    /// 压平为单一全局调色板，使 -U 能正常展开帧间优化
    private static func flatten(_ source: URL, near destination: URL) async throws -> URL {
        let temp = destination.deletingPathExtension()
            .appendingPathExtension("flat.tmp.gif")
        try await ExternalTool.run("gifsicle", ["--colors", "256", "-o", temp.path, source.path])
        return temp
    }
}
