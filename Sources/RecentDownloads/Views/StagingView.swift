import SwiftUI
import UniformTypeIdentifiers
import RecentDownloadsCore

/// 中转站视图：拖入区域 + 文件列表 + 清空。
struct StagingView: View {
    @StateObject var store: StagingStore
    let onDragBegin: () -> Void
    let onDragEnd: () -> Void

    @State private var isDragOver = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 拖入区域
            VStack(spacing: 4) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 22))
                    .foregroundStyle(isDragOver ? Color.accentColor : Color.secondary)
                Text("拖入文件到此（只记录路径）")
                    .font(.callout)
                    .foregroundStyle(isDragOver ? Color.accentColor : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isDragOver ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [6])
                    )
            )
            .padding(.horizontal)
            .padding(.vertical, 8)
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                handleDrop(providers: providers)
            }

            if !store.files.isEmpty {
                HStack {
                    Text("共 \(store.files.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空") { store.clear() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            Divider()

            if store.files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("中转站为空")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.files) { item in
                            HStack(spacing: 8) {
                                DraggableFileRow(
                                    file: DownloadFile(
                                        url: item.url,
                                        displayName: item.displayName,
                                        sortDate: item.addedDate,
                                        byteSize: nil
                                    ),
                                    onDragBegin: onDragBegin,
                                    onDragEnd: onDragEnd
                                )

                                Button {
                                    store.remove(url: item.url)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.trailing, 8)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Task { @MainActor in
                            store.add(urls: [url])
                        }
                    } else if let url = item as? URL {
                        Task { @MainActor in
                            store.add(urls: [url])
                        }
                    }
                }
            }
        }
        return true
    }
}