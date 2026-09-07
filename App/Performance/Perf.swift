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
        case streamDelta         // 流式单 delta：模型侧合并+剥 citation
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
        center.addObserver(forName: UITextView.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lastEditBeganAt = CFAbsoluteTimeGetCurrent()
        }
        center.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lastEditBeganAt = CFAbsoluteTimeGetCurrent()
        }
        center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, let began = self.lastEditBeganAt else { return }
            self.lastEditBeganAt = nil
            self.record(.keyboardAppear, ms: (CFAbsoluteTimeGetCurrent() - began) * 1000)
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
            .streamDelta: "流式单 delta（模型侧）",
            .markdownRender: "Markdown 单次渲染",
            .textMeasure: "单次全量测量",
        ]
        return Key.allCases.compactMap { key in
            guard let sample = samples[key] else { return nil }
            return Row(key: key, name: titles[key] ?? key.rawValue, sample: sample)
        }
    }
}
