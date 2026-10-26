import Testing
import Foundation
@testable import RecentDownloadsCore

@Suite("DownloadsScanner 扫描规则")
final class DownloadsScannerTests {
    let tempDir: URL
    let scanner: DownloadsScanner

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanner-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        scanner = DownloadsScanner()
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @discardableResult
    private func makeFile(named name: String, modified: Date? = nil) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data("test content".utf8).write(to: url)
        if let modified {
            try FileManager.default.setAttributes(
                [.modificationDate: modified],
                ofItemAtPath: url.path
            )
        }
        return url
    }

    // MARK: - 过滤规则

    @Test("返回普通文件")
    func returnsRegularFiles() async throws {
        try makeFile(named: "report.pdf")
        try makeFile(named: "photo.png")

        let files = try await scanner.scan(directory: tempDir, limit: 15)

        #expect(Set(files.map(\.displayName)) == ["report.pdf", "photo.png"])
    }

    @Test("过滤掉目录")
    func filtersOutDirectories() async throws {
        try makeFile(named: "doc.txt")
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("folder"),
            withIntermediateDirectories: true
        )

        let files = try await scanner.scan(directory: tempDir, limit: 15)

        #expect(files.map(\.displayName) == ["doc.txt"])
    }

    @Test("过滤掉隐藏文件")
    func filtersOutHiddenFiles() async throws {
        try makeFile(named: "visible.txt")
        try makeFile(named: ".hidden_file")

        let files = try await scanner.scan(directory: tempDir, limit: 15)

        #expect(files.map(\.displayName) == ["visible.txt"])
    }

    @Test("过滤掉临时扩展名（大小写不敏感）")
    func filtersOutTemporaryExtensions() async throws {
        try makeFile(named: "video.mp4")
        for name in ["a.crdownload", "b.download", "c.part", "d.partial", "e.tmp", "f.CRDOWNLOAD", "g.Tmp"] {
            try makeFile(named: name)
        }

        let files = try await scanner.scan(directory: tempDir, limit: 15)

        #expect(files.map(\.displayName) == ["video.mp4"])
    }

    // MARK: - 排序

    @Test("按修改日期倒序（最新在前）")
    func sortsNewestFirstByModificationDate() async throws {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_800_000_000)
        try makeFile(named: "older.txt", modified: older)
        try makeFile(named: "newer.txt", modified: newer)

        let files = try await scanner.scan(directory: tempDir, limit: 15)

        #expect(files.map(\.displayName) == ["newer.txt", "older.txt"])
    }

    @Test("日期相同时按文件名稳定排序")
    func stableSortByNameWhenDatesEqual() async throws {
        let sameDate = Date(timeIntervalSince1970: 1_700_000_000)
        try makeFile(named: "b.txt", modified: sameDate)
        try makeFile(named: "a.txt", modified: sameDate)
        try makeFile(named: "c.txt", modified: sameDate)

        let files = try await scanner.scan(directory: tempDir, limit: 15)

        #expect(files.map(\.displayName) == ["a.txt", "b.txt", "c.txt"])
    }

    @Test("优先使用 addedToDirectoryDate 排序")
    func prefersAddedToDirectoryDate() async throws {
        // a.txt 创建早但修改晚；b.txt 创建晚但修改早。
        // 若按 added date → b 在前；若按 modification date → a 在前。
        try makeFile(named: "a.txt")
        try await Task.sleep(nanoseconds: 300_000_000)
        try makeFile(named: "b.txt")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
            ofItemAtPath: tempDir.appendingPathComponent("a.txt").path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: tempDir.appendingPathComponent("b.txt").path
        )

        let files = try await scanner.scan(directory: tempDir, limit: 15)

        #expect(files.map(\.displayName) == ["b.txt", "a.txt"])
    }

    // MARK: - 数量上限与容错

    @Test("限制返回数量为指定的 limit")
    func limitTruncatesToRequestedCount() async throws {
        for i in 0..<20 {
            try makeFile(
                named: String(format: "file-%02d.txt", i),
                modified: Date(timeIntervalSince1970: 1_700_000_000 + Double(i))
            )
        }

        let files = try await scanner.scan(directory: tempDir, limit: 15)

        #expect(files.count == 15)
        #expect(files.first?.displayName == "file-19.txt")
        #expect(files.last?.displayName == "file-05.txt")
    }

    @Test("单个无权限文件不导致整体扫描失败")
    func unreadableFileDoesNotFailWholeScan() async throws {
        try makeFile(named: "good.txt")
        let bad = tempDir.appendingPathComponent("bad.txt")
        try Data("x".utf8).write(to: bad)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: bad.path
        )

        let files = try await scanner.scan(directory: tempDir, limit: 15)

        #expect(files.map(\.displayName).contains("good.txt"))
        #expect(!files.isEmpty)
    }

    @Test("扫描不存在的目录抛出错误")
    func missingDirectoryThrows() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")

        await #expect(throws: (any Error).self) {
            _ = try await scanner.scan(directory: missing, limit: 15)
        }
    }

    @Test("文件元数据正确填充")
    func fileMetadataIsPopulated() async throws {
        let content = Data(repeating: 0x41, count: 1234)
        let url = tempDir.appendingPathComponent("data.bin")
        try content.write(to: url)

        let files = try await scanner.scan(directory: tempDir, limit: 15)

        #expect(files.count == 1)
        #expect(files[0].url.standardizedFileURL == url.standardizedFileURL)
        #expect(files[0].displayName == "data.bin")
        #expect(files[0].byteSize == 1234)
        #expect(files[0].sortDate != nil)
    }
}