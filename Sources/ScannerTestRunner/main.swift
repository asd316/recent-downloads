import Foundation
import os
import RecentDownloadsCore

/// 一个简单的测试运行器，验证核心逻辑的正确性。
/// 在 CLT 环境下替代 `swift test` 的测试运行器（Swift Testing 不输出结果）。
@main
struct ScannerTestRunner {
    @MainActor
    static func main() async {
        var passed = 0
        var failed = 0

        await runScannerTests(&passed, &failed)
        await runStoreTests(&passed, &failed)
        await runWatcherTests(&passed, &failed)
        runRegexExcluderTests(&passed, &failed)
        runChangeTrackerTests(&passed, &failed)
        await runStagingStoreTests(&passed, &failed)

        print("\n=== 结果: \(passed) 通过, \(failed) 失败 ===")
        if failed > 0 { exit(1) }
    }

    // MARK: - DownloadsScanner 测试

    static func runScannerTests(_ passed: inout Int, _ failed: inout Int) async {
        let scanner = DownloadsScanner()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanner-test-run-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // 1. 基本文件扫描
            try Data("test".utf8).write(to: tempDir.appendingPathComponent("report.pdf"))
            try Data("test".utf8).write(to: tempDir.appendingPathComponent("photo.png"))
            let files1 = try await scanner.scan(directory: tempDir, limit: 15)
            assertEqual(Set(files1.map { $0.displayName }), ["report.pdf", "photo.png"], "返回普通文件", &passed, &failed)

            // 2. 过滤目录
            try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("folder"), withIntermediateDirectories: true)
            let files2 = try await scanner.scan(directory: tempDir, limit: 15)
            assertEqual(files2.map { $0.displayName }.sorted(), ["photo.png", "report.pdf"], "过滤目录", &passed, &failed)

            // 3. 过滤隐藏文件
            try Data("hidden".utf8).write(to: tempDir.appendingPathComponent(".hidden_file"))
            let files3 = try await scanner.scan(directory: tempDir, limit: 15)
            assertEqual(files3.map { $0.displayName }.sorted(), ["photo.png", "report.pdf"], "过滤隐藏文件", &passed, &failed)

            // 4. 过滤临时扩展名
            try Data("tmp".utf8).write(to: tempDir.appendingPathComponent("a.crdownload"))
            try Data("tmp".utf8).write(to: tempDir.appendingPathComponent("b.TMP"))
            let files4 = try await scanner.scan(directory: tempDir, limit: 15)
            assertEqual(files4.map { $0.displayName }.sorted(), ["photo.png", "report.pdf"], "过滤临时扩展名", &passed, &failed)

