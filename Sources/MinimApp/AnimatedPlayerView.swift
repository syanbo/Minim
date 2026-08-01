import SwiftUI
import MinimCore

/// 动图播放器：解码全部帧后按各帧延时播放；
/// 遵守文件的循环次数（0=无限），非无限循环播完后停在末帧并显示「重新播放」
struct AnimatedPlayerView: View {
    let url: URL

    @State private var animation: AnimatedImage.Animation?
    @State private var staticImage: NSImage?
    @State private var frameIndex = 0
    @State private var finished = false
    @State private var playTask: Task<Void, Never>?

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
                if finished {
                    replayButton
                }
            } else if let staticImage {
                Image(nsImage: staticImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            playTask?.cancel()
            animation = nil
            staticImage = nil
            finished = false
            await load()
            startPlayback()
        }
        .onDisappear { playTask?.cancel() }
    }

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

    private func load() async {
        let url = self.url
        let loaded = await Task.detached(priority: .userInitiated) {
            () -> (AnimatedImage.Animation?, NSImage?) in
            if let anim = AnimatedImage.decode(url) {
                // 预览用不到原始分辨率，超大动图缩到 1200px 内省内存
                let spec = ResizeSpec(width: 1200, height: 1200, keepAspectRatio: true)
                return (AnimatedImage.mapImages(anim) { ImageResizer.apply(spec, to: $0) }, nil)
            }
            return (nil, NSImage(contentsOf: url))
        }.value
        animation = loaded.0
        staticImage = loaded.1
    }

    private func startPlayback() {
        playTask?.cancel()
        finished = false
        frameIndex = 0
        guard let animation, animation.frames.count > 1 else { return }
        let frames = animation.frames
        let loopCount = animation.loopCount
        playTask = Task { @MainActor in
            var playedLoops = 0
            while !Task.isCancelled {
                for (index, frame) in frames.enumerated() {
                    frameIndex = index
                    try? await Task.sleep(nanoseconds: UInt64(max(frame.delayMs, 10)) * 1_000_000)
                    if Task.isCancelled { return }
                }
                playedLoops += 1
                if loopCount != 0 && playedLoops >= loopCount {
                    finished = true
                    return
                }
            }
        }
    }
}
