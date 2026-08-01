import SwiftUI

struct DropZoneView: View {
    @Environment(AppStore.self) private var store
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text(isTargeted ? "松手开始压缩" : "拖入图片或文件夹")
                .font(.title3)
                .foregroundStyle(isTargeted ? Color.accentColor : .primary)
            Text("静图 PNG · JPG　动图 GIF · APNG · WebP")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("选择图片…") {
                store.presentFileImporter = true
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [10])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
                .padding(24)
        )
    }
}
