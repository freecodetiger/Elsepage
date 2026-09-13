import SwiftUI
import UIKit

/// Main-actor cache for the expensive part of a read-only text view's intrinsic
/// size calculation. The key carries the complete attributed-text fingerprint,
/// so markdown runs, fonts and links cannot share a height accidentally.
@MainActor
final class TextMeasureCache {
    static let shared = TextMeasureCache(capacity: 200)

    struct Key: Hashable {
        let fingerprint: String
        let widthBucket: Int
    }

    private let capacity: Int
    private var values: [Key: CGFloat] = [:]
    private var order: [Key] = []
    private(set) var hits = 0
    private(set) var misses = 0

    init(capacity: Int) { self.capacity = max(1, capacity) }

    func value(for key: Key, measure: () -> CGFloat) -> CGFloat {
        if let cached = values[key] {
            hits += 1
            touch(key)
            Perf.shared.event("textMeasure.cache.hit bucket=\(key.widthBucket)")
            return cached
        }
        misses += 1
        let measured = measure()
        values[key] = measured
        touch(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            values.removeValue(forKey: evicted)
        }
        Perf.shared.event("textMeasure.cache.miss bucket=\(key.widthBucket)")
        return measured
    }

    func reset() {
        values.removeAll()
        order.removeAll()
        hits = 0
        misses = 0
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

/// Caches markdown structure separately from the current font and color pass.
/// Dynamic Type changes therefore reuse parsing work while rebuilding only the
/// cheap attributed-string styling layer.
@MainActor
final class RichTextBuilder {
    static let shared = RichTextBuilder(capacity: 200)

    private let capacity: Int
    private var parsed: [String: AttributedString] = [:]
    private var parsedOrder: [String] = []
    private var styled: [String: NSAttributedString] = [:]
    private var styledOrder: [String] = []

    init(capacity: Int) { self.capacity = max(1, capacity) }

    func markdown(_ source: String, textStyle: UIFont.TextStyle, isSecondary: Bool, dynamicTypeKey: String) -> NSAttributedString {
        let styleKey = "markdown|\(source)|\(textStyle.rawValue)|\(isSecondary)|\(dynamicTypeKey)"
        if let cached = styled[styleKey] {
            touch(styleKey, order: &styledOrder)
            Perf.shared.event("richText.cache.hit markdown")
            return cached
        }
        let structure: AttributedString
        if let cached = parsed[source] {
            structure = cached
            touch(source, order: &parsedOrder)
        } else {
            structure = (try? AttributedString(
                markdown: source,
                options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
            )) ?? AttributedString(source)
            parsed[source] = structure
            touch(source, order: &parsedOrder)
            trim(&parsed, order: &parsedOrder)
            Perf.shared.event("richText.parse.miss")
        }
        let color: UIColor = isSecondary ? .secondaryLabel : .label
        let result = makeSelectableMarkdown(structure, textStyle: textStyle, color: color)
        styled[styleKey] = result
        touch(styleKey, order: &styledOrder)
        trim(&styled, order: &styledOrder)
        Perf.shared.event("richText.cache.miss markdown")
        return result
    }

    func plain(_ source: String, textStyle: UIFont.TextStyle, isSecondary: Bool, dynamicTypeKey: String) -> NSAttributedString {
        let key = "plain|\(source)|\(textStyle.rawValue)|\(isSecondary)|\(dynamicTypeKey)"
        if let cached = styled[key] {
            touch(key, order: &styledOrder)
            Perf.shared.event("richText.cache.hit plain")
            return cached
        }
        let color: UIColor = isSecondary ? .secondaryLabel : .label
        let result = NSAttributedString(string: source, attributes: [
            .font: UIFont.preferredFont(forTextStyle: textStyle),
            .foregroundColor: color,
        ])
        styled[key] = result
        touch(key, order: &styledOrder)
        trim(&styled, order: &styledOrder)
        Perf.shared.event("richText.cache.miss plain")
        return result
    }

    func reset() {
        parsed.removeAll()
        parsedOrder.removeAll()
        styled.removeAll()
        styledOrder.removeAll()
    }

    private func touch(_ key: String, order: inout [String]) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func trim<Value>(_ values: inout [String: Value], order: inout [String]) {
        while order.count > capacity {
            let evicted = order.removeFirst()
            values.removeValue(forKey: evicted)
        }
    }
}

/// Shared SwiftUI facade for selectable conversation/archive text. Existing
/// wrappers keep their public call sites stable while routing all construction
/// through this cache-backed implementation.
struct MessageText: View {
    enum Content {
        case plain(String)
        case markdown(String)
    }

    let content: Content
    var textStyle: UIFont.TextStyle = .body
    var isSecondary = false
    var linkHandler: ((URL) -> Bool)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let dynamicTypeKey = String(describing: dynamicTypeSize)
        let attributed = Perf.shared.timed(.markdownRender) {
            switch content {
            case .plain(let source):
                return RichTextBuilder.shared.plain(source, textStyle: textStyle, isSecondary: isSecondary, dynamicTypeKey: dynamicTypeKey)
            case .markdown(let source):
                return RichTextBuilder.shared.markdown(source, textStyle: textStyle, isSecondary: isSecondary, dynamicTypeKey: dynamicTypeKey)
            }
        }
        return SelectableTextView(attributedText: attributed, linkHandler: linkHandler)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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

    static func dismantleUIView(_ uiView: FitTextView, coordinator: Coordinator) {
        Perf.shared.noteTextViewAlive(-1)
    }

    func updateUIView(_ textView: FitTextView, context: Context) {
        Perf.shared.timed(.textUpdate) {
            context.coordinator.linkHandler = linkHandler
            if textView.attributedText != attributedText {
                Perf.shared.event("text.replace view=\(textView.perfID)")
                textView.cancelSelectionProbe()
                textView.attributedText = attributedText
                // 宽度由 SwiftUI 提案决定,高度由内容自报。
                textView.invalidateIntrinsicContentSize()
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextViewDelegate {
        var linkHandler: ((URL) -> Bool)?

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let view = textView as? FitTextView else { return }
            view.noteSelectionCallback()
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
        MessageText(content: .plain(content), textStyle: textStyle, isSecondary: isSecondary)
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
    private var lastMeasureKey: TextMeasureCache.Key?
    private var lastMeasuredHeight: CGFloat?
    let perfID = UUID().uuidString.prefix(8)
    private var selectionTouchAt: TimeInterval?

    override func becomeFirstResponder() -> Bool {
        guard Perf.shared.isEnabled else { return super.becomeFirstResponder() }
        Perf.shared.event("selection.responder.begin view=\(perfID)")
        let accepted = Perf.shared.timed(.selectionResponderAcquire) { super.becomeFirstResponder() }
        Perf.shared.event("selection.responder.end view=\(perfID) accepted=\(accepted)")
        return accepted
    }

    func cancelSelectionProbe() {
        selectionTouchAt = nil
    }

    func noteSelectionCallback() {
        guard Perf.shared.isEnabled, selectedRange.length > 0 else { return }
        guard let began = selectionTouchAt else { return }
        selectionTouchAt = nil // Clear before SelectionKeeper can trigger another callback.
        let elapsed = ProcessInfo.processInfo.systemUptime - began
        guard elapsed >= 0, elapsed < 3 else {
            Perf.shared.event("selection.expired view=\(perfID)")
            return
        }
        Perf.shared.record(.selectionStart, ms: elapsed * 1000)
        Perf.shared.event("selection.nonempty view=\(perfID)")
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if Perf.shared.isEnabled {
            Perf.shared.noteScrollChain(of: self)
            Perf.shared.probeMainQueue()
            selectionTouchAt = selectedRange.length == 0 ? touches.map(\.timestamp).min() : nil
            Perf.shared.event("selection.touchDelivered view=\(perfID) existing=\(selectedRange.length > 0)")
            if let began = selectionTouchAt {
                let delivery = (ProcessInfo.processInfo.systemUptime - began) * 1000
                Perf.shared.event("selection.touchDelivery \(String(format: "%.1f", delivery))ms view=\(perfID)")
            }
        }
        // 任何触摸(含长按前的手指按下)先清掉上一处残留选区,保证本处气泡能弹。
        SelectionKeeper.shared.touchesBegan(on: self)
        super.touchesBegan(touches, with: event)
    }

    override var intrinsicContentSize: CGSize {
        let width = usableWidth()
        let widthBucket = Int((width / 8).rounded())
        let key = TextMeasureCache.Key(
            fingerprint: Self.fingerprint(attributedText),
            widthBucket: widthBucket
        )
        let height: CGFloat
        if key == lastMeasureKey, let lastMeasuredHeight {
            height = lastMeasuredHeight
        } else {
            let measuredWidth = CGFloat(widthBucket * 8)
            height = TextMeasureCache.shared.value(for: key) {
                let rect = Perf.shared.timed(.textMeasure) {
                    attributedText.boundingRect(
                        with: CGSize(width: measuredWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                }
                return ceil(rect.height) + 1
            }
            lastMeasureKey = key
            lastMeasuredHeight = height
        }
        // width 设为 noIntrinsicMetric:宽度完全听从 SwiftUI 提案,不在横轴自增。
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        Perf.shared.timed(.textLayout) {
            performTextLayout()
        }
    }

    private func performTextLayout() {
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

    private static func fingerprint(_ value: NSAttributedString) -> String {
        var result = value.string
        guard value.length > 0 else { return result }
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length), options: []) { attributes, range, _ in
            result += "|\(range.location):\(range.length)"
            if let font = attributes[.font] as? UIFont {
                result += ":font=\(font.fontDescriptor.postscriptName):\(font.pointSize):\(font.fontDescriptor.symbolicTraits.rawValue)"
            }
            if let color = attributes[.foregroundColor] as? UIColor {
                result += ":color=\(color.description)"
            }
            if let link = attributes[.link] {
                result += ":link=\(String(describing: link))"
            }
        }
        return result
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
