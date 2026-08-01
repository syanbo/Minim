import SwiftUI
import AppKit
import MinimCore

/// 动图播放器：解码全部帧后按各帧延时播放；
/// 遵守文件的循环次数（0=无限），非无限循环播完后停在末帧并显示「重新播放」。
/// showsFrameControls = true 时底部出现逐帧控制条（暂停 / 拖动选帧 / 导出当前帧）
struct AnimatedPlayerView: View {
    let url: URL
    /// 是否显示逐帧控制条（对比面板开，其他地方的纯预览不需要）
    var showsFrameControls = false

    @State private var animation: AnimatedImage.Animation?
    @State private var staticImage: NSImage?
    @State private var frameIndex = 0
    @State private var finished = false
    @State private var paused = false
    @State private var playTask: Task<Void, Never>?
    /// 导出结果提示，几秒后自动消失
    @State private var exportNote: String?
    @State private var exportNoteIsError = false

    private var frameCount: Int { animation?.frames.count ?? 0 }

    var body: some View {
        ZStack {
            if let animation {
                Image(
                    animation.frames[min(frameIndex, animation.frames.count - 1)].image,
                    scale: 1, label: Text("")
                )
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                // 有控制条时播放按钮已经能重播，不再叠一个大按钮挡画面
                if finished && !showsFrameControls {
                    replayButton
                }
                if showsFrameControls, animation.frames.count > 1 {
                    VStack {
                        Spacer()
                        frameControls
                    }
                    .padding(8)
                }
            } else if let staticImage {
                Image(nsImage: staticImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ProgressView()
            }
            if let exportNote {
                VStack {
                    noteBadge(exportNote)
                    Spacer()
                }
                .padding(8)
            }
        }
        .task(id: url) {
            playTask?.cancel()
            animation = nil
            staticImage = nil
            finished = false
            paused = false
            await load()
            startPlayback()
        }
        .onDisappear { playTask?.cancel() }
    }

    // MARK: - 覆盖层

    private var replayButton: some View {
        Button {
            startPlayback()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                Text("重新播放")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.6), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 逐帧控制条：播放/暂停 · 帧滑杆 · 第 N/M 帧 · 导出当前帧
    private var frameControls: some View {
        HStack(spacing: 8) {
            Button {
                if paused || finished {
                    startPlayback(from: finished ? 0 : frameIndex)
                } else {
                    pause()
                }
            } label: {
                Image(systemName: (paused || finished) ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(paused || finished ? "播放" : "暂停")

            Slider(
                value: Binding(
                    get: { Double(frameIndex) },
                    set: { seek(to: Int($0.rounded())) }
                ),
                in: 0...Double(max(frameCount - 1, 1)),
                step: 1
            )
            .controlSize(.mini)
            .help("拖动选帧（会暂停播放）")

            Text("\(frameIndex + 1)/\(frameCount)")
                .font(.caption2)
                .monospacedDigit()
                .fixedSize()

            Menu {
                ForEach(FrameExporter.Format.allCases) { format in
                    Button("导出为 \(format.label)") { export(as: format) }
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("导出当前帧")
            .help("把当前这一帧导出成静态图（原始分辨率）")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
    }

    private func noteBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                (exportNoteIsError ? Color.red : Color.green).opacity(0.85), in: Capsule()
            )
            .foregroundStyle(.white)
    }

    // MARK: - 播放控制

    private func load() async {
        let url = self.url
        let loaded = await Task.detached(priority: .userInitiated) {
            () -> (AnimatedImage.Animation?, NSImage?) in
            if let anim = AnimatedImage.decode(url) {
                // 预览用不到原始分辨率，超大动图缩到 1200px 内省内存。
                // 导出单帧不受影响：FrameExporter 会从原文件重新解码那一帧
                let spec = ResizeSpec(width: 1200, height: 1200, keepAspectRatio: true)
                return (AnimatedImage.mapImages(anim) { ImageResizer.apply(spec, to: $0) }, nil)
            }
            return (nil, NSImage(contentsOf: url))
        }.value
        animation = loaded.0
        staticImage = loaded.1
    }

    /// 从指定帧开始播放（暂停后继续、播完重播都走这里）
    private func startPlayback(from start: Int = 0) {
        playTask?.cancel()
        finished = false
        paused = false
        guard let animation, animation.frames.count > 1 else { return }
        let frames = animation.frames
        let loopCount = animation.loopCount
        var index = min(max(start, 0), frames.count - 1)
        frameIndex = index
        playTask = Task { @MainActor in
            var playedLoops = 0
            while !Task.isCancelled {
                frameIndex = index
                try? await Task.sleep(
                    nanoseconds: UInt64(max(frames[index].delayMs, 10)) * 1_000_000
                )
                if Task.isCancelled { return }
                index += 1
                if index >= frames.count {
                    index = 0
                    playedLoops += 1
                    if loopCount != 0 && playedLoops >= loopCount {
                        frameIndex = frames.count - 1
                        finished = true
                        return
                    }
                }
            }
        }
    }

    private func pause() {
        playTask?.cancel()
        playTask = nil
        paused = true
    }

    /// 拖动滑杆即暂停：一边播一边选帧没有意义
    private func seek(to index: Int) {
        guard frameCount > 0 else { return }
        pause()
        finished = false
        frameIndex = min(max(index, 0), frameCount - 1)
    }

    // MARK: - 导出当前帧

    private func export(as format: FrameExporter.Format) {
        guard frameCount > 0 else { return }
        pause()
        let index = frameIndex
        let source = url
        let panel = NSSavePanel()
        panel.title = "导出第 \(index + 1) 帧"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.directoryURL = source.deletingLastPathComponent()
        panel.nameFieldStringValue = FrameExporter.suggestedName(
            source: source, frameIndex: index, frameCount: frameCount, format: format
        )

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destination = panel.url else { return }
            // 面板里可以手改扩展名，格式以最终文件名为准
            let chosen = FrameExporter.Format
                .detect(fileExtension: destination.pathExtension) ?? format
            Task { @MainActor in
                do {
                    let size = try await Task.detached(priority: .userInitiated) {
                        try FrameExporter.export(
                            source: source, frameIndex: index, format: chosen, to: destination
                        )
                    }.value
                    note(
                        "已导出 \(destination.lastPathComponent) · \(ByteFormatter.string(size))",
                        isError: false
                    )
                } catch {
                    note((error as? ExternalToolError)?.message ?? "导出失败", isError: true)
                }
            }
        }
        // 必须推迟到下一次 runloop 再弹面板：直接在菜单动作里弹，
        // 菜单的事件跟踪还没结束，关掉面板后这个菜单就再也点不开了
        let window = NSApp.keyWindow
        Task { @MainActor in
            if let window {
                panel.beginSheetModal(for: window, completionHandler: handler)
            } else {
                panel.begin(completionHandler: handler)
            }
        }
    }

    private func note(_ text: String, isError: Bool) {
        exportNoteIsError = isError
        withAnimation(.easeOut(duration: 0.15)) { exportNote = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.easeOut(duration: 0.2)) { exportNote = nil }
        }
    }
}
