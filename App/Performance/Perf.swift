import Foundation
import os
import UIKit

/// Phase-0 interaction-performance instrumentation（spec 工作包 F / ADR-0002）。
///
/// 双用途：给 os_signpost（Instruments 同源流）打点，同时把采样聚合进进程内桶，
/// 供 Settings 的诊断屏直接读取（真机自查 / 回归基线）。
/// 所有热路径入口先查 `isEnabled`：Release 下是单次分支的 no-op，行为零改动。
@MainActor
final class Perf {
    static let shared = Perf()

    enum Key: String, CaseIterable {
        case readerOpen          // 点书 → navigator 首帧（首个 locationDidChange）
        case readerParse         // EPUB open() 解析段
        case readerToFirstPage   // navigator 构造 → 首帧
        case keyboardAppear      // 编辑开始(beginEditing) → keyboardDidShow
        case keyboardToWillShow
        case keyboardWillToDidShow
        case keyboardAnimation
        case inputTouchToEditing
        case responderAcquire
        case selectionResponderAcquire
        case mainQueueDelay
        case selectionStart
        case textLayout
        case textUpdate
        case streamDelta         // 流式可见批次刷新：合并+剥 citation
        case markdownRender      // AgentMarkdownText 单次 body 渲染（整串解析+重建）
        case textMeasure         // FitTextView 单次全量测量（boundingRect）
    }

    struct Sample {
        var count = 0
        var totalMS = 0.0
        var maxMS = 0.0
        var lastMS = 0.0

        mutating func add(_ ms: Double) {
            count += 1
            totalMS += ms
            lastMS = ms
            if ms > maxMS { maxMS = ms }
        }
    }

    private(set) var isEnabled = false
    private(set) var samples: [Key: Sample] = [:]
    /// 当前存活 + 峰值。由 SelectableTextView make/dismantle 在主线程更新。
    private(set) var aliveTextViews = 0
    private(set) var peakAliveTextViews = 0

    private let signposter = OSSignposter(subsystem: "com.readloop.app", category: "perf")
    private var lastEditBeganAt: CFTimeInterval?
    private var keyboardWillShowAt: CFTimeInterval?
    private var events: [String] = []
    private var probeGeneration = 0
    private let epoch = ProcessInfo.processInfo.systemUptime

    /// Bounded, content-free timeline. No input, book text, URLs or credentials.
    func event(_ name: String) {
        guard isEnabled else { return }
        let elapsed = (ProcessInfo.processInfo.systemUptime - epoch) * 1000
        events.append(String(format: "%.1fms %@", elapsed, name))
        if events.count > 200 { events.removeFirst(events.count - 200) }
    }

    func reset() {
        probeGeneration += 1
        samples.removeAll()
        events.removeAll()
        lastEditBeganAt = nil
        keyboardWillShowAt = nil
        peakAliveTextViews = aliveTextViews
        event("capture.reset")
    }

    /// Short-lived probe, restarted by each interaction; no background polling.
    func probeMainQueue() {
        guard isEnabled else { return }
        probeGeneration += 1
        scheduleQueueProbe(generation: probeGeneration, remaining: 30)
    }

