import SwiftUI
import RecentDownloadsCore

/// 弹层内容：三种模式（下载 / 监控 / 中转站）+ 底部操作。
struct MenuBarContentView: View {
    @StateObject var downloadsStore: DownloadsStore
    @StateObject var watchStore: WatchStore
    @StateObject var stagingStore: StagingStore
    let onOpenDownloads: () -> Void
    let onQuit: () -> Void
    let onSelectWatchDirectory: () -> Void
    let onDragBegin: () -> Void
    let onDragEnd: () -> Void

    @State private var mode: AppMode = .downloads

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            switch mode {
            case .downloads:
                downloadsContent
            case .watch:
                WatchView(
                    store: watchStore,
                    onSelectDirectory: onSelectWatchDirectory,
                    onDragBegin: onDragBegin,
                    onDragEnd: onDragEnd
                )
            case .staging:
                StagingView(
                    store: stagingStore,
                    onDragBegin: onDragBegin,
                    onDragEnd: onDragEnd
                )
            }

            Divider()

            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Text("最近下载")
                .font(.headline)
            Spacer()
            Picker("模式", selection: $mode) {
                ForEach(AppMode.allCases, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var downloadsContent: some View {
        switch downloadsStore.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

        case .loaded(let files) where files.isEmpty:
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("下载文件夹中暂无文件")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()

        case .loaded(let files):
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(files) { file in
                        DraggableFileRow(file: file, onDragBegin: onDragBegin, onDragEnd: onDragEnd)
                        Divider()
                    }
                }
            }

        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("重试") {
                    Task { await downloadsStore.refresh() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private var footer: some View {
        HStack {
            if mode == .downloads {
                Button(action: onOpenDownloads) {
                    Label("打开下载文件夹", systemImage: "folder")
                }
                .buttonStyle(.borderless)
            } else {
                Text(mode.footerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("退出", action: onQuit)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

enum AppMode: String, CaseIterable {
    case downloads
    case watch
    case staging

    var label: String {
        switch self {
        case .downloads: return "下载"
        case .watch: return "监控"
        case .staging: return "中转站"
        }
    }

    var footerHint: String {
        switch self {
        case .downloads: return ""
        case .watch: return "按变化先后排列，最多 10 项"
        case .staging: return "拖入即记录路径"
        }
    }
}