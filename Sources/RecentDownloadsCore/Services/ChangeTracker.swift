import Foundation

/// 追踪目录中文件的「变化先后顺序」。
///
/// 每次拿到新扫描结果时与上次快照对比：
/// - 新增文件：作为变化插入队首。
/// - 已有文件内容/大小变化：作为变化移到队首。
/// - 已消失文件：从追踪列表中移除。
///
/// 首次更新把所有文件视为初始列表（按扫描返回顺序），不产生「变化」。
public final class ChangeTracker: @unchecked Sendable {
    /// 文件 URL 的唯一键：路径 + 排序日期 + 大小。
    private struct Key: Hashable {
        let url: URL
        let sortDate: Date
        let byteSize: Int64?
    }

    private let lock = NSLock()
    /// 按变化时间倒序（队首最新）的去重文件列表。
    private var ordered: [DownloadFile] = []
    /// 上次快照：URL -> 内容指纹。
    private var snapshot: [URL: Key] = [:]

    public init() {}

    /// 当前追踪的文件，按变化先后倒序。
    public var recentFiles: [DownloadFile] {
        lock.lock()
        defer { lock.unlock() }
        return ordered
    }

    /// 处理一次扫描结果，返回本次「发生变化」的文件（按变化先后顺序，最新在前）。
    /// 首次调用返回空数组（建立基准快照）。
    /// - Parameters:
    ///   - files: 本次扫描到的文件（已按日期倒序）。
    ///   - now: 当前时间，用于判定变化顺序。
    public func update(with files: [DownloadFile], now: Date = Date()) -> [DownloadFile] {
        lock.lock()
        defer { lock.unlock() }

        let isFirstUpdate = snapshot.isEmpty

        var newSnapshot: [URL: Key] = [:]
        for file in files {
            newSnapshot[file.url] = Key(url: file.url, sortDate: file.sortDate, byteSize: file.byteSize)
        }

        // 移除已消失的文件。
        ordered.removeAll { newSnapshot[$0.url] == nil }

        // 判定变化：新增或指纹变化。
        var changed: [DownloadFile] = []
        for file in files {
            let key = newSnapshot[file.url]!
            let isNew = snapshot[file.url] == nil
            let isModified = !isNew && snapshot[file.url] != key
            if isNew || isModified {
                changed.append(file)
            }
        }

        if isFirstUpdate {
            // 首次：按日期倒序建立初始列表。
            ordered = files.sorted { $0.sortDate > $1.sortDate }
        } else {
            // 变化文件插到队首（最新变化在最前）。
            for file in changed.reversed() {
                ordered.removeAll { $0.url == file.url }
                ordered.insert(file, at: 0)
            }
        }

        snapshot = newSnapshot
        return isFirstUpdate ? [] : changed
    }
}