    private func scheduleQueueProbe(generation: Int, remaining: Int) {
        guard remaining > 0, generation == probeGeneration else { return }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.probeGeneration == generation,
                  UIApplication.shared.applicationState == .active else { return }
            self.record(.mainQueueDelay, ms: max(0, ProcessInfo.processInfo.systemUptime - deadline) * 1000)
            self.scheduleQueueProbe(generation: generation, remaining: remaining - 1)
        }
    }

    func noteScrollChain(of view: UIView) {
        guard isEnabled else { return }
        var ancestor: UIView? = view
        var depth = 0
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                event("scroll depth=\(depth) enabled=\(scroll.isScrollEnabled) delays=\(scroll.delaysContentTouches) cancels=\(scroll.canCancelContentTouches) dragging=\(scroll.isDragging)")
            }
            for gesture in current.gestureRecognizers ?? [] {
                if let press = gesture as? UILongPressGestureRecognizer {
                    event("longPress depth=\(depth) minimum=\(press.minimumPressDuration)s state=\(press.state.rawValue) enabled=\(press.isEnabled)")
                }
            }
            ancestor = current.superview
            depth += 1
        }
    }

    var report: String {
        let summary = rows.map { row in
            "\(row.name): n=\(row.sample.count), mean=\(row.sample.totalMS / Double(max(1, row.sample.count)))ms, max=\(row.sample.maxMS)ms, last=\(row.sample.lastMS)ms"
        }.joined(separator: "\n")
        let cache = "textMeasureCache: hits=\(TextMeasureCache.shared.hits), misses=\(TextMeasureCache.shared.misses)"
        return "ReadLoop interaction diagnostics\niOS \(UIDevice.current.systemVersion)\n\(summary)\n\(cache)\nalive=\(aliveTextViews), peak=\(peakAliveTextViews)\n--- recent 200 events (process-relative time) ---\n" + events.joined(separator: "\n")
    }

    private init() {}

    /// 只在 DEBUG 构建调用（AppModel.start）。可重复调用，幂等。
    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        startKeyboardObserver()
    }

    // MARK: - 热路径助手（disabled 时单分支 no-op）

    /// 执行 `work` 并记录耗时（毫秒）；disabled 时不计时直接返回。
    @discardableResult
    func timed<T>(_ key: Key, _ work: () throws -> T) rethrows -> T {
        guard isEnabled else { return try work() }
        let start = CFAbsoluteTimeGetCurrent()
        let out = try work()
        record(key, ms: (CFAbsoluteTimeGetCurrent() - start) * 1000)
        return out
    }

    func record(_ key: Key, ms: Double) {
        guard isEnabled else { return }
        var sample = samples[key] ?? Sample()
        sample.add(ms)
        samples[key] = sample
        if key == .selectionStart || key == .keyboardAppear || key == .keyboardToWillShow || key == .keyboardWillToDidShow || key == .keyboardAnimation || ms >= 8 {
            event("\(key.rawValue) \(String(format: "%.1f", ms))ms")
        }
    }

    // MARK: - os_signpost 区间

    struct Interval {
        let key: Key
        let start: CFTimeInterval
        let state: OSSignpostIntervalState?
    }

    func begin(_ key: Key) -> Interval {
        Interval(key: key, start: CFAbsoluteTimeGetCurrent(), state: isEnabled ? signposter.beginInterval(signpostName(key)) : nil)
    }

    /// 结束并记录时长。
    func end(_ interval: Interval) {
        if let state = interval.state {
            signposter.endInterval(signpostName(interval.key), state)
        }
        record(interval.key, ms: (CFAbsoluteTimeGetCurrent() - interval.start) * 1000)
    }

    /// 结束但不记录（失败/取消路径，避免空区间污染均值）。
    func abort(_ interval: Interval) {
        if let state = interval.state {
            signposter.endInterval(signpostName(interval.key), state)
        }
    }

    func signpostEvent(_ name: StaticString) {
        guard isEnabled else { return }
        signposter.emitEvent(name)
    }

    private func signpostName(_ key: Key) -> StaticString {
        switch key {
        case .readerOpen: "readerOpen"
        case .readerParse: "readerParse"
        case .readerToFirstPage: "readerToFirstPage"
        case .keyboardAppear: "keyboardAppear"
        case .keyboardToWillShow: "keyboardToWillShow"
        case .keyboardWillToDidShow: "keyboardWillToDidShow"
        case .keyboardAnimation: "keyboardAnimation"
        case .inputTouchToEditing: "inputTouchToEditing"
        case .responderAcquire: "responderAcquire"
        case .selectionResponderAcquire: "selectionResponderAcquire"
        case .mainQueueDelay: "mainQueueDelay"
        case .selectionStart: "selectionStart"
        case .textLayout: "textLayout"
        case .textUpdate: "textUpdate"
        case .streamDelta: "streamDelta"
        case .markdownRender: "markdownRender"
        case .textMeasure: "textMeasure"
        }
    }

    // MARK: - 只读文本视图存活计数（make/dismantle 都在主线程）

    func noteTextViewAlive(_ delta: Int) {
        guard isEnabled else { return }
        aliveTextViews += delta
        if aliveTextViews < 0 { aliveTextViews = 0 }
        if aliveTextViews > peakAliveTextViews { peakAliveTextViews = aliveTextViews }
    }

    // MARK: - 键盘冷路径（全局通知，非侵入）

    private func startKeyboardObserver() {
        let center = NotificationCenter.default
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                let info = notification.userInfo ?? [:]
                let begin = (info[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
                let end = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
                let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
                let phase = notification.name == UIResponder.keyboardWillChangeFrameNotification ? "will" : "did"
                self.event("keyboard.frame.\(phase) fromY=\(begin.minY) toY=\(end.minY) height=\(end.height) declared=\(duration)s")
            }
        }
        center.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lastEditBeganAt = ProcessInfo.processInfo.systemUptime
            self?.event("editing.begin")
        }
        center.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lastEditBeganAt = ProcessInfo.processInfo.systemUptime
            self?.event("editing.begin")
        }
        center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.keyboardWillShowAt = now
            self.event("keyboard.willShow")
            if let began = self.lastEditBeganAt, now - began < 5 {
                self.record(.keyboardToWillShow, ms: (now - began) * 1000)
            }
            if let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double {
                self.record(.keyboardAnimation, ms: duration * 1000)
            }
        }
        center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.event("keyboard.didShow")
            if let began = self.lastEditBeganAt, now - began < 5 {
                self.record(.keyboardAppear, ms: (now - began) * 1000)
            }
            if let will = self.keyboardWillShowAt, now - will < 5 {
                self.record(.keyboardWillToDidShow, ms: (now - will) * 1000)
            }
            self.lastEditBeganAt = nil
            self.keyboardWillShowAt = nil
        }
        for name in [UITextView.textDidEndEditingNotification, UITextField.textDidEndEditingNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.lastEditBeganAt = nil
                self?.keyboardWillShowAt = nil
                self?.event("editing.end")
            }
        }
        center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lastEditBeganAt = nil
            self?.keyboardWillShowAt = nil
            self?.event("keyboard.willHide")
        }
    }
}

