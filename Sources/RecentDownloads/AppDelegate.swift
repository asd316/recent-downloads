import AppKit
import SwiftUI
import RecentDownloadsCore

/// 菜单栏状态项与弹层生命周期的持有者。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var store: DownloadsStore!
    private var watchStore: WatchStore!
    private var stagingStore: StagingStore!
    private var watcher: DownloadsWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 仅驻留菜单栏，不显示 Dock 图标。
        NSApp.setActivationPolicy(.accessory)

        let downloadsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")

        let store = DownloadsStore(
            scanner: DownloadsScanner(),
            directory: downloadsDirectory
        )
        self.store = store
        self.watchStore = WatchStore()
        self.stagingStore = StagingStore()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "最近下载")
            button.target = self
            button.action = #selector(togglePopover)
        }
        self.statusItem = statusItem

        let popover = NSPopover()
        // semitransient：可成为 key window，首次点击不被系统吞掉（transient 需点击两次才能交互）。
        popover.behavior = .semitransient
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(
                downloadsStore: store,
                watchStore: self.watchStore,
                stagingStore: self.stagingStore,
                onOpenDownloads: { [weak self] in
                    self?.openDownloadsDirectory()
                },
                onQuit: {
                    NSApp.terminate(nil)
                },
                onSelectWatchDirectory: { [weak self] in
                    self?.selectWatchDirectory()
                },
                onDragBegin: { [weak popover] in
                    // 拖动期间保持弹层显示，避免提前关闭。
                    popover?.behavior = .applicationDefined
                },
                onDragEnd: { [weak popover] in
                    popover?.behavior = .semitransient
                    popover?.performClose(nil)
                }
            )
        )
        self.popover = popover

        setupWatcher(directory: downloadsDirectory)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            Task { await store.refresh() }
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func openDownloadsDirectory() {
        let downloadsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        popover?.performClose(nil)
        NSWorkspace.shared.activateFileViewerSelecting([downloadsDirectory])
    }

    /// 选择监控文件夹。
    private func selectWatchDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择要监控的文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        watchStore.setDirectory(url)
    }

    /// 监听下载目录变化；建立失败只记日志，不阻断使用（每次打开弹层仍会刷新）。
    private func setupWatcher(directory: URL) {
        do {
            let watcher = try DownloadsWatcher(directory: directory) { [weak self] in
                Task { @MainActor in
                    await self?.store.refresh()
                }
            }
            watcher.start()
            self.watcher = watcher
        } catch {
            NSLog("DownloadsWatcher 创建失败: \(error)")
        }
    }
}