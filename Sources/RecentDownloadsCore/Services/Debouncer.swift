import Foundation

/// 通用防抖器：窗口内多次 `schedule` 只触发一次回调。
public final class Debouncer: @unchecked Sendable {
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?

    public init(delay: TimeInterval, queue: DispatchQueue = .main) {
        self.delay = delay
        self.queue = queue
    }

    /// 在窗口内推迟回调；窗口内的重复调用会重置计时。
    public func schedule(_ action: @escaping @Sendable () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// 取消尚未触发的回调。
    public func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
