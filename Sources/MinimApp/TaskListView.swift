import SwiftUI
import MinimCore

struct TaskListView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List(store.tasks) { task in
            TaskRowView(task: task)
                .listRowSeparator(.visible)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}
