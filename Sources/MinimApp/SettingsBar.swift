import SwiftUI
import MinimCore

struct SettingsBar: View {
    @Environment(AppStore.self) private var store
    @State private var showResizePopover = false
    @State private var showAnimPopover = false

    /// 动图按钮标签：概括当前默认参数
    private var animButtonLabel: String {
        var parts = [store.animOutput.label]
        if !store.animFrameKeep.isIdentity { parts.append(store.animFrameKeep.label) }
        if store.animSpeed != 1 { parts.append(String(format: "%.1fx", store.animSpeed)) }
        return parts.joined(separator: " · ")
    }

    private var resizeButtonLabel: String {
        guard store.resizeEnabled,
              store.resizeWidth > 0 || store.resizeHeight > 0 else { return "裁剪缩放" }
        let w = store.resizeWidth > 0 ? "\(store.resizeWidth)" : "原"
        let h = store.resizeHeight > 0 ? "\(store.resizeHeight)" : "原"
        return "\(w)×\(h)"
    }

    var body: some View {
        @Bindable var store = store
        // 固定间距、整体居左；末尾 Spacer 吸收多余宽度，最小宽度时右边距与左边一致
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("质量")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Picker("质量", selection: $store.quality) {
                    ForEach(QualityPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            .help("压缩质量档位；「默认」按原图质量智能决定，「保真」接近无损")


            Toggle(isOn: $store.generateWebP) {
                Text("WebP")
                    .fixedSize()
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .fixedSize()
            .help("压缩的同时输出同名 .webp 文件到输出文件夹（GIF 不支持）")


            Toggle(isOn: $store.autoConvert) {
                Text("JPG")
                    .fixedSize()
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .fixedSize()
            .help("PNG / 静态 WebP 额外输出一张 JPG（名字-jpg.jpg，透明部分填白底），不替换主输出")


            Toggle(isOn: $store.convertToPNG) {
                Text("PNG")
                    .fixedSize()
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .fixedSize()
            .help("JPG / 静态 WebP 额外输出一张无损 PNG（名字-png.png），不替换主输出")


            Picker("输出", selection: $store.replaceOriginal) {
                Label("\(OutputMode.defaultSubdirName) 文件夹", systemImage: "folder")
                    .tag(false)
                Label("替换原图", systemImage: "arrow.triangle.2.circlepath")
                    .tag(true)
            }
            .labelsHidden()
            .fixedSize()
            .help("默认输出到源目录下的 \(OutputMode.defaultSubdirName) 文件夹，文件名保持不变；替换原图模式不保留原图，只对之后添加的图片生效")


            Button {
                showResizePopover.toggle()
            } label: {
                Label(resizeButtonLabel, systemImage: "crop")
                    .fixedSize()
            }
            .buttonStyle(.bordered)
            .tint(store.resizeEnabled ? Color.accentColor : nil)
            .help("按设置的宽高裁剪或缩放图片（超过原图尺寸时按原图，不放大）")
            .popover(isPresented: $showResizePopover, arrowEdge: .bottom) {
                ResizePopover()
                    .environment(store)
            }


            Button {
                showAnimPopover.toggle()
            } label: {
                Label(animButtonLabel, systemImage: "film")
                    .fixedSize()
            }
            .buttonStyle(.bordered)
            .help("动图（GIF / 动图 WebP / APNG）的默认输出格式、抽帧、速度与循环；单行可单独覆盖")
            .popover(isPresented: $showAnimPopover, arrowEdge: .bottom) {
                AnimPopover()
                    .environment(store)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }
}
