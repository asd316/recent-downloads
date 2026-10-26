import SwiftUI

/// 应用入口。AppKit 生命周期由 `AppDelegate` 接管（菜单栏状态项与弹层）。
@main
struct RecentDownloadsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
