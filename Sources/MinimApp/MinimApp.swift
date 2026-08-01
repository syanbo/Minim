import SwiftUI

@main
struct MinimApp: App {
    @State private var store = AppStore()
    @State private var updates = UpdateChecker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(updates)
                .task { updates.checkOnLaunchIfNeeded() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("添加图片…") {
                    store.presentFileImporter = true
                }
                .keyboardShortcut("o")
                Button("清空列表") {
                    store.clearFinished()
                }
                .keyboardShortcut("k")
            }
            // 更新相关放「关于」之后，不占工具条
            CommandGroup(after: .appInfo) {
                Divider()
                Button("检查更新…") { updates.checkNow() }
                Toggle("启动时自动检查更新", isOn: Binding(
                    get: { updates.autoCheckEnabled },
                    set: { updates.autoCheckEnabled = $0 }
                ))
            }
        }
    }
}
