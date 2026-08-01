import Foundation

public enum CompressionEngine {

    /// 处理阶段回调（用于界面显示进度文案）
    public typealias StageReporter = @Sendable (String) -> Void

    /// 压缩单张图片（含可选 WebP 生成），全程先写临时文件，
    /// 若压缩结果不比原图小则回退为原文件拷贝
    public static func compress(
        source: URL, settings: CompressionSettings, onStage: StageReporter? = nil
    ) async throws -> CompressionResult {
        guard let format = ImageFormat.detect(from: source) else {
            throw ExternalToolError(tool: "engine", message: "不支持的图片格式")
        }
        let originalSize = source.fileSizeBytes

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("minim", isDirectory: true)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 动图转换路径：GIF（转换开启时）与动图 WebP/APNG（始终，gifsicle 处理不了它们）
        if let animOutput = settings.anim.output.resolved(for: format) {
            onStage?("解码动图")
            if let animation = AnimatedImage.decode(source) {
                return try await convertAnimation(
                    animation, source: source, output: animOutput,
                    originalSize: originalSize, format: format,
                    settings: settings, tempDir: tempDir, onStage: onStage
                )
            }
        }
        onStage?("压缩中")

        let temp = tempDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(format.preferredExtension)
        defer { try? fm.removeItem(at: temp) }

        // PNG 的裁剪缩放：先无损写出缩放后的 PNG，再走 pngquant/oxipng 流程
        var pngInput = source
        var resizedPNGTemp: URL?
        defer { if let resizedPNGTemp { try? fm.removeItem(at: resizedPNGTemp) } }
        if format == .png, let resize = settings.resize,
           let resized = ImageResizer.resizedImage(from: source, spec: resize) {
            let resizedTemp = tempDir
                .appendingPathComponent(UUID().uuidString + ".resized.png")
            try ImageResizer.writePNG(resized, to: resizedTemp)
            resizedPNGTemp = resizedTemp
            pngInput = resizedTemp
        }

        switch format {
        case .jpeg:
            try JPEGCompressor.compress(
                source: source, to: temp, preset: settings.quality, resize: settings.resize
            )
        case .png:
            try await PNGCompressor.compress(source: pngInput, to: temp, preset: settings.quality)
        case .gif:
            try await GIFCompressor.compress(
                source: source, to: temp, preset: settings.quality,
                resize: settings.resize, anim: settings.anim
            )
        case .webpAnimated, .apng:
            // 只会在动图解码失败时走到这里
            throw ExternalToolError(tool: "engine", message: "动图解码失败")
        }

        let compressedSize = temp.fileSizeBytes
        // 裁剪缩放、GIF 抽帧/加速/改循环都是实际改动，产物更大也不能回退成原图
        let transformed = settings.resize?.shrinks(fileAt: source) ?? false
            || (format == .gif
                && (settings.anim.transformsTimeline || settings.anim.loopOverride != nil))
        let keptOriginal = !transformed
            && (compressedSize <= 0 || compressedSize >= originalSize)

        let outputURL = destinationURL(for: source, format: format, mode: settings.outputMode)
        let outputSize = try publish(
            temp: temp, to: outputURL, source: source,
            keptOriginal: keptOriginal, originalSize: originalSize, producedSize: compressedSize
        )

        // WebP：从源图生成（保证质量基准一致），GIF 动图不支持
        var webpURL: URL?
        var webpSize: Int64?
        if settings.generateWebP, format != .gif {
            let target = webpDestinationURL(for: source, outputURL: outputURL)
            try? fm.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try WebPEncoder.encode(
                source: source, to: target, preset: settings.quality, resize: settings.resize
            )
            webpURL = target
            webpSize = target.fileSizeBytes
        }

        // 自动转换格式：额外输出一个候选文件（不替换主输出），只对静态 PNG 有效
        var convertedURL: URL?
        var convertedSize: Int64?
        if settings.autoConvert, format == .png,
           let converted = try? jpegCandidate(
               source: source, outputURL: outputURL, settings: settings
           ) {
            convertedURL = converted.url
            convertedSize = converted.size
        }

        return CompressionResult(
            outputURL: outputURL,
            originalSize: originalSize,
            outputSize: outputSize,
            webpURL: webpURL,
            webpSize: webpSize,
            keptOriginal: keptOriginal,
            convertedURL: convertedURL,
            convertedSize: convertedSize
        )
    }

