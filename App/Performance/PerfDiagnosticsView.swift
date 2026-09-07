import SwiftUI

/// DEBUG 交互性能摘要（spec 工作包 F / Phase 0）。
/// 展示 `Perf` 收集的本次运行采样，供真机自查与回归基线读取；Release 下
/// `Perf.isEnabled == false`，由调用侧整节隐藏。
struct PerfDiagnosticsView: View {
    var body: some View {
        Section {
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
            }
        } header: {
            Text("交互性能（本次运行）")
        } footer: {
            Text("真机 Instruments 同源：os_signpost（com.readloop.app / perf）。数字仅内存累积，退出即清，不落盘。")
        }
    }

    private static func fmt(_ sample: Perf.Sample) -> String {
        "\(sample.count) 次 · 均 \(Self.ms(sample.totalMS / Double(max(sample.count, 1)))) · 峰 \(Self.ms(sample.maxMS)) · 末 \(Self.ms(sample.lastMS))"
    }

    private static func ms(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0fms", value) : String(format: "%.1fms", value)
    }
}
