import Foundation

/// 不可变的文件展示模型。
public struct DownloadFile: Identifiable, Equatable, Sendable {
    public let url: URL
    public let displayName: String
    public let sortDate: Date
    public let byteSize: Int64?

    public var id: URL { url }

    public init(url: URL, displayName: String, sortDate: Date, byteSize: Int64?) {
        self.url = url
        self.displayName = displayName
        self.sortDate = sortDate
        self.byteSize = byteSize
    }
}