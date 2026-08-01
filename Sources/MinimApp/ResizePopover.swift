import SwiftUI

/// 裁剪缩放设置面板（复刻原版：开关 + 宽/高 + 限制宽高比）
struct ResizePopover: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $store.resizeEnabled) {
                Text("启用裁剪缩放")
                    .fontWeight(.medium)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Group {
                HStack(spacing: 8) {
                    Text("宽")
                        .foregroundStyle(.secondary)
                    TextField("原图", value: $store.resizeWidth, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                    Text("高")
                        .foregroundStyle(.secondary)
                    TextField("原图", value: $store.resizeHeight, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                    Text("px")
                        .foregroundStyle(.tertiary)
                }

                Picker("模式", selection: $store.resizeKeepRatio) {
                    Text("等比缩放").tag(true)
                    Text("居中裁剪").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(store.resizeKeepRatio
                    ? "等比缩放到宽高框内，不变形、不放大；填 0 的维度按原图。"
                    : "缩放覆盖目标尺寸后居中裁剪，输出精确的宽×高。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!store.resizeEnabled)
            .opacity(store.resizeEnabled ? 1 : 0.5)
        }
        .padding(16)
        .frame(width: 260)
    }
}
