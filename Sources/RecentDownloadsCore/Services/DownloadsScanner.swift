import Foundation

/// 目录扫描抽象，便于在 store 测试中注入 fake。
public protocol DownloadsScanning: Sendable {
    /// 扫描目录并返回按日期倒序的前 `limit` 个文件。
    func scan(directory: URL, limit: Int) async throws -> [DownloadFile]
}

/// 纯文件系统扫描：过滤、排序、截断。
public struct DownloadsScanner: DownloadsScanning {
    /// 未完成下载 / 临时文件的扩展名，比较时忽略大小写。
    private static let temporaryExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "tmp",
    ]

    /// 是否跳过隐藏文件。
    public let skipHidden: Bool
    /// 是否过滤临时扩展名（crdownload/download/part/partial/tmp）。
    public let filterTemporary: Bool

    /// - Parameters:
    ///   - skipHidden: 默认 `true`（跳过点开头的隐藏文件）。监控模式可传 `false`，交给正则排除。
    ///   - filterTemporary: 默认 `true`（过滤未完成下载的临时文件）。监控模式可传 `false`。
    public init(skipHidden: Bool = true, filterTemporary: Bool = true) {
        self.skipHidden = skipHidden
        self.filterTemporary = filterTemporary
    }

    public func scan(directory: URL, limit: Int) async throws -> [DownloadFile] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isHiddenKey,
            .addedToDirectoryDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .nameKey,
        ]

        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: skipHidden ? [.skipsHiddenFiles] : []
        )

        var files: [DownloadFile] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else {
                continue // 单个文件元数据读取失败：跳过，不阻断整体扫描。
            }
            guard values.isRegularFile == true else { continue }
            if skipHidden, values.isHidden == true { continue }
            if filterTemporary, Self.isTemporaryFile(url) { continue }

            // 优先使用 added-to-directory 日期；不可得时回退到内容修改日期。
            let sortDate = values.addedToDirectoryDate ?? values.contentModificationDate
            guard let sortDate else { continue }

            files.append(DownloadFile(
                url: url,
                displayName: values.name ?? url.lastPathComponent,
                sortDate: sortDate,
                byteSize: values.fileSize.map(Int64.init)
            ))
        }

        files.sort { lhs, rhs in
            if lhs.sortDate != rhs.sortDate {
                return lhs.sortDate > rhs.sortDate
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }

        return Array(files.prefix(limit))
    }

    private static func isTemporaryFile(_ url: URL) -> Bool {
        temporaryExtensions.contains(url.pathExtension.lowercased())
    }
}