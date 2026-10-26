import Testing
import Foundation
@testable import RecentDownloadsCore

/// 线程安全的计数器，用于断言回调次数。
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
    }
}

@Suite("DownloadsWatcher 目录监听")
final class DownloadsWatcherTests {
    @Test("防抖：延迟窗口内多次文件事件只回调一次")
    func debouncesMultipleEvents() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = CallCounter()
        let watcher = try DownloadsWatcher(directory: dir, debounceDelay: 0.4) {
            counter.increment()
        }
        watcher.start()
        defer { watcher.stop() }

        // 在防抖窗口内连续创建多个文件。
        for i in 0..<5 {
            try Data("x".utf8).write(to: dir.appendingPathComponent("file-\(i).txt"))
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        // 等待防抖窗口 + 事件传播缓冲。
        try await Task.sleep(nanoseconds: 900_000_000)

        #expect(counter.count == 1)
    }

    @Test("start 和 stop 幂等，stop 后不再回调")
    func stopStopsCallbacks() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watcher-stop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = CallCounter()
        let watcher = try DownloadsWatcher(directory: dir, debounceDelay: 0.1) {
            counter.increment()
        }

        watcher.start()
        watcher.start() // 幂等
        try Data("x".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try await Task.sleep(nanoseconds: 500_000_000)
        let afterStart = counter.count
        #expect(afterStart >= 1)

        watcher.stop()
        watcher.stop() // 幂等
        try Data("x".utf8).write(to: dir.appendingPathComponent("b.txt"))
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(counter.count == afterStart)
    }

    @Test("目录不存在时初始化抛出错误")
    func missingDirectoryThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
        #expect(throws: (any Error).self) {
            _ = try DownloadsWatcher(directory: missing) {}
        }
    }
}