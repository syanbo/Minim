import SwiftUI

@main
struct MinimApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
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
        }
    }
}