    /// 动图转换：抽帧 → 逐帧缩放裁剪 → 编码为动画 WebP / APNG
    private static func convertAnimation(
        _ animation: AnimatedImage.Animation,
        source: URL,
        output: AnimOutputFormat,
        originalSize: Int64,
        format: ImageFormat,
        settings: CompressionSettings,
        tempDir: URL,
        onStage: StageReporter? = nil
    ) async throws -> CompressionResult {
        let fm = FileManager.default
        var anim = AnimatedImage.retime(
            AnimatedImage.decimate(animation, keep: settings.anim.frameKeep),
            speed: settings.anim.speed
        )

        if let resize = settings.resize {
            onStage?("缩放 \(anim.frames.count) 帧")
            anim = AnimatedImage.mapImages(anim) { ImageResizer.apply(resize, to: $0) }
        }
        try Task.checkCancellation()

        let loopCount = settings.anim.loopOverride ?? anim.loopCount
        let ext = output == .apng ? "png" : "webp"
        let temp = tempDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        defer { try? fm.removeItem(at: temp) }

        switch output {
        case .webp:
            onStage?("编码动画 WebP（\(anim.frames.count) 帧）")
            try AnimEncoder.encodeWebP(
                anim, loopCount: loopCount, preset: settings.quality,
                originalSizeHint: Int(originalSize), to: temp
            )
        case .apng:
            try await AnimEncoder.encodeAPNG(
                anim, loopCount: loopCount, preset: settings.quality,
                to: temp, onStage: onStage
            )
        case .gif:
            throw ExternalToolError(tool: "engine", message: "无效的动图输出格式")
        }

        // 输出路径沿用主命名规则，但扩展名换成目标格式
        var outputURL = destinationURL(for: source, format: format, mode: settings.outputMode)
            .deletingPathExtension()
            .appendingPathExtension(ext)
        if outputURL == source {
            // 覆盖模式下扩展名相同（webp→webp）才可能同路径；异格式写在源文件旁
            outputURL = source.deletingPathExtension().appendingPathExtension(ext)
        }
        // 同格式重编码且没有任何实际改动（不抽帧/不加速/不缩放/不改循环）时，
        // 产物不比原图小就回退保留原文件（如已高度优化过的 APNG 再编码反而更大）
        let encodedSize = temp.fileSizeBytes
        let sameFormat = (format == .apng && output == .apng)
            || (format == .webpAnimated && output == .webp)
        let transformed = settings.anim.transformsTimeline
            || (settings.resize?.shrinks(fileAt: source) ?? false)
            || loopCount != animation.loopCount
        let keptOriginal = sameFormat && !transformed
            && (encodedSize <= 0 || encodedSize >= originalSize)

        let outputSize = try publish(
            temp: temp, to: outputURL, source: source,
            keptOriginal: keptOriginal, originalSize: originalSize, producedSize: encodedSize
        )
        return CompressionResult(
            outputURL: outputURL,
            originalSize: originalSize,
            outputSize: outputSize,
            keptOriginal: keptOriginal
        )
    }

    /// 静态 PNG 的转 JPG 候选（额外文件，不替换主输出）
    private static func jpegCandidate(
        source: URL, outputURL: URL, settings: CompressionSettings
    ) throws -> (url: URL, size: Int64)? {
        guard let (image, analysis) = FormatConverter.analyze(
            source: source, resize: settings.resize
        ) else { return nil }

        let fm = FileManager.default
        let candidateJPEG = fm.temporaryDirectory
            .appendingPathComponent("minim", isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        defer { try? fm.removeItem(at: candidateJPEG) }

        // 开启转格式即一定额外输出 JPG；透明部分平铺到白底
        let flattened = analysis.hasTransparency
            ? FormatConverter.flattenOnWhite(image)
            : image
        let quality = FormatConverter.pngToJPEGQuality(analysis: analysis, preset: settings.quality)
        try FormatConverter.writeJPEG(flattened, to: candidateJPEG, quality: quality)
        guard candidateJPEG.fileSizeBytes > 0 else { return nil }

        let baseName = source.deletingPathExtension().lastPathComponent
        let target = outputURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)-jpg.jpg")
        try? fm.removeItem(at: target)
        try fm.copyItem(at: candidateJPEG, to: target)
        return (target, target.fileSizeBytes)
    }

    /// 落盘：keptOriginal 时把原文件拷到目标，否则用临时产物替换目标；返回最终输出大小
    private static func publish(
        temp: URL, to outputURL: URL, source: URL,
        keptOriginal: Bool, originalSize: Int64, producedSize: Int64
    ) throws -> Int64 {
        let fm = FileManager.default
        try? fm.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if keptOriginal {
            if outputURL != source {
                try? fm.removeItem(at: outputURL)
                try fm.copyItem(at: source, to: outputURL)
            }
            return originalSize
        }
        _ = try fm.replaceItemAt(outputURL, withItemAt: temp)
        return producedSize
    }

    static func destinationURL(for source: URL, format: ImageFormat, mode: OutputMode) -> URL {
        switch mode {
        case .overwrite:
            return source
        case .fixedSubdir(let name):
            return source.deletingLastPathComponent()
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(source.lastPathComponent)
        case .customDir(let dir):
            return dir.appendingPathComponent(source.lastPathComponent)
        }
    }

    /// WebP 输出位置：与主输出同目录、同名换扩展
    static func webpDestinationURL(for source: URL, outputURL: URL) -> URL {
        let name = source.deletingPathExtension().lastPathComponent + ".webp"
        return outputURL.deletingLastPathComponent().appendingPathComponent(name)
    }
}
