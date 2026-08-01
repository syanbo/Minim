import SwiftUI
import AppKit
import MinimCore

struct TaskRowView: View {
    @Environment(AppStore.self) private var store
    let task: ImageTask
    @State private var thumbnail: NSImage?
    @State private var sourceAnimInfo: AnimatedImage.ProbeInfo?
    /// 处理后的动图信息与格式（同生同灭，一次探测得出）
    @State private var outputInfo: (format: ImageFormat?, anim: AnimatedImage.ProbeInfo)?
    /// 拖动中的速度值：松手才提交，避免每个 tick 触发全列表重绘与写盘
    @State private var draftSpeed: Double?
    @State private var thumbnailHovering = false

    private var doneOutputURL: URL? {
        task.state.result?.outputURL
    }

    /// 待开始、完成、失败的动图行都保留参数行，可随时调整
    private var showsConfigLine: Bool {
        guard task.isAnimated else { return false }
        switch task.state {
        case .awaitingStart, .done, .failed: return true
        case .pending, .processing: return false
        }
    }

    /// 参数被改动过 → 显示重试按钮。
    /// 既包括行内动图参数（输出/抽帧/循环），也包括影响动图的工具栏设置（质量/裁剪缩放/输出位置）
    private var configChanged: Bool {
        guard let last = task.lastRunSettings else { return false }
        let current = store.settings
        if let config = task.animConfig, config != last.anim { return true }
        return last.quality != current.quality
            || last.resize != current.resize
            || last.outputMode != current.outputMode
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.sourceURL.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    badge(task.format.displayName, .secondary)
                }
                detailLine
                if let info = sourceAnimInfo {
                    animInfoLine(info)
                }
                if showsConfigLine {
                    animConfigLine
                }
            }
            Spacer()
            trailingView
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(store.compareTask?.id == task.id
                    ? Color.accentColor.opacity(0.08)
                    : Color.clear)
        )
        .onTapGesture {
            // 点击整行在侧边面板预览/对比；再点同一行收起
            store.compareTask = store.compareTask?.id == task.id ? nil : task
        }
        .help(task.state.isDone ? "点击对比压缩前后效果" : "点击预览原图")
        .task {
            thumbnail = await loadThumbnail(for: task.sourceURL)
            if task.isAnimated {
                let source = task.sourceURL
                sourceAnimInfo = await Task.detached(priority: .utility) {
                    AnimatedImage.probe(source)
                }.value
            }
        }
        .task(id: doneOutputURL) {
            guard task.isAnimated, let output = doneOutputURL else {
                outputInfo = nil
                return
            }
            outputInfo = await Task.detached(priority: .utility) {
                AnimatedImage.probe(output).map { (ImageFormat.detect(from: output), $0) }
            }.value
        }
    }

    // MARK: - 通用样式

    /// 胶囊徽章：格式、输出扩展名、压缩率、「已最优」共用
    private func badge(_ text: String, _ tint: Color, size: CGFloat = 9) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .padding(.horizontal, size > 9 ? 8 : 4)
            .padding(.vertical, size > 9 ? 3 : 1)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    // MARK: - 动图信息与参数

    /// 动图基础信息：格式 · 帧数 · 时长 · 循环 · 尺寸（→ 处理后信息，完成即展示）
    private func animInfoLine(_ info: AnimatedImage.ProbeInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "film")
                .font(.system(size: 8))
            Text("\(task.format.displayName) · \(info.summary)")
            if let out = outputInfo {
                Image(systemName: "arrow.right")
                    .font(.system(size: 7))
                Text(out.format.map { "\($0.displayName) · \(out.anim.summary)" } ?? out.anim.summary)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }

    /// 生效参数：行内覆盖优先，否则跟随工具栏
    private var config: AnimSettings {
        store.animConfig(for: task)
    }

    private var hasOverride: Bool {
        store.hasAnimOverride(task)
    }

    /// 待开始状态的行内参数：输出格式 / 抽帧 / 循环
    private var animConfigLine: some View {
        HStack(spacing: 10) {
            Menu {
                // 非 GIF 输入没有「GIF 压缩」档
                ForEach(AnimOutputFormat.allCases.filter {
                    $0 != .gif || task.format == .gif
                }, id: \.self) { format in
                    Button(format.label) { update { $0.output = format } }
                }
            } label: {
                Text(config.output.label)
            }

            Menu {
                ForEach(FrameKeep.presets, id: \.self) { preset in
                    Button(menuLabel(for: preset)) { update { $0.frameKeep = preset } }
                }
            } label: {
                Text(config.frameKeep.label)
            }
            .help("抽帧比例：被删帧的时长并入前一帧，总时长不变，只降帧率")

            HStack(spacing: 4) {
                Text("速度")
                Slider(
                    value: Binding(
                        get: { draftSpeed ?? config.speed },
                        set: { draftSpeed = $0 }
                    ),
                    in: 1...2, step: 0.1,
                    onEditingChanged: { editing in
                        guard !editing, let value = draftSpeed else { return }
                        draftSpeed = nil
                        update { $0.speed = value }
                    }
                )
                .controlSize(.mini)
                .frame(width: 72)
                Text(String(format: "%.1fx", draftSpeed ?? config.speed))
                    .monospacedDigit()
                    .foregroundStyle(
                        (draftSpeed ?? config.speed) == 1 ? .secondary : Color.accentColor
                    )
            }
            .help("播放速度：与抽帧独立，抽帧本身不改变总时长")

            Menu {
                Button("保留原设置") { update { $0.loopOverride = nil } }
                Button("无限循环") { update { $0.loopOverride = 0 } }
                ForEach([1, 2, 3, 5, 10], id: \.self) { n in
                    Button("循环 \(n) 次") { update { $0.loopOverride = n } }
                }
            } label: {
                Text(loopLabel)
            }

            if hasOverride {
                Button {
                    store.resetAnimConfig(taskID: task.id)
                } label: {
                    Label("单独设置", systemImage: "arrow.uturn.backward")
                        .labelStyle(.titleAndIcon)
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .help("这一行已脱离工具栏的动图默认参数，点击恢复跟随")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.caption)
        .padding(.top, 2)
    }

    /// 抽帧档位标签，已知源帧率时附带该档的预计帧率
    private func menuLabel(for keep: FrameKeep) -> String {
        guard let source = sourceAnimInfo, source.fps > 0 else { return keep.label }
        let fps = source.fps * keep.ratio * config.speed
        return "\(keep.label) · \(AnimatedImage.ProbeInfo.fpsText(fps))"
    }

    private var loopLabel: String {
        switch config.loopOverride {
        case nil: "循环:保留"
        case 0: "循环:无限"
        case .some(let n): "循环:\(n) 次"
        }
    }

    private func update(_ transform: (inout AnimSettings) -> Void) {
        var updated = config
        transform(&updated)
        store.updateAnimConfig(taskID: task.id, updated)
    }

    // MARK: - 通用部件

    /// 缩略图：点击在 Finder 中定位并选中源文件（整行点击是预览/对比，两者互不干扰）
    private var thumbnailView: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 40, height: 40)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(thumbnailHovering ? 1 : 0)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            NSWorkspace.shared.activateFileViewerSelecting([task.sourceURL])
        }
        .onHover { hovering in
            thumbnailHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help("在 Finder 中显示原文件")
    }

    @ViewBuilder
    private var detailLine: some View {
        switch task.state {
        case .awaitingStart, .pending, .processing:
            let word = switch task.state {
            case .awaitingStart: "待开始"
            case .pending: "排队中"
            default: store.stage(for: task.id) ?? "压缩中"
            }
            Text("\(word) · \(ByteFormatter.string(task.originalSize))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .done(let result):
            HStack(spacing: 4) {
                Text(ByteFormatter.string(result.originalSize))
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                Text(ByteFormatter.string(result.outputSize))
                    .fontWeight(.medium)
                if result.outputURL.pathExtension.lowercased()
                    != task.sourceURL.pathExtension.lowercased() {
                    badge(result.outputURL.pathExtension.uppercased(), Color.accentColor)
                }
                if let webpSize = result.webpSize {
                    Text("· WebP \(ByteFormatter.string(webpSize))")
                        .foregroundStyle(.secondary)
                }
                if let convertedURL = result.convertedURL, let convertedSize = result.convertedSize {
                    Text("· \(convertedURL.pathExtension.uppercased()) \(ByteFormatter.string(convertedSize))")
                        .foregroundStyle(.purple)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        switch task.state {
        case .awaitingStart:
            CapsuleButton(title: "开始", icon: "play.fill") {
                store.startAnim(taskID: task.id)
            }
        case .pending, .processing:
            HStack(spacing: 8) {
                if case .processing = task.state {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "clock").foregroundStyle(.tertiary)
                }
                Button {
                    store.cancel(taskID: task.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("取消处理")
            }
        case .done(let result):
            HStack(spacing: 10) {
                if configChanged {
                    retryButton
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中显示")
                if result.keptOriginal {
                    badge("已最优", .secondary, size: 11)
                } else {
                    badge(ByteFormatter.ratioString(result.savedRatio), .green, size: 11)
                }
            }
        case .failed:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                if task.isAnimated {
                    retryButton
                }
            }
        }
    }

    private var retryButton: some View {
        CapsuleButton(title: "重试", icon: "arrow.counterclockwise") {
            store.startAnim(taskID: task.id)
        }
    }

    /// 行内主操作按钮（开始/重试）：胶囊样式，与压缩率徽章同视觉语言
    private struct CapsuleButton: View {
        let title: String
        let icon: String
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .bold))
                    Text(title)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        Color.accentColor.opacity(hovering ? 1 : 0.85)
                    )
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }

    private func loadThumbnail(for url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 120,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary) {
                return NSImage(cgImage: cgImage, size: .zero)
            }
            // 动图 WebP 等格式缩略图 API 可能失败，回退取第一帧再缩小
            guard let frame = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: false,
            ] as CFDictionary) else { return nil }
            let spec = ResizeSpec(width: 120, height: 120, keepAspectRatio: true)
            let scaled = ImageResizer.apply(spec, to: frame) ?? frame
            return NSImage(cgImage: scaled, size: .zero)
        }.value
    }
}
