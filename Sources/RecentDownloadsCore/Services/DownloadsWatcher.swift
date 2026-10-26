import Foundation

/// 监听目录变化并触发刷新。
///
/// 使用 `DispatchSourceFileSystemObject` 监听文件系统事件，
/// 事件经防抖后回调 `onChange`。监听事件本身不读取目录，
/// 最终状态始终由重新扫描得到。
public final class DownloadsWatcher: @unchecked Sendable {
    private let directory: URL
    private let onChange: @Sendable () -> Void
    private let debouncer: Debouncer
    private let queue = DispatchQueue(label: "recent-downloads.watcher")
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    /// - Parameters:
    ///   - directory: 要监听的目录。
    ///   - debounceDelay: 事件防抖窗口，默认 300ms。
    ///   - onChange: 防抖后的事件回调。
    /// - Throws: 目录不存在时抛出错误。
    public init(directory: URL, debounceDelay: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CocoaError(.fileNoSuchFile)
        }
        self.directory = directory
        self.onChange = onChange
        self.debouncer = Debouncer(delay: debounceDelay, queue: queue)
    }

    /// 开始监听。重复调用幂等。
    public func start() {
        guard source == nil else { return }

        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )
        let onChange = onChange
        source.setEventHandler { [weak self] in
            self?.debouncer.schedule { onChange() }
        }
        source.setCancelHandler { [weak self] in
            if let self, self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        self.source = source
        source.resume()
    }

    /// 停止监听。重复调用幂等。
    public func stop() {
        source?.cancel()
        source = nil
        debouncer.cancel()
    }

    deinit {
        source?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}
