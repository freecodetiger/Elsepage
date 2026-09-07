import SwiftUI
import UIKit

/// iOS 26 及更早的 SwiftUI `Text(.textSelection(.enabled))` 在长按时只会弹出作用于
/// 整段文本的系统菜单——没有选区高亮、没有可拖手柄(iOS 27 起 Text 才原生支持选区)。
/// 要拿到原生「蓝色选区 + 双手柄 + 放大镜 + 跨行多选」,必须改用 UIKit 的只读
/// `UITextView`(isEditable=false / isSelectable=true),这里把它包成 SwiftUI 视图。
///
/// 每个实例是一块独立的可选中文本:多选手柄的跨行范围限于本块内部,不能跨相邻块连续选。
struct SelectableTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    var linkHandler: ((URL) -> Bool)?

    func makeUIView(context: Context) -> FitTextView {
        let textView = FitTextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        // 文本容器跟随视图宽度换行,否则长段落会按固有宽度单行溢出屏幕。
        textView.textContainer.widthTracksTextView = true
        textView.dataDetectorTypes = []
        textView.isAccessibilityElement = true
        textView.delegate = context.coordinator
        Perf.shared.noteTextViewAlive(1)
        return textView
    }

    static func dismantleUIViewController(_ uiViewController: FitTextView, coordinator: Coordinator) {
        Perf.shared.noteTextViewAlive(-1)
    }

    func updateUIView(_ textView: FitTextView, context: Context) {
        context.coordinator.linkHandler = linkHandler
        if textView.attributedText != attributedText {
            textView.attributedText = attributedText
            // 宽度由 SwiftUI 提案决定,高度由内容自报。
            textView.invalidateIntrinsicContentSize()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextViewDelegate {
        var linkHandler: ((URL) -> Bool)?

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let view = textView as? FitTextView else { return }
            SelectionKeeper.shared.selectionChanged(on: view)
        }
        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            // 被自定义 handler 消费的链接(如 citation 跳转)吞掉默认动作;
            // 其余(如 http)走系统默认打开。
            if case .link(let url) = textItem.content {
                return (linkHandler?(url) ?? false) ? UIAction(title: "") { _ in } : defaultAction
            }
            return defaultAction
        }
    }
}

/// 纯文本正文的可选中包装:系统字体 + 文本样式 + 明/次色,随 Dynamic Type 自适应。
struct SelectableTextBody: View {
    let content: String
    var textStyle: UIFont.TextStyle = .body
    var isSecondary = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        SelectableTextView(attributedText: attributedContent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedContent: NSAttributedString {
        // 读取 typeSize 使 Dynamic Type 变化时本视图重建、按新字号重建富文本。
        _ = typeSize
        let color: UIColor = isSecondary ? .secondaryLabel : .label
        return NSAttributedString(string: content, attributes: [
            .font: UIFont.preferredFont(forTextStyle: textStyle),
            .foregroundColor: color,
        ])
    }
}

/// 把 SwiftUI 解析过的 Markdown `AttributedString` 落地成给 UITextView 的
/// `NSAttributedString`:映射加粗/斜体/代码/链接,其余退化为基础样式。
func makeSelectableMarkdown(
    _ markdown: AttributedString,
    textStyle: UIFont.TextStyle,
    color: UIColor
) -> NSAttributedString {
    let base = UIFont.preferredFont(forTextStyle: textStyle)
    let result = NSMutableAttributedString()
    for run in markdown.runs {
        let text = String(markdown[run.range].characters)
        guard !text.isEmpty else { continue }
        let font = selectableFont(for: run.inlinePresentationIntent, base: base)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if let link = run.link {
            attributes[.link] = link
        }
        result.append(NSAttributedString(string: text, attributes: attributes))
    }
    if result.length == 0 {
        result.append(NSAttributedString(
            string: String(markdown.characters),
            attributes: [.font: base, .foregroundColor: color]
        ))
    }
    return result
}

/// 只读可选中文本的“第一响应者协调器”:任意时刻至多一个文本视图持有选区。
/// 上一次选区若残留(点外部只关菜单不清选区),会堵住下一个长按的编辑气泡;
/// 这里在“新触摸开始”和“新选区形成”时先让上一个视图 resign + 清空选区。
@MainActor
final class SelectionKeeper {
    static let shared = SelectionKeeper()
    private weak var activeView: FitTextView?
    private init() {}

    func touchesBegan(on view: FitTextView) {
        clearPrevious(before: view)
        activeView = view
    }

    func selectionChanged(on view: FitTextView) {
        guard view.selectedRange.length > 0 else { return }
        clearPrevious(before: view)
        activeView = view
        if !view.isFirstResponder {
            view.becomeFirstResponder()
        }
    }

    private func clearPrevious(before newView: FitTextView) {
        guard let previous = activeView, previous !== newView else { return }
        if activeView === previous { activeView = nil }
        previous.resignFirstResponder()
        if previous.selectedRange.length > 0 {
            previous.selectedRange = NSRange(location: 0, length: 0)
        }
    }
}

/// 按当前宽度自适应高度的只读 UITextView:宽度交给 SwiftUI 提案(换行),
/// 高度由内容在真实宽度下量得并上报给 `intrinsicContentSize`。
final class FitTextView: UITextView {
    private var lastMeasuredWidth: CGFloat = -1

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // 任何触摸(含长按前的手指按下)先清掉上一处残留选区,保证本处气泡能弹。
        SelectionKeeper.shared.touchesBegan(on: self)
        super.touchesBegan(touches, with: event)
    }

    override var intrinsicContentSize: CGSize {
        let width = usableWidth()
        let rect = Perf.shared.timed(.textMeasure) {
            attributedText.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
        // width 设为 noIntrinsicMetric:宽度完全听从 SwiftUI 提案,不在横轴自增。
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(rect.height) + 1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 宽度变化(旋转/Dynamic Type/首帧布局)后按新宽度重新量高。
        if bounds.width != lastMeasuredWidth {
            lastMeasuredWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }

    private func usableWidth() -> CGFloat {
        if bounds.width > 0 { return bounds.width }
        if let windowWidth = window?.bounds.width { return windowWidth }
        return 320
    }
}

private func selectableFont(for intent: InlinePresentationIntent?, base: UIFont) -> UIFont {
    guard let intent else { return base }
    var font = base
    if intent.contains(.code) {
        font = .monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
    }
    var traits: UIFontDescriptor.SymbolicTraits = []
    if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
    if intent.contains(.emphasized) { traits.insert(.traitItalic) }
    guard !traits.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else {
        return font
    }
    return UIFont(descriptor: descriptor, size: 0)
}

extension View {
    /// 挂一条消息的「复制整条(带出处)」长按菜单。出处 = 说话者 + 时间,拼在正文之后。
    /// 只应挂在不与可选中正文重叠的头部/元信息区域,避免长按手势抢掉文本选择。
    func copyMessageContextMenu(content: String, authorLabel: String, date: Date?) -> some View {
        contextMenu {
            Button {
                var text = content
                if !text.hasSuffix("\n") { text += "\n" }
                let provenance: String
                if let date {
                    provenance = "—— \(authorLabel) · \(date.formatted(date: .abbreviated, time: .shortened))"
                } else {
                    provenance = "—— \(authorLabel)"
                }
                UIPasteboard.general.string = text + provenance
            } label: {
                Label("复制整条", systemImage: "doc.on.doc")
            }
        }
    }
}
