import SwiftUI
import MinimCore

/// 动图默认参数面板（工具栏）：所有动图任务默认跟随这里，
/// 单行改过参数才脱离，方便一次给一批动图设同一套参数
struct AnimPopover: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 12) {
            Text("动图默认参数")
                .fontWeight(.medium)

            LabeledContent("输出格式") {
                Picker("输出格式", selection: $store.animOutput) {
                    ForEach(AnimOutputFormat.allCases, id: \.self) { format in
                        Text(format.label).tag(format)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Text("非 GIF 输入没有「GIF 压缩」档，会自动按自身格式重编码。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("抽帧") {
                Picker("抽帧", selection: $store.animFrameKeep) {
                    ForEach(FrameKeep.presets, id: \.self) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            LabeledContent("速度") {
                HStack(spacing: 6) {
                    Slider(value: $store.animSpeed, in: 0.5...2, step: 0.1)
                        .frame(width: 110)
                    Text(String(format: "%.1fx", store.animSpeed))
                        .monospacedDigit()
                        .foregroundStyle(store.animSpeed == 1 ? .secondary : Color.accentColor)
                }
            }
            Text("抽帧只降帧率、不改变总时长；要变快变慢用速度。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("循环") {
                Picker("循环", selection: $store.animLoopMode) {
                    Text("保留原设置").tag("keep")
                    Text("无限循环").tag("infinite")
                    Text("自定义次数").tag("custom")
                }
                .labelsHidden()
                .fixedSize()
            }
            if store.animLoopMode == "custom" {
                Stepper(value: $store.animLoopCount, in: 1...50) {
                    Text("循环 \(store.animLoopCount) 次")
                }
                .controlSize(.small)
            }

            if store.overriddenAnimCount > 0 {
                Divider()
                HStack(spacing: 8) {
                    Text("\(store.overriddenAnimCount) 个任务已单独调过参数")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("全部跟随") { store.resetAllAnimOverrides() }
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