extension Perf {
    /// 诊断屏只读快照（`isEnabled` 时才非空）。
    struct Row: Identifiable {
        let key: Key
        let name: String
        let sample: Sample
        var id: Key { key }
    }

    var rows: [Row] {
        let titles: [Key: String] = [
            .readerOpen: "打开阅读器（点书→首帧）",
            .readerParse: "EPUB 解析 open()",
            .readerToFirstPage: "Navigator→首帧",
            .keyboardAppear: "键盘（编辑开始→DidShow）",
            .keyboardToWillShow: "键盘（编辑开始→WillShow）",
            .keyboardWillToDidShow: "键盘（WillShow→DidShow）",
            .keyboardAnimation: "键盘（系统声明动画时长）",
            .inputTouchToEditing: "输入框（触摸→开始编辑回调）",
            .responderAcquire: "输入框 becomeFirstResponder 调用",
            .selectionResponderAcquire: "只读文本 becomeFirstResponder 调用",
            .mainQueueDelay: "主队列探针（超出 50ms 调度间隔）",
            .selectionStart: "选区（触摸→首次非空回调）",
            .textLayout: "文本 layoutSubviews（含 super）",
            .textUpdate: "文本 updateUIView（含比较/赋值）",
            .streamDelta: "流式可见批次刷新（模型侧）",
            .markdownRender: "Markdown 单次渲染",
            .textMeasure: "单次全量测量",
        ]
        return Key.allCases.compactMap { key in
            guard let sample = samples[key] else { return nil }
            return Row(key: key, name: titles[key] ?? key.rawValue, sample: sample)
        }
    }
}
