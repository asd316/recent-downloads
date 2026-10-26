import SwiftUI
import RecentDownloadsCore

/// 监控模式视图：目录选择、正则排除、变化列表。
struct WatchView: View {
    @StateObject var store: WatchStore
    let onSelectDirectory: () -> Void
    let onDragBegin: () -> Void
    let onDragEnd: () -> Void

    @State private var regexText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 目录选择
            HStack {
                if let dir = store.directory {
                    Label(dir.lastPathComponent, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("未选择监控文件夹")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("选择文件夹") { onSelectDirectory() }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal)

            // 正则排除
            HStack(spacing: 4) {
                Text("排除")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("正则（逗号分隔）", text: $regexText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit { applyRegex() }
                Button("应用") { applyRegex() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(.horizontal)

            Divider()

            // 文件列表
            if store.files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "eye")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text(store.directory == nil ? "选择文件夹开始监控" : "监控中，暂无变化")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.files) { file in
                            DraggableFileRow(file: file, onDragBegin: onDragBegin, onDragEnd: onDragEnd)
                            Divider()
                        }
                    }
                }
            }
        }
        .onAppear {
            regexText = store.excludePatterns.joined(separator: ", ")
        }
    }

    private func applyRegex() {
        let patterns = regexText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        store.excludePatterns = patterns.isEmpty ? ["^\\."] : patterns
    }
}