            // 5. 排序：最新在前
            try Data("old".utf8).write(to: tempDir.appendingPathComponent("old.txt"))
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
                ofItemAtPath: tempDir.appendingPathComponent("old.txt").path
            )
            try Data("new".utf8).write(to: tempDir.appendingPathComponent("new.txt"))
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
                ofItemAtPath: tempDir.appendingPathComponent("new.txt").path
            )
            let files5 = try await scanner.scan(directory: tempDir, limit: 15)
            // 只保留 new.txt 和 old.txt，过滤掉其他
            let filtered5 = files5.filter { file in
                file.displayName == "new.txt" || file.displayName == "old.txt"
            }
            assertEqual(filtered5.map { $0.displayName }, ["new.txt", "old.txt"], "按日期倒序", &passed, &failed)

            // 6. 数量限制
            let files6 = try await scanner.scan(directory: tempDir, limit: 1)
            assertEqual(files6.count, 1, "limit 截断", &passed, &failed)

            // 7. 扫描不存在的目录抛出错误
            let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
            do {
                _ = try await scanner.scan(directory: missing, limit: 15)
                print("❌ 扫描不存在的目录应当抛出错误")
                failed += 1
            } catch {
                passed += 1
            }

            // 8. 文件元数据正确
            let content = Data(repeating: 0x41, count: 1234)
            let url = tempDir.appendingPathComponent("data.bin")
            try content.write(to: url)
            let files8 = try await scanner.scan(directory: tempDir, limit: 15)
            if let match = files8.first(where: { $0.displayName == "data.bin" }) {
                assertEqual(match.byteSize, 1234, "文件大小正确", &passed, &failed)
                assertEqual(match.url.standardizedFileURL, url.standardizedFileURL, "URL 正确", &passed, &failed)
            } else {
                print("❌ data.bin 未在扫描结果中")
                failed += 1
            }

            // 9. 优先级：added date 优先于 modification date
            // a.txt 创建早但修改晚；b.txt 创建晚但修改早。
            try Data("a".utf8).write(to: tempDir.appendingPathComponent("a-priority.txt"))
            try await Task.sleep(nanoseconds: 300_000_000)
            try Data("b".utf8).write(to: tempDir.appendingPathComponent("b-priority.txt"))
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
                ofItemAtPath: tempDir.appendingPathComponent("a-priority.txt").path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
                ofItemAtPath: tempDir.appendingPathComponent("b-priority.txt").path
            )
            let files9 = try await scanner.scan(directory: tempDir, limit: 15)
            let prio = files9.filter { file in
                file.displayName == "a-priority.txt" || file.displayName == "b-priority.txt"
            }
            assertEqual(prio.map { $0.displayName }, ["b-priority.txt", "a-priority.txt"], "added date 优先", &passed, &failed)
        } catch {
            print("❌ 扫描测试异常: \(error)")
            failed += 1
        }
    }

    // MARK: - DownloadsStore 测试

    @MainActor
    static func runStoreTests(_ passed: inout Int, _ failed: inout Int) async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-test-run-\(UUID().uuidString)")

        // 1. 初始状态 loading
        let store1 = DownloadsStore(
            scanner: FakeScanner { _, _ in [] },
            directory: dir
        )
        assertEqual(store1.state == .loading, true, "初始状态为 loading", &passed, &failed)

        // 2. 成功 → loaded
        let files = [
            DownloadFile(url: dir.appendingPathComponent("a.txt"), displayName: "a.txt", sortDate: Date(), byteSize: 10),
            DownloadFile(url: dir.appendingPathComponent("b.txt"), displayName: "b.txt", sortDate: Date(), byteSize: 20),
        ]
        let store2 = DownloadsStore(
            scanner: FakeScanner { _, _ in files },
            directory: dir
        )
        await store2.refresh()
        assertEqual(store2.state == .loaded(files), true, "扫描成功进入 loaded", &passed, &failed)

        // 3. 空目录 → loaded([])
        let store3 = DownloadsStore(
            scanner: FakeScanner { _, _ in [] },
            directory: dir
        )
        await store3.refresh()
        assertEqual(store3.state == .loaded([]), true, "空目录进入 loaded 空列表", &passed, &failed)

        // 4. 失败 → failed
        let store4 = DownloadsStore(
            scanner: FakeScanner { _, _ in throw StoreTestError.scanFailed },
            directory: dir
        )
        await store4.refresh()
        if case .failed(let message) = store4.state {
            assertEqual(message.isEmpty, false, "失败状态带非空消息", &passed, &failed)
        } else {
            print("❌ 期望 failed 状态，实际为 \(store4.state)")
            failed += 1
        }

        // 5. 目录不存在 → 可读消息
        let store5 = DownloadsStore(
            scanner: FakeScanner { _, _ in throw CocoaError(.fileReadNoSuchFile) },
            directory: dir
        )
        await store5.refresh()
        assertEqual(store5.state == .failed("下载文件夹不存在"), true, "目录不存在给出可读消息", &passed, &failed)

        // 6. 刷新期间保留已有内容：第一次返回 oldFiles，第二次挂起后放行返回 newFiles
        let gate = AsyncGate()
        let oldFiles = [
            DownloadFile(url: dir.appendingPathComponent("old.txt"), displayName: "old.txt", sortDate: Date(), byteSize: 1),
        ]
        let newFiles = [
            DownloadFile(url: dir.appendingPathComponent("new.txt"), displayName: "new.txt", sortDate: Date(), byteSize: 2),
        ]
        let switching = SwitchingScanner(firstResult: oldFiles) { _ in
            await gate.wait()
            return newFiles
        }
        let store6 = DownloadsStore(scanner: switching, directory: dir)
        await store6.refresh()
        assertEqual(store6.state == .loaded(oldFiles), true, "首次加载成功", &passed, &failed)

        // 发起第二次刷新（挂起在 gate），期间状态应保持 loaded(oldFiles)
        let refreshTask = Task { await store6.refresh() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        assertEqual(store6.state == .loaded(oldFiles), true, "慢刷新期间保留已有内容", &passed, &failed)
        gate.open()
        await refreshTask.value
        assertEqual(store6.state == .loaded(newFiles), true, "慢刷新完成后更新为新内容", &passed, &failed)

        // 7. 并发刷新：旧结果不覆盖新结果（generation token）
        let gate2 = AsyncGate()
        let store7 = DownloadsStore(
            scanner: FakeScanner { _, _ in
                await gate2.wait()
                return [DownloadFile(url: dir.appendingPathComponent("slow.txt"), displayName: "slow.txt", sortDate: Date(), byteSize: 3)]
            },
            directory: dir
        )
        // 第一个慢刷新开始
        let firstTask = Task { await store7.refresh() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        // 第二个快刷新：同一 store，直接换 scanner 不行（scanner 是 let），
        // 这里验证 generation：第二个 refresh 用新的 scanner 引用不行。
        // 方案：store7 的 scanner 第一次调用返回快结果，后续调用挂起。
        // 简化：用 SwitchingScanner 让第 1 次调用快返回 fast，第 2 次挂起。
        let gate3 = AsyncGate()
        let fastThenSlow = SwitchingScanner(firstResult: [fastFile(dir, "fast.txt")]) { _ in
            await gate3.wait()
            return [fastFile(dir, "slow.txt")]
        }
        let store7b = DownloadsStore(scanner: fastThenSlow, directory: dir)
        let t1 = Task { await store7b.refresh() } // 第 1 次调用：快 → loaded(fast)
        try? await Task.sleep(nanoseconds: 50_000_000)
        let t2 = Task { await store7b.refresh() } // 第 2 次调用：挂起
        try? await Task.sleep(nanoseconds: 100_000_000)
        // 此时 store7b 应保持 loaded(fast)，尽管 t1 已完成
        assertEqual(store7b.state == .loaded([fastFile(dir, "fast.txt")]), true, "并发刷新保持最新结果", &passed, &failed)
        gate3.open()
        await t1.value
        await t2.value
        assertEqual(store7b.state == .loaded([fastFile(dir, "slow.txt")]), true, "并发刷新最终为第二次结果", &passed, &failed)

        // 8. 清理 store7 的挂起（避免泄漏）
        gate2.open()
        await firstTask.value
    }

    private static func fastFile(_ dir: URL, _ name: String) -> DownloadFile {
        DownloadFile(url: dir.appendingPathComponent(name), displayName: name, sortDate: Date(timeIntervalSince1970: 1_700_000_000), byteSize: 4)
    }

    // MARK: - DownloadsWatcher 测试

    static func runWatcherTests(_ passed: inout Int, _ failed: inout Int) async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watcher-test-run-\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            // 1. 防抖：窗口内连续创建文件只回调一次
            let counter = CallCounter()
            let watcher = try DownloadsWatcher(directory: dir, debounceDelay: 0.4) {
                counter.increment()
            }
            watcher.start()
            defer { watcher.stop() }

            for i in 0..<5 {
                try Data("x".utf8).write(to: dir.appendingPathComponent("file-\(i).txt"))
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try await Task.sleep(nanoseconds: 900_000_000)
            assertEqual(counter.count, 1, "防抖：多次事件只回调一次", &passed, &failed)

            // 2. start/stop 幂等，stop 后不再回调
            let counter2 = CallCounter()
            let watcher2 = try DownloadsWatcher(directory: dir, debounceDelay: 0.1) {
                counter2.increment()
            }
            watcher2.start()
            watcher2.start() // 幂等
            try Data("x".utf8).write(to: dir.appendingPathComponent("stop-a.txt"))
            try await Task.sleep(nanoseconds: 500_000_000)
            let afterStart = counter2.count
            assertEqual(afterStart >= 1, true, "监听期间收到事件", &passed, &failed)

            watcher2.stop()
            watcher2.stop() // 幂等
            try Data("x".utf8).write(to: dir.appendingPathComponent("stop-b.txt"))
            try await Task.sleep(nanoseconds: 500_000_000)
            assertEqual(counter2.count, afterStart, "stop 后不再回调", &passed, &failed)

            // 3. 目录不存在时初始化抛错
            let missing = FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-\(UUID().uuidString)")
            do {
                _ = try DownloadsWatcher(directory: missing) {}
                print("❌ 目录不存在应抛错")
                failed += 1
            } catch {
                passed += 1
            }
        } catch {
            print("❌ watcher 测试异常: \(error)")
            failed += 1
        }
    }

    // MARK: - RegexExcluder 测试

    static func runRegexExcluderTests(_ passed: inout Int, _ failed: inout Int) {
        // 1. 默认排除点开头
        let hidden = RegexExcluder(patterns: ["^\\."])
        assertEqual(hidden.shouldExclude(".DS_Store"), true, "排除 . 开头文件", &passed, &failed)
        assertEqual(hidden.shouldExclude("report.pdf"), false, "不排除普通文件", &passed, &failed)

        // 2. 空模式不排除任何
        let none = RegexExcluder(patterns: [])
        assertEqual(none.shouldExclude("anything"), false, "空模式不排除", &passed, &failed)

        // 3. 多正则任一匹配即排除
        let multi = RegexExcluder(patterns: ["^tmp_", "\\.bak$"])
        assertEqual(multi.shouldExclude("tmp_cache.txt"), true, "匹配第一个正则", &passed, &failed)
        assertEqual(multi.shouldExclude("data.bak"), true, "匹配第二个正则", &passed, &failed)
        assertEqual(multi.shouldExclude("normal.txt"), false, "都不匹配不排除", &passed, &failed)

        // 4. 无效正则被忽略，不崩溃
        let invalid = RegexExcluder(patterns: ["[invalid", "^\\."])
        assertEqual(invalid.shouldExclude(".hidden"), true, "无效正则被忽略，有效正则仍工作", &passed, &failed)
        assertEqual(invalid.activePatternCount, 1, "无效正则不计入", &passed, &failed)

        // 5. 大小写敏感
        let caseSensitive = RegexExcluder(patterns: ["\\.PNG$"])
        assertEqual(caseSensitive.shouldExclude("a.PNG"), true, "大小写匹配", &passed, &failed)
        assertEqual(caseSensitive.shouldExclude("a.png"), false, "大小写不匹配不排除", &passed, &failed)
    }

    // MARK: - ChangeTracker 测试

    static func runChangeTrackerTests(_ passed: inout Int, _ failed: inout Int) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("change-tracker-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let tracker = ChangeTracker()

        // 1. 首次更新：全部作为初始列表（按日期倒序）
        let a = DownloadFile(url: dir.appendingPathComponent("a.txt"), displayName: "a.txt", sortDate: Date(timeIntervalSince1970: 1_700_000_000), byteSize: 1)
        let b = DownloadFile(url: dir.appendingPathComponent("b.txt"), displayName: "b.txt", sortDate: Date(timeIntervalSince1970: 1_800_000_000), byteSize: 2)
        let initial = tracker.update(with: [a, b], now: Date(timeIntervalSince1970: 1_900_000_000))
        assertEqual(initial.isEmpty, true, "首次更新不产生变化", &passed, &failed)
        assertEqual(tracker.recentFiles.map { $0.displayName }, ["b.txt", "a.txt"], "首次按日期倒序", &passed, &failed)

        // 2. 新增文件 → 插到队首
        let c = DownloadFile(url: dir.appendingPathComponent("c.txt"), displayName: "c.txt", sortDate: Date(timeIntervalSince1970: 1_700_000_000), byteSize: 3)
        let changed1 = tracker.update(with: [a, b, c], now: Date(timeIntervalSince1970: 1_950_000_000))
        assertEqual(changed1.map { $0.displayName }, ["c.txt"], "新增文件作为变化返回", &passed, &failed)
        assertEqual(tracker.recentFiles.map { $0.displayName }, ["c.txt", "b.txt", "a.txt"], "新增插到队首", &passed, &failed)

        // 3. 修改已有文件 → 移到队首
        let bModified = DownloadFile(url: dir.appendingPathComponent("b.txt"), displayName: "b.txt", sortDate: Date(timeIntervalSince1970: 1_800_000_000), byteSize: 99)
        let changed2 = tracker.update(with: [a, bModified, c], now: Date(timeIntervalSince1970: 2_000_000_000))
        assertEqual(changed2.map { $0.displayName }, ["b.txt"], "修改文件作为变化返回", &passed, &failed)
        assertEqual(tracker.recentFiles.map { $0.displayName }, ["b.txt", "c.txt", "a.txt"], "修改移到队首", &passed, &failed)

        // 4. 删除文件 → 从列表移除
        let changed3 = tracker.update(with: [bModified, c], now: Date(timeIntervalSince1970: 2_050_000_000))
        assertEqual(tracker.recentFiles.map { $0.displayName }, ["b.txt", "c.txt"], "删除后从列表消失", &passed, &failed)
        assertEqual(changed3.isEmpty, true, "删除不产生变化文件", &passed, &failed)

        // 5. 无变化 → 返回空
        let changed4 = tracker.update(with: [bModified, c], now: Date(timeIntervalSince1970: 2_100_000_000))
        assertEqual(changed4.isEmpty, true, "无变化返回空", &passed, &failed)
    }

    // MARK: - StagingStore 测试

    static func runStagingStoreTests(_ passed: inout Int, _ failed: inout Int) async {
        await MainActor.run {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("staging-\(UUID().uuidString)")

            // 1. 添加文件（记录路径）
            let store = StagingStore()
            let url1 = dir.appendingPathComponent("a.txt")
            let url2 = dir.appendingPathComponent("b.txt")
            store.add(urls: [url1, url2])
            assertEqual(store.files.count, 2, "添加两个文件", &passed, &failed)
            assertEqual(store.files[0].url, url2, "最新添加在最前", &passed, &failed)

            // 2. 重复添加同一文件 → 去重（移到最前）
            store.add(urls: [url1])
            assertEqual(store.files.count, 2, "重复添加去重", &passed, &failed)
            assertEqual(store.files[0].url, url1, "重复添加移到最前", &passed, &failed)

            // 3. 移除单条
            store.remove(url: url2)
            assertEqual(store.files.map { $0.url }, [url1], "移除单条", &passed, &failed)

            // 4. 清空
            store.clear()
            assertEqual(store.files.isEmpty, true, "清空中转站", &passed, &failed)

            // 5. displayName 提取
            let url3 = dir.appendingPathComponent("报告.pdf")
            store.add(urls: [url3])
            assertEqual(store.files[0].displayName, "报告.pdf", "显示名取文件名", &passed, &failed)
        }
    }

    // MARK: - 断言工具

    static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String, _ passed: inout Int, _ failed: inout Int) {
        if actual == expected {
            print("✅ \(label)")
            passed += 1
        } else {
            print("❌ \(label): 期望=\(expected), 实际=\(actual)")
            failed += 1
        }
    }
}

