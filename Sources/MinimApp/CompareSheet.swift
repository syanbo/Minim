import SwiftUI
import AppKit
import MinimCore

/// 侧边对比面板：原图与压缩结果左右直接对比
struct ComparePanel: View {
    @Environment(AppStore.self) private var store
    let task: ImageTask

    /// id 用标签而非位置序号：候选集合会随开关增减，
    /// 位置编号会让用户当前选中的那一项在重新生成后莫名跳回主输出
    private struct Variant: Identifiable, Hashable {
        var id: String { label }
        let label: String
        let url: URL
        let size: Int64
    }

    @State private var selectedVariant = ""
    @State private var originalImage: NSImage?
    @State private var outputImage: NSImage?
    /// 像素尺寸随图一起在后台读一次；放计算属性里会让每次 body 求值都做磁盘 I/O
    @State private var originalPixelSize: (width: Int, height: Int)?
    @State private var outputPixelSize: (width: Int, height: Int)?
    /// 预览底色：棋盘 / 白底 / 黑底（记忆上次选择）
    @AppStorage("compareBackground") private var background = "checker"

    private var result: CompressionResult? {
        task.state.result
    }

    private var variants: [Variant] {
        guard let result else { return [] }
        var list = [Variant(
            label: result.outputURL.pathExtension.uppercased(),
            url: result.outputURL,
            size: result.outputSize
        )]
        // 额外输出（WebP / JPG / PNG）地位相同，顺序跟随 result.converted
        list += result.converted.map {
            Variant(label: $0.label, url: $0.url, size: $0.size)
        }
        return list
    }

    private var currentVariant: Variant? {
        variants.first { $0.id == selectedVariant } ?? variants.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            compareArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .task(id: "\(task.id)-\(selectedVariant)-\(result?.outputURL.path ?? "")") {
            originalImage = nil
            outputImage = nil
            await loadImages()
        }
    }

    // MARK: - 顶部信息

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Text(task.sourceURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    store.compareTask = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("收起对比面板")
            }
            HStack(spacing: 8) {
                if result == nil {
                    Text(ByteFormatter.string(task.originalSize))
                } else if let result, let variant = currentVariant {
                    Text(ByteFormatter.string(result.originalSize))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(ByteFormatter.string(variant.size))
                        .fontWeight(.medium)
                    let ratio = 1 - Double(variant.size) / Double(max(result.originalSize, 1))
                    Text(ByteFormatter.ratioString(ratio))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            (ratio > 0 ? Color.green : Color.orange).opacity(0.15),
                            in: Capsule()
                        )
                        .foregroundStyle(ratio > 0 ? .green : .orange)
                }
                Spacer()
            }
            .font(.callout)
        }
        // 高度对齐主区域的「标题栏 + 工具条」，两侧分隔线连成一条线；
        // 产物切换器因此挪到了底部条，头部只放文件名与体积
        .frame(height: BarMetrics.inspectorHeader)
        .padding(.horizontal, 14)
    }

    // MARK: - 左右直接对比

    /// 未压缩时单栏预览原图，压缩后左右对比；动图两侧各自实时播放
    @ViewBuilder
    private var compareArea: some View {
        if task.isAnimated || originalImage != nil {
            HStack(spacing: 10) {
                pane(title: "原图", url: task.sourceURL, still: originalImage,
                     pixelSize: originalPixelSize)
                if result != nil {
                    pane(title: "压缩后", url: currentVariant?.url, still: outputImage,
                         pixelSize: outputPixelSize)
                }
            }
            .padding(12)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func pane(
        title: String, url: URL?, still: NSImage?, pixelSize: (width: Int, height: Int)?
    ) -> some View {
        comparePane(title: title, pixelSize: pixelSize) {
            if task.isAnimated {
                // 动图带逐帧控制条：可暂停、拖动选帧、把当前帧导出成静态图
                if let url { AnimatedPlayerView(url: url, showsFrameControls: true) }
            } else if let still {
                Image(nsImage: still)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
    }

    private func comparePane<Content: View>(
        title: String, pixelSize: (width: Int, height: Int)?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                switch background {
                case "white": Color.white
                case "black": Color.black
                default: CheckerboardBackground()
                }
                content()
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(pixelSize.map { "\(title) · \($0.width)×\($0.height)" } ?? title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [currentVariant?.url ?? task.sourceURL]
                )
            } label: {
                Image(systemName: "folder")
            }
            .help("在 Finder 中显示")
            Spacer(minLength: 8)
            if variants.count > 1 {
                Picker("对比对象", selection: $selectedVariant) {
                    ForEach(variants) { variant in
                        Text(variant.label).tag(variant.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help("选择与原图对比的产物")
            }
            Picker("底色", selection: $background) {
                Text("棋盘").tag("checker")
                Text("白").tag("white")
                Text("黑").tag("black")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help("预览底色（透明区域的衬底）")
        }
        // 与状态栏等高，分隔线对齐
        .frame(height: BarMetrics.status)
        .padding(.horizontal, 14)
    }

    private func loadImages() async {
        let sourceURL = task.sourceURL
        let outputURL = currentVariant?.url
        // 动图由 AnimatedPlayerView 自行解码播放，这里只取尺寸
        let isAnimated = task.isAnimated
        // 显式标注类型：三元表达式里 nil 与 flatMap 结果混在元组中时，
        // 旧版编译器会把它推断成 NSObject? 而报错
        let loaded = await Task.detached(priority: .userInitiated) {
            let original: NSImage? = isAnimated ? nil : NSImage(contentsOf: sourceURL)
            let output: NSImage? = isAnimated
                ? nil
                : outputURL.flatMap { NSImage(contentsOf: $0) }
            return (
                original,
                output,
                ImageResizer.pixelSize(of: sourceURL),
                outputURL.flatMap { ImageResizer.pixelSize(of: $0) }
            )
        }.value
        originalImage = loaded.0
        outputImage = loaded.1
        originalPixelSize = loaded.2
        outputPixelSize = loaded.3
    }
}

/// 棋盘格背景，便于观察透明区域
struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.9)))
            for row in 0..<Int(ceil(size.height / cell)) {
                for col in 0..<Int(ceil(size.width / cell)) where (row + col) % 2 == 0 {
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(col) * cell, y: CGFloat(row) * cell,
                            width: cell, height: cell
                        )),
                        with: .color(.gray.opacity(0.25))
                    )
                }
            }
        }
    }
}
