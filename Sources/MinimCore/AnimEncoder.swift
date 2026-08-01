import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import libwebp

/// 动画编码：WebP（libwebp WebPAnimEncoder）与 APNG（ImageIO）
public enum AnimEncoder {

    /// 编码动画 WebP。loopCount 0 = 无限循环；保真档走 lossless。
    /// 与静态 WebP 同策略：无损/有损双候选，无损不超过有损 4 倍体积就选无损
    /// （发光/半透明类素材有损既不省体积画质还差）
    public static func encodeWebP(
        _ animation: AnimatedImage.Animation,
        loopCount: Int,
        preset: QualityPreset,
        originalSizeHint: Int? = nil,
        to url: URL
    ) throws {
        let losslessData = try encodeWebPData(
            animation, loopCount: loopCount, lossless: true, quality: 75
        )
        if preset == .lossless {
            try losslessData.write(to: url)
            return
        }
        let lossyData = try encodeWebPData(
            animation, loopCount: loopCount,
            lossless: false, quality: Float(preset.fixedJPEGQuality ?? 75)
        )
        try WebPEncoder.chooseCandidate(
            lossless: losslessData, lossy: lossyData, originalSizeHint: originalSizeHint
        ).write(to: url)
    }

    private static func encodeWebPData(
        _ animation: AnimatedImage.Animation,
        loopCount: Int,
        lossless: Bool,
        quality: Float
    ) throws -> Data {
        guard let first = animation.frames.first else {
            throw ExternalToolError(tool: "WebPAnim", message: "没有可编码的帧")
        }
        let width = Int32(first.image.width)
        let height = Int32(first.image.height)

        var options = WebPAnimEncoderOptions()
        guard WebPAnimEncoderOptionsInit(&options) != 0 else {
            throw ExternalToolError(tool: "WebPAnim", message: "编码器选项初始化失败")
        }
        options.anim_params.loop_count = Int32(loopCount)
        options.minimize_size = 1   // 帧间差分深度优化（稍慢但显著减小体积）

        guard let encoder = WebPAnimEncoderNew(width, height, &options) else {
            throw ExternalToolError(tool: "WebPAnim", message: "编码器创建失败")
        }
        defer { WebPAnimEncoderDelete(encoder) }

        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0 else {
            throw ExternalToolError(tool: "WebPAnim", message: "编码配置初始化失败")
        }
        if lossless {
            config.lossless = 1
            config.quality = quality        // 无损模式下代表压缩努力程度
        } else {
            config.quality = quality
            config.use_sharp_yuv = 1        // 锐化色度转换，避免硬边缘发糊
        }

        var timestampMs: Int32 = 0
        for frame in animation.frames {
            var picture = WebPPicture()
            guard WebPPictureInit(&picture) != 0 else {
                throw ExternalToolError(tool: "WebPAnim", message: "帧初始化失败")
            }
            defer { WebPPictureFree(&picture) }
            picture.width = width
            picture.height = height
            picture.use_argb = 1

            let pixels = CGImagePixels.straightRGBA(
                of: frame.image, width: Int(width), height: Int(height)
            )
            let imported = pixels.withUnsafeBufferPointer {
                WebPPictureImportRGBA(&picture, $0.baseAddress, width * 4)
            }
            guard imported != 0 else {
                throw ExternalToolError(tool: "WebPAnim", message: "帧像素导入失败")
            }
            guard WebPAnimEncoderAdd(encoder, &picture, timestampMs, &config) != 0 else {
                let message = String(cString: WebPAnimEncoderGetError(encoder))
                throw ExternalToolError(tool: "WebPAnim", message: "帧编码失败: \(message)")
            }
            timestampMs += Int32(frame.delayMs)
        }
        // 收尾帧：标记动画总时长
        WebPAnimEncoderAdd(encoder, nil, timestampMs, nil)

        var data = WebPData()
        WebPDataInit(&data)
        guard WebPAnimEncoderAssemble(encoder, &data) != 0 else {
            throw ExternalToolError(tool: "WebPAnim", message: "动画装配失败")
        }
        defer { WebPDataClear(&data) }
        guard let bytes = data.bytes, data.size > 0 else {
            throw ExternalToolError(tool: "WebPAnim", message: "输出为空")
        }
        return Data(bytes: bytes, count: data.size)
    }

