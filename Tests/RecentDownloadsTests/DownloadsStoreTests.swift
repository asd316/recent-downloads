import Testing
import Foundation
import Combine
@testable import RecentDownloadsCore

/// 可控行为的 fake scanner，用于隔离测试 store 的状态机。
struct FakeScanner: DownloadsScanning {
    var handler: @Sendable (URL, Int) async throws -> [DownloadFile]

    func scan(directory: URL, limit: Int) async throws -> [DownloadFile] {
        try await handler(directory, limit)
    }
}

@Suite("DownloadsStore 状态管理")
@MainActor
final class DownloadsStoreTests {
    let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-tests-\(UUID().uuidString)")
    }

    private func makeFile(named name: String) -> DownloadFile {
        DownloadFile(
            url: directory.appendingPathComponent(name),
            displayName: name,
            sortDate: Date(timeIntervalSince1970: 1_700_000_000),
            byteSize: 10
        )
    }

    @Test("初始状态为 loading")
    func initialStateIsLoading() {
        let store = DownloadsStore(
            scanner: FakeScanner { _, _ in [] },
            directory: directory
        )
        #expect(store.state == .loading)
    }

    @Test("扫描成功进入 loaded 状态")
    func refreshSuccess() async {
        let files = [makeFile(named: "a.txt"), makeFile(named: "b.txt")]
        let store = DownloadsStore(
            scanner: FakeScanner { _, _ in files },
            directory: directory
        )
        await store.refresh()
        #expect(store.state == .loaded(files))
    }

    @Test("空目录进入 loaded 空列表")
    func refreshEmptyDirectory() async {
        let store = DownloadsStore(
            scanner: FakeScanner { _, _ in [] },
            directory: directory
        )
        await store.refresh()
        #expect(store.state == .loaded([]))
    }

    @Test("扫描失败进入 failed 状态")
    func refreshFailure() async {
        let store = DownloadsStore(
            scanner: FakeScanner { _, _ in throw TestError.scanFailed },
            directory: directory
        )
        await store.refresh()
        if case .failed(let message) = store.state {
            #expect(!message.isEmpty)
        } else {
            Issue.record("期望 failed 状态，实际为 \(store.state)")
        }
    }

    @Test("目录不存在时给出可读错误消息")
    func missingDirectoryMessage() async {
        let store = DownloadsStore(
            scanner: FakeScanner { _, _ in
                throw CocoaError(.fileReadNoSuchFile)
            },
            directory: directory
        )
        await store.refresh()
        #expect(store.state == .failed("下载文件夹不存在"))
    }
}

enum TestError: Error {
    case scanFailed
}