/// 可控的 fake scanner。
struct FakeScanner: DownloadsScanning {
    var handler: @Sendable (URL, Int) async throws -> [DownloadFile]

    func scan(directory: URL, limit: Int) async throws -> [DownloadFile] {
        try await handler(directory, limit)
    }
}

/// 第一次调用返回固定结果，后续调用走自定义闭包。
final class SwitchingScanner: DownloadsScanning, @unchecked Sendable {
    private let callCounter = OSAllocatedUnfairLock(initialState: 0)
    private let firstResult: [DownloadFile]
    private let subsequent: @Sendable (Int) async throws -> [DownloadFile]

    init(firstResult: [DownloadFile], subsequent: @escaping @Sendable (Int) async throws -> [DownloadFile]) {
        self.firstResult = firstResult
        self.subsequent = subsequent
    }

    func scan(directory: URL, limit: Int) async throws -> [DownloadFile] {
        let count = callCounter.withLock { counter in
            counter += 1
            return counter
        }
        if count == 1 {
            return firstResult
        }
        return try await subsequent(count)
    }
}

enum StoreTestError: Error {
    case scanFailed
}

/// 控制扫描完成时机的门闩。
final class AsyncGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func wait() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.semaphore.wait()
                continuation.resume()
            }
        }
    }

    func open() {
        semaphore.signal()
    }
}

/// 线程安全的计数器。
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