    /// 编码 APNG。loopCount 0 = 无限循环。
    /// 首选 apngasm 差分装配（帧间只存变化区域，体积远小于全幅帧）；
    /// 质量档位非保真时先逐帧 pngquant 量化（有损），保真 = 无损
    public static func encodeAPNG(
        _ animation: AnimatedImage.Animation,
        loopCount: Int,
        preset: QualityPreset = .lossless,
        to url: URL,
        onStage: CompressionEngine.StageReporter? = nil
    ) async throws {
        let fm = FileManager.default
        guard ExternalTool.locate("apngasm") != nil else {
            // 回退：ImageIO 全幅帧（无 apngasm 时）
            try encodeAPNGFullFrames(animation, loopCount: loopCount, to: url)
            await oxipngPass(url)
            return
        }
        let dir = fm.temporaryDirectory
            .appendingPathComponent("minim-apng-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let hasPngquant = ExternalTool.locate("pngquant") != nil
        let quantRange = hasPngquant ? preset.pngquantQualityRange : nil
        // 先尝试全局调色板量化：各帧调色板不同时全局色数会超 256，
        // apngasm 只能退回真彩编码，体积可涨到索引色的 3 倍
        var sharedFrames: [CGImage]?
        if let range = quantRange {
            onStage?("量化全局调色板")
            sharedFrames = await sharedPaletteFrames(
                animation.frames, range: range, tempDir: dir
            )
        }
        try Task.checkCancellation()
        // 全局调色板成功时各帧已量化，无需再逐帧量化
        let perFrameRange = sharedFrames == nil ? quantRange : nil

        var args = ["-o", url.path]
        let total = animation.frames.count
        for (index, frame) in animation.frames.enumerated() {
            try Task.checkCancellation()
            onStage?("写出帧 \(index + 1)/\(total)")
            let framePath = dir.appendingPathComponent(String(format: "f%04d.png", index))
            try ImageResizer.writePNG(sharedFrames?[index] ?? frame.image, to: framePath)
            if let range = perFrameRange {
                _ = await quantize(framePath, range: range, relaxFloorOnFailure: false)
            }
            args += [framePath.path, "\(max(frame.delayMs, 10))"]
        }
        // 拼图帧已落盘，装配前释放（切片与拼图共享像素，可达上百 MB）
        sharedFrames = nil
        args += ["-l", "\(loopCount)", "-F"]
        try? fm.removeItem(at: url)
        onStage?("装配 APNG")
        try await ExternalTool.run("apngasm", args)
        guard fm.fileExists(atPath: url.path) else {
            throw ExternalToolError(tool: "apngasm", message: "APNG 装配失败")
        }
        await oxipngPass(url)
    }

    /// pngquant 量化到 ≤256 色（原地覆盖）；返回是否真的写出了量化产物。
    /// relaxFloorOnFailure：达不到质量下限时去掉下限重试
    private static func quantize(
        _ url: URL, range: (min: Int, max: Int), relaxFloorOnFailure: Bool
    ) async -> Bool {
        func run(minQuality: Int) async -> Bool {
            // 退出码 98/99 = 跳过/达不到质量下限，此时不写输出
            (try? await ExternalTool.run("pngquant", [
                "--force", "--speed", "3",
                "--quality", "\(minQuality)-\(range.max)",
                "--output", url.path, "256", "--", url.path,
            ])) != nil
        }
        if await run(minQuality: range.min) { return true }
        guard relaxFloorOnFailure else { return false }
        return await run(minQuality: 0)
    }

    /// 无损再压一道（保留动画结构）
    private static func oxipngPass(_ url: URL) async {
        _ = try? await ExternalTool.run("oxipng", [
            "-o", "2", "--strip", "safe", "--quiet", url.path,
        ])
    }

    /// 全局调色板量化：把所有帧拼成一张大图交给 pngquant 一次量化，
    /// 使全部帧共用同一套 ≤256 色，apngasm 才能输出 8 位索引色 APNG。
    /// 帧尺寸不一致、拼图过大或达不到质量下限时返回 nil（退回逐帧量化）
    private static func sharedPaletteFrames(
        _ frames: [AnimatedImage.Frame],
        range: (min: Int, max: Int),
        tempDir: URL
    ) async -> [CGImage]? {
        guard let first = frames.first, frames.count > 1 else { return nil }
        let width = first.image.width
        let height = first.image.height
        guard frames.allSatisfy({ $0.image.width == width && $0.image.height == height })
        else { return nil }

        let cols = Int(ceil(Double(frames.count).squareRoot()))
        let rows = Int(ceil(Double(frames.count) / Double(cols)))
        let sheetWidth = cols * width
        let sheetHeight = rows * height
        // 拼图内存上限约 190 MB（RGBA），超出则退回逐帧量化
        guard sheetWidth * sheetHeight <= 48_000_000 else { return nil }

        guard let context = CGContext(
            data: nil, width: sheetWidth, height: sheetHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        for (index, frame) in frames.enumerated() {
            let col = index % cols
            let row = index / cols
            // CGContext 原点在左下，逐行自上而下摆放
            context.draw(frame.image, in: CGRect(
                x: col * width, y: sheetHeight - (row + 1) * height,
                width: width, height: height
            ))
        }
        guard let sheet = context.makeImage() else { return nil }

        let sheetURL = tempDir.appendingPathComponent("palette-sheet.png")
        guard (try? ImageResizer.writePNG(sheet, to: sheetURL)) != nil else { return nil }
        // 噪点多的视频类动图拼图达不到质量下限时去掉下限重试：
        // 宁可降一点画质也要拿到索引色，否则退回真彩编码体积会翻数倍
        guard await quantize(sheetURL, range: range, relaxFloorOnFailure: true) else { return nil }

        guard let src = CGImageSourceCreateWithURL(sheetURL as CFURL, nil),
              let sheetImage = CGImageSourceCreateImageAtIndex(src, 0, nil),
              sheetImage.width == sheetWidth, sheetImage.height == sheetHeight
        else { return nil }

        var sliced: [CGImage] = []
        sliced.reserveCapacity(frames.count)
        for index in frames.indices {
            // CGImage 裁剪原点在左上，与摆放顺序一致
            guard let piece = sheetImage.cropping(to: CGRect(
                x: (index % cols) * width, y: (index / cols) * height,
                width: width, height: height
            )) else { return nil }
            sliced.append(piece)
        }
        return sliced
    }

    /// ImageIO 全幅帧 APNG（体积较大，仅作 apngasm 缺失时的回退）
    static func encodeAPNGFullFrames(
        _ animation: AnimatedImage.Animation,
        loopCount: Int,
        to url: URL
    ) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, animation.frames.count, nil
        ) else {
            throw ExternalToolError(tool: "APNG", message: "无法创建输出文件")
        }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyAPNGLoopCount: loopCount,
            ],
        ] as CFDictionary)
        for frame in animation.frames {
            CGImageDestinationAddImage(dest, frame.image, [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGDelayTime: Double(frame.delayMs) / 1000.0,
                    kCGImagePropertyAPNGUnclampedDelayTime: Double(frame.delayMs) / 1000.0,
                ],
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else {
            throw ExternalToolError(tool: "APNG", message: "APNG 编码失败")
        }
    }

}
