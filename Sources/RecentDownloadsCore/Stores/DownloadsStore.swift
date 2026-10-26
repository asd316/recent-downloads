import Combine
import Foundation

/// 界面状态的三态枚举。
public enum DownloadsViewState: Equatable, Sendable {
    case loading
    case loaded([DownloadFile])
    case failed(String)
}

/// 管理下载文件列表的界面状态。
///
/// 每次 `refresh()` 在后台执行扫描，完成后在主线程更新状态。
/// 使用 generation token 处理并发：只有最新发起的 `refresh()` 可以更新状态。
@MainActor
public final class DownloadsStore: ObservableObject {
    @Published public private(set) var state: DownloadsViewState = .loading

    private let scanner: any DownloadsScanning
    private let directory: URL
    private let limit: Int
    private var generation = 0

    public init(scanner: any DownloadsScanning, directory: URL, limit: Int = 15) {
        self.scanner = scanner
        self.directory = directory
        self.limit = limit
    }

    public func refresh() async {
        let currentGeneration = generation + 1
        generation = currentGeneration

        // 已有内容时保留显示，不切 loading；否则设为 loading。
        if case .loaded = state {
            // 保留
        } else {
            state = .loading
        }

        let files: [DownloadFile]
        do {
            files = try await scanner.scan(directory: directory, limit: limit)
        } catch {
            guard generation == currentGeneration else { return }
            state = .failed(Self.userFacingMessage(for: error))
            return
        }
        guard generation == currentGeneration else { return }
        state = .loaded(files)
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let cocoaError = error as? CocoaError {
            switch cocoaError.code {
            case .fileReadNoSuchFile, .fileNoSuchFile:
                return "下载文件夹不存在"
            default:
                break
            }
        }
        return "无法读取下载文件夹"
    }
}