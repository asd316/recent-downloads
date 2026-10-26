import Foundation
import Combine

/// 监控模式的状态管理。
@MainActor
public final class WatchStore: ObservableObject {
    @Published public private(set) var directory: URL?
    @Published public private(set) var files: [DownloadFile] = []
    @Published public var excludePatterns: [String] = ["^\\."] {
        didSet { rebuildExcluder() }
    }

    private let tracker = ChangeTracker()
    private var watcher: DownloadsWatcher?
    private let scanner = DownloadsScanner(skipHidden: false, filterTemporary: false)
    private var excluder = RegexExcluder(patterns: ["^\\."])

    public init() {}

    /// 切换监控目录。会停止旧 watcher，启动新 watcher 并立即扫描。
    public func setDirectory(_ url: URL) {
        directory = url
        watcher?.stop()
        watcher = nil
        // 重置 tracker（新目录从零开始）
        tracker.reset()
        do {
            let w = try DownloadsWatcher(directory: url) { [weak self] in
                Task { @MainActor in await self?.refresh() }
            }
            w.start()
            watcher = w
        } catch {
            NSLog("WatchStore watcher 创建失败: \(error)")
        }
        Task { await refresh() }
    }

    /// 停止监控。
    public func stop() {
        watcher?.stop()
        watcher = nil
        directory = nil
        files = []
        tracker.reset()
    }

    /// 重新扫描并计算变化。
    public func refresh() async {
        guard let dir = directory else { return }
        guard let allFiles = try? await scanner.scan(directory: dir, limit: 100) else { return }
        _ = tracker.update(with: allFiles)
        applyFilters()
    }

    private func applyFilters() {
        let recent = tracker.recentFiles
        files = recent
            .filter { !excluder.shouldExclude($0.displayName) }
            .prefix(10)
            .map { $0 }
    }

    private func rebuildExcluder() {
        excluder = RegexExcluder(patterns: excludePatterns)
        applyFilters()
    }
}

extension ChangeTracker {
    func reset() {
        _ = update(with: [])
    }
}