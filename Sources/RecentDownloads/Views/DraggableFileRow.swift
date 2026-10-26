import AppKit
import SwiftUI
import RecentDownloadsCore

/// 使用 AppKit `NSView` 实现的跨应用文件拖放行。
///
/// 使用 `NSPanGestureRecognizer` 处理拖拽手势，避免 SwiftUI 视图层级
/// 拦截首次鼠标事件导致需先点击再拖拽的问题。
struct DraggableFileRow: NSViewRepresentable {
    let file: DownloadFile
    let onDragBegin: () -> Void
    let onDragEnd: () -> Void

    init(file: DownloadFile, onDragBegin: @escaping () -> Void = {}, onDragEnd: @escaping () -> Void = {}) {
        self.file = file
        self.onDragBegin = onDragBegin
        self.onDragEnd = onDragEnd
    }

    func makeNSView(context: Context) -> DraggableFileRowView {
        let view = DraggableFileRowView(file: file, onDragBegin: onDragBegin, onDragEnd: onDragEnd)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: DraggableFileRowView, context: Context) {
        nsView.updateFile(file, onDragBegin: onDragBegin, onDragEnd: onDragEnd)
    }
}

/// 自定义 NSView，使用手势识别器处理跨应用拖放。
final class DraggableFileRowView: NSView {
    private var file: DownloadFile
    private var onDragBegin: () -> Void
    private var onDragEnd: () -> Void
    private var isDragging = false
    private var dragThresholdReached = false

    private static let dragThreshold: CGFloat = 5.0

    init(file: DownloadFile, onDragBegin: @escaping () -> Void, onDragEnd: @escaping () -> Void) {
        self.file = file
        self.onDragBegin = onDragBegin
        self.onDragEnd = onDragEnd
        super.init(frame: .zero)

        // 使用 pan 手势识别器，无需先点击获得焦点即可拖拽。
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.buttonMask = 1 << 0 // 左键
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateFile(_ file: DownloadFile, onDragBegin: @escaping () -> Void, onDragEnd: @escaping () -> Void) {
        self.file = file
        self.onDragBegin = onDragBegin
        self.onDragEnd = onDragEnd
        needsDisplay = true
    }

    // MARK: - Drawing

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let padding: CGFloat = 12
        let iconSize = NSSize(width: 32, height: 32)

        // 图标
        let icon = NSWorkspace.shared.icon(forFile: file.url.path)
        icon.size = iconSize
        icon.draw(
            in: NSRect(x: padding, y: (bounds.height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
        )

        // 文本区域
        let textX = padding + iconSize.width + 8
        let textWidth = max(bounds.width - textX - padding, 0)

        // 文件名（单行中间截断）
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]
        let name = Self.truncate(file.displayName, toWidth: textWidth, attributes: nameAttributes)
        let nameSize = (name as NSString).size(withAttributes: nameAttributes)
        (name as NSString).draw(
            at: NSPoint(x: textX, y: 8),
            withAttributes: nameAttributes
        )

        // 相对时间 + 大小
        let subtitle = "\(FilePresentation.relativeDateString(file.sortDate)) · \(FilePresentation.byteCountString(file.byteSize))"
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        (subtitle as NSString).draw(
            at: NSPoint(x: textX, y: 8 + nameSize.height + 2),
            withAttributes: subtitleAttributes
        )
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 48)
    }

    private static func truncate(_ string: String, toWidth width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> String {
        guard width > 0 else { return "" }
        var result = string
        while (result as NSString).size(withAttributes: attributes).width > width && result.count > 1 {
            result = String(result.dropLast())
        }
        if result != string {
            result += "…"
        }
        return result
    }

    // MARK: - Pan Gesture

    /// 允许首次点击直接到达视图（无需先点击激活窗口）。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isDragging = false
            dragThresholdReached = false
            // 直接开始拖拽，无需先点击激活

        case .changed:
            guard !dragThresholdReached else { return }
            let translation = gesture.translation(in: self)
            let distance = sqrt(translation.x * translation.x + translation.y * translation.y)
            if distance >= Self.dragThreshold {
                dragThresholdReached = true
                beginDrag()
            }

        case .ended, .cancelled:
            if !isDragging {
                // 没超过阈值 → 视为普通点击
                if gesture.state == .ended {
                    // 可选：点击行为
                }
            }
            isDragging = false
            dragThresholdReached = false

        default:
            break
        }
    }

    // MARK: - Drag Session

    private func beginDrag() {
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: file.url.path) else {
            isDragging = false
            onDragEnd()
            return
        }

        isDragging = true
        onDragBegin()

        let draggingItem = NSDraggingItem(pasteboardWriter: file.url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: file.url.path)
        let iconSize = NSSize(width: 32, height: 32)
        icon.size = iconSize

        // 组合预览：图标 + 文件名
        let preview = createDragPreview(icon: icon, name: file.displayName)
        draggingItem.setDraggingFrame(preview.frame, contents: preview.image)
        draggingItem.draggingFrame = preview.frame

        // 使用当前鼠标事件
        let event = NSApp.currentEvent ?? NSEvent()
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func createDragPreview(icon: NSImage, name: String) -> (frame: NSRect, image: NSImage) {
        let padding: CGFloat = 6
        let iconSize = NSSize(width: 32, height: 32)
        let textSize = (name as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        let width = iconSize.width + padding + min(textSize.width, 200) + padding * 2
        let height = max(iconSize.height, textSize.height) + padding * 2
        let frame = NSRect(x: 0, y: 0, width: width, height: height)

        let image = NSImage(size: frame.size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // 半透明背景
        NSColor(white: 0, alpha: 0.7).setFill()
        let bgPath = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        bgPath.fill()

        // 图标
        icon.draw(
            in: NSRect(x: padding, y: (frame.height - iconSize.height) / 2, width: iconSize.width, height: iconSize.height)
        )

        // 文件名
        let textX = padding + iconSize.width + padding
        let textY = (frame.height - textSize.height) / 2
        let textColor = NSColor.white
        let truncatedName: String
        if textSize.width > 200 {
            truncatedName = (name as NSString).substring(to: min(name.count, 30)) + "…"
        } else {
            truncatedName = name
        }
        (truncatedName as NSString).draw(
            at: NSPoint(x: textX, y: textY),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: textColor,
            ]
        )

        return (frame, image)
    }
}

// MARK: - NSDraggingSource

extension DraggableFileRowView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy]
    }

    func draggingSessionEnded(_ session: NSDraggingSession, operation: NSDragOperation) {
        isDragging = false
        dragThresholdReached = false
        onDragEnd()
    }
}