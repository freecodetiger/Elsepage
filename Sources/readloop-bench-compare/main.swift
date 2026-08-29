import BenchCore
import Foundation

// readloop-bench-compare — BENCH-04 基线对比与回归阻断。
//
// Usage:
//   swift run readloop-bench-compare BASELINE.json CANDIDATE.json [--dimension-limit X] [--total-limit Y]
//
// Both reports must be judge-scored (produced with `readloop-bench --judge`).
// Exit codes:
//   0  pass — no threshold violation
//   1  regression — at least one dimension / total average dropped beyond the limit
//   2  usage or data error (bad args, missing judge data, sample-set mismatch)

struct CompareCLIError: Error {
    let message: String
    let exitCode: Int32
}

struct CompareArguments {
    var baselineURL: URL?
    var candidateURL: URL?
    var dimensionLimit: Double?
    var totalLimit: Double?

    static let helpText = """
    readloop-bench-compare — BENCH-04 基线对比与回归阻断

    用法:
      swift run readloop-bench-compare BASELINE.json CANDIDATE.json [--dimension-limit X] [--total-limit Y]

    位置参数:
      BASELINE.json    已存档的基线报告 (--judge 评分版)
      CANDIDATE.json   本次候选运行的报告 (--judge 评分版)

    选项:
      --dimension-limit X   维度均分降幅阈值 (0–2 量表, 默认 0.5; 降幅超过即回归)
      --total-limit Y       总分均分降幅阈值 (0–22 量表, 默认 0.3; 降幅超过即回归)
      阈值也可用环境变量 BENCH_COMPARE_DIMENSION_LIMIT / BENCH_COMPARE_TOTAL_LIMIT
      提供; 命令行参数优先于环境变量。

    退出码:
      0  通过 (无阈值违规)
      1  回归 (任一维度或总分降幅超过阈值, 阻断合并)
      2  参数或数据错误 (缺 judge 评分 / 样本集不一致 / 文件不可读)

    回归流程见 docs/bench/REGRESSION.md。
    """

    static func parse(_ arguments: [String]) -> Result<CompareArguments, CompareCLIError> {
        var parsed = CompareArguments()
        var positional: [String] = []
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "--dimension-limit", "--total-limit":
                index += 1
                guard index < arguments.count, let number = Double(arguments[index]) else {
                    return .failure(CompareCLIError(message: "\(flag) 需要一个数字参数", exitCode: 2))
                }
                if flag == "--dimension-limit" {
                    parsed.dimensionLimit = number
                } else {
                    parsed.totalLimit = number
                }
            case "--help", "-h":
                return .failure(CompareCLIError(message: helpText, exitCode: 0))
            default:
                positional.append(flag)
            }
            index += 1
        }
        guard positional.count == 2 else {
            return .failure(CompareCLIError(message: "需要恰好两个报告参数: BASELINE.json CANDIDATE.json\n\n\(helpText)", exitCode: 2))
        }
        parsed.baselineURL = URL(fileURLWithPath: positional[0])
        parsed.candidateURL = URL(fileURLWithPath: positional[1])
        return .success(parsed)
    }
}

func loadReport(at url: URL) throws -> BenchRunReport {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CompareCLIError(message: "报告文件不存在: \(url.path)", exitCode: 2)
    }
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw CompareCLIError(message: "报告文件不可读: \(url.path)", exitCode: 2)
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
        return try decoder.decode(BenchRunReport.self, from: data)
    } catch {
        throw CompareCLIError(message: "报告不是合法的 bench 运行 JSON: \(url.path)", exitCode: 2)
    }
}

func threshold(fromEnvironment key: String) -> Double? {
    guard let raw = ProcessInfo.processInfo.environment[key]?
        .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
    return Double(raw)
}

/// Left-pads to a display column; CJK width is approximated by counting
/// non-ASCII characters twice so the table stays roughly aligned.
func padded(_ text: String, _ width: Int) -> String {
    let displayWidth = text.unicodeScalars.reduce(0) { $0 + ($1.isASCII ? 1 : 2) }
    guard displayWidth < width else { return text }
    return text + String(repeating: " ", count: width - displayWidth)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let parsed: CompareArguments
switch CompareArguments.parse(arguments) {
case .failure(let error):
    FileHandle.standardError.write(Data((error.message + "\n").utf8))
    exit(error.exitCode)
case .success(let value):
    parsed = value
}

// Threshold precedence: CLI flag > environment > default.
let thresholds = BenchCompareThresholds(
    dimensionDropLimit: parsed.dimensionLimit
        ?? threshold(fromEnvironment: "BENCH_COMPARE_DIMENSION_LIMIT")
        ?? BenchCompareThresholds.standard.dimensionDropLimit,
    totalDropLimit: parsed.totalLimit
        ?? threshold(fromEnvironment: "BENCH_COMPARE_TOTAL_LIMIT")
        ?? BenchCompareThresholds.standard.totalDropLimit
)

do {
    let baselineReport = try loadReport(at: parsed.baselineURL ?? URL(fileURLWithPath: "-"))
    let candidateReport = try loadReport(at: parsed.candidateURL ?? URL(fileURLWithPath: "-"))
    let baseline = try BenchJudgeSnapshotExtractor.extract(from: baselineReport)
    let candidate = try BenchJudgeSnapshotExtractor.extract(from: candidateReport)
    let result = try BenchReportComparator.compare(baseline: baseline, candidate: candidate, thresholds: thresholds)

    var lines: [String] = []
    lines.append("readloop-bench-compare")
    lines.append("  基线:    \(parsed.baselineURL?.path ?? "-") (run \(baseline.runID), \(result.sampleCount) 样本)")
    lines.append("  候选:    \(parsed.candidateURL?.path ?? "-") (run \(candidate.runID))")
    lines.append("  阈值:    维度降幅 > \(String(format: "%.2f", thresholds.dimensionDropLimit)) 或 总分降幅 > \(String(format: "%.2f", thresholds.totalDropLimit)) 判为回归")
    lines.append("")
    lines.append("  \(padded("维度", 14))\(padded("基线", 8))\(padded("候选", 8))差值")
    for diff in result.dimensionDiffs {
        lines.append("  \(padded(diff.dimension, 14))\(padded(String(format: "%.2f", diff.baseline), 8))\(padded(String(format: "%.2f", diff.candidate), 8))\(String(format: "%+.2f", diff.delta))")
    }
    lines.append("  \(padded("总分(0–22)", 14))\(padded(String(format: "%.2f", result.totalBaseline), 8))\(padded(String(format: "%.2f", result.totalCandidate), 8))\(String(format: "%+.2f", result.totalDelta))")
    lines.append("")
    if result.passed {
        lines.append("  结果: PASS — 未触发回归阈值")
    } else {
        lines.append("  结果: FAIL — 触发回归阻断:")
        for violation in result.violations {
            lines.append("    - \(violation)")
        }
        lines.append("  合并被阻断; 如确属预期改进, 按文档归档新基线 (docs/bench/REGRESSION.md)。")
    }
    print(lines.joined(separator: "\n"))
    exit(Int32(BenchReportComparator.exitCode(for: result)))
} catch let error as CompareCLIError {
    FileHandle.standardError.write(Data((error.message + "\n").utf8))
    exit(error.exitCode)
} catch let error as BenchCompareError {
    FileHandle.standardError.write(Data((error.message + "\n").utf8))
    exit(2)
} catch {
    // Deliberately generic: never echo environment values.
    FileHandle.standardError.write(Data(("对比失败: \(String(describing: error))\n").utf8))
    exit(2)
}
