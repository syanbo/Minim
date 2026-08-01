import SwiftUI
import UniformTypeIdentifiers
import MinimCore

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(UpdateChecker.self) private var updates
    @State private var isDropTargeted = false

    private var updateMessage: String {
        switch updates.state {
        case .idle, .checking: "正在检查…"
        case .upToDate(let current): "已是最新版本（\(current)）"
        case .updateAvailable(let version, _): "有新版本 \(version)，当前 \(updates.currentVersion)"
        case .failed(let reason): reason
        }
    }

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            SettingsBar()
            Divider()
            ZStack {
                if store.tasks.isEmpty {
                    DropZoneView(isTargeted: isDropTargeted)
                } else {
                    TaskListView()
                }
                if isDropTargeted && !store.tasks.isEmpty {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .background(Color.accentColor.opacity(0.06))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            StatusBar()
        }
        // 最小宽度加在主内容区：面板展开时窗口被撑大，主区域不会被挤压。
        // 880 = 工具条 7 个控件的实测本征宽度（动图按钮标签最长时）
        .frame(minWidth: 880, minHeight: 500)
        .dropDestination(for: URL.self) { urls, _ in
            store.add(urls: urls)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) { isDropTargeted = targeted }
        }
        .inspector(isPresented: Binding(
            get: { store.compareTask != nil },
            set: { if !$0 { store.compareTask = nil } }
        )) {
            if let task = store.compareTask {
                // 按 id 取实时任务：预览中开始压缩后，面板能跟随状态更新
                ComparePanel(task: store.tasks.first { $0.id == task.id } ?? task)
                    .inspectorColumnWidth(min: 420, ideal: 640, max: 900)
            }
        }
        .fileImporter(
            isPresented: $store.presentFileImporter,
            allowedContentTypes: [.png, .jpeg, .gif, .webP, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                store.add(urls: urls)
            }
        }
        .navigationTitle("轻图")
        .alert("检查更新", isPresented: Binding(
            get: { updates.presentsResult },
            set: { if !$0 { updates.dismiss() } }
        )) {
            if case .updateAvailable(_, let url) = updates.state {
                Button("前往下载") {
                    NSWorkspace.shared.open(url)
                    updates.dismiss()
                }
                Button("稍后", role: .cancel) { updates.dismiss() }
            } else {
                Button("好") { updates.dismiss() }
            }
        } message: {
            Text(updateMessage)
        }
    }
}

struct StatusBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack {
            if store.tasks.isEmpty {
                Text("拖入 PNG / JPG / WebP / GIF / APNG 开始压缩")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(store.doneCount)/\(store.tasks.count) 张完成")
                    .foregroundStyle(.secondary)
                if store.totalSaved > 0 {
                    Text("共节省 \(ByteFormatter.string(store.totalSaved))")
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                }
                // 计算属性会全量扫描任务并构造一次 settings，一次 body 只求值一次
                let staleCount = store.staleTaskIDs.count
                if staleCount > 0 {
                    Button {
                        store.recompressStale()
                    } label: {
                        Label("重新生成（\(staleCount)）", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                    .help("工具栏设置已变更，点击按新设置重新压缩")
                }
                if store.awaitingAnimCount > 1 {
                    Button {
                        store.startAllAnim()
                    } label: {
                        Label("开始全部动图（\(store.awaitingAnimCount)）", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                }
            }
            Spacer()
            if store.runningCount > 0 {
                Button("全部取消") { store.cancelAll() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            if store.finishedCount > 0 {
                // 只清理已完成/失败，待开始的动图会保留
                Button("清空已完成") { store.clearFinished() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            if !store.tasks.isEmpty {
                Button("全部移除") { store.removeAll() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("清空整个列表，包括还没开始的动图")
            }
        }
        .font(.callout)
        // 固定高度：对比面板的底部条按同一个数值排版，分隔线才对得齐
        .frame(height: BarMetrics.status)
        .padding(.horizontal, 16)
        .background(.bar)
    }
}
