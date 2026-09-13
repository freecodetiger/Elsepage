import SwiftUI
import UIKit

/// DEBUG 交互性能摘要（spec 工作包 F / Phase 0）。
/// 展示 `Perf` 收集的本次运行采样，供真机自查与回归基线读取；Release 下
/// `Perf.isEnabled == false`，由调用侧整节隐藏。
struct PerfDiagnosticsView: View {
    @State private var revision = 0
    @State private var copied = false

    var body: some View {
        Section {
            let _ = revision
            let rows = Perf.shared.rows
            if rows.isEmpty {
                Text("暂无采样——DEBUG 构建下会在阅读 / 键盘 / 流式 / 排版时自动采集。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    LabeledContent(row.name, value: Self.fmt(row.sample))
                }
                LabeledContent("常驻只读文本视图", value: "\(Perf.shared.aliveTextViews)（峰值 \(Perf.shared.peakAliveTextViews)）")
                LabeledContent("文本测量缓存", value: "命中 \(TextMeasureCache.shared.hits) · 未命中 \(TextMeasureCache.shared.misses)")
            }
            Button(copied ? "已复制性能报告" : "复制性能报告") {
                UIPasteboard.general.string = Perf.shared.report
                copied = true
            }
            Button("清空采样，开始新一轮") {
                Perf.shared.reset()
                TextMeasureCache.shared.reset()
                RichTextBuilder.shared.reset()
                copied = false
                revision += 1
            }
            Button("刷新采样") { revision += 1 }
            #if DEBUG
            LabeledContent("自动化测试连接", value: DebugLoop.shared.message)
            Button(DebugLoop.shared.isRunning ? "停止测试服务" : "启动测试服务（USB）") {
                if DebugLoop.shared.isRunning { DebugLoop.shared.stop() }
                else { DebugLoop.shared.start() }
            }
            #endif
        } header: {
            Text("交互性能（本次运行）")
        } footer: {
            Text("真机 Instruments 同源：os_signpost（com.readloop.app / perf）。采样与最近 200 条事件仅在内存，退出即清。报告不含正文。选区指标截至回调，包含长按识别时间；键盘分段不等于系统/App CPU 分摊。")
        }
    }

    private static func fmt(_ sample: Perf.Sample) -> String {
        "\(sample.count) 次 · 均 \(Self.ms(sample.totalMS / Double(max(sample.count, 1)))) · 峰 \(Self.ms(sample.maxMS)) · 末 \(Self.ms(sample.lastMS))"
    }

    private static func ms(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0fms", value) : String(format: "%.1fms", value)
    }
}
