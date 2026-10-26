import Foundation

/// 中转站条目：只记录来源路径，不复制文件。
public struct StagedFile: Identifiable, Equatable, Sendable {
    public let url: URL
    public let displayName: String
    public let addedDate: Date

    public var id: URL { url }

    public init(url: URL, displayName: String, addedDate: Date = Date()) {
        self.url = url
        self.displayName = displayName
        self.addedDate = addedDate
    }
}

/// 中转站状态：文件来源路径列表，支持添加、移除、清空。
@MainActor
public final class StagingStore: ObservableObject {
    @Published public private(set) var files: [StagedFile] = []

    public init() {}

    /// 添加文件路径（去重：已存在的移到最前）。只记录路径，不复制文件。
    public func add(urls: [URL]) {
        for url in urls {
            files.removeAll { $0.url == url }
            files.insert(StagedFile(url: url, displayName: url.lastPathComponent), at: 0)
        }
    }

    /// 移除单条。
    public func remove(url: URL) {
        files.removeAll { $0.url == url }
    }

    /// 清空中转站。
    public func clear() {
        files.removeAll()
    }
}
