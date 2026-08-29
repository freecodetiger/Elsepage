import BenchCore
import Foundation

// readloop-bench — ReaderAgentBench runner (PRD §16).
//
// Usage:
//   swift run readloop-bench [--samples DIR] [--out FILE] [--dry-run] [--limit N]
//
// Environment (real runs only): DEEPSEEK_API_KEY, DEEPSEEK_BASE_URL, DEEPSEEK_MODEL.
// The key is read from the environment and never printed or written to reports.

struct CLIError: Error {
    let message: String
}

struct CLIArguments {
    var samplesDirectory = URL(fileURLWithPath: "Fixtures/BenchSamples")
    var outputURL: URL?
    var dryRun = false
    var limit: Int?

    static func parse(_ arguments: [String]) -> Result<CLIArguments, CLIError> {
        var parsed = CLIArguments()
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "--samples":
                guard index + 1 < arguments.count else { return .failure(CLIError(message: "--samples 需要一个目录参数")) }
                index += 1
                parsed.samplesDirectory = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--out":
                guard index + 1 < arguments.count else { return .failure(CLIError(message: "--out 需要一个文件参数")) }
                index += 1
                parsed.outputURL = URL(fileURLWithPath: arguments[index])
            case "--dry-run":
                parsed.dryRun = true
            case "--limit":
                guard index + 1 < arguments.count, let limit = Int(arguments[index + 1]), limit > 0 else {
                    return .failure(CLIError(message: "--limit 需要一个正整数参数"))
                }
                index += 1
                parsed.limit = limit
            case "--help", "-h":
                return .failure(CLIError(message: helpText))
            default:
                return .failure(CLIError(message: "未知参数: \(flag)\n\n\(helpText)"))
            }
            index += 1
        }
        return .success(parsed)
    }

    static let helpText = """
    readloop-bench — ReaderAgentBench 运行器 (PRD §16)

    用法:
      swift run readloop-bench [--samples DIR] [--out FILE] [--dry-run] [--limit N]

    参数:
      --samples DIR   样本目录 (默认: Fixtures/BenchSamples)
      --out FILE      JSON 报告输出路径 (默认: docs/bench/runs/bench-<时间戳>.json;
                      同目录会生成同名 -scoring.csv 人工评分表)
      --dry-run       无网络冒烟: 用 FakeModelClient 验证管线 (CI 安全)
      --limit N       只跑前 N 个样本

    环境变量 (真实跑批):
      DEEPSEEK_API_KEY    必填,仅从环境读取,绝不打印/入库
      DEEPSEEK_BASE_URL   默认 https://api.deepseek.com/v1
      DEEPSEEK_MODEL      默认 deepseek-chat

    常用:
      set -a; source ~/.readloop-bench-env; set +a   # 读取密钥环境
      swift run readloop-bench --limit 3             # 小规模真实跑批
      swift run readloop-bench --dry-run             # 无密钥冒烟
    """
}

let arguments = Array(CommandLine.arguments.dropFirst())
let parsed: CLIArguments
switch CLIArguments.parse(arguments) {
case .failure(let error):
    FileHandle.standardError.write(Data((error.message + "\n").utf8))
    exit(2)
case .success(let value):
    parsed = value
}

let stamp: String = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}()
let outputURL = parsed.outputURL ?? URL(fileURLWithPath: "docs/bench/runs/bench-\(stamp).json")
let options = BenchRunOptions(
    samplesDirectory: parsed.samplesDirectory,
    outputURL: outputURL,
    dryRun: parsed.dryRun,
    limit: parsed.limit
)

do {
    let summary = try await BenchRunner.run(options: options)
    let report = summary.report
    print("readloop-bench 完成")
    print("  dry-run: \(report.dryRun)")
    print("  model:   \(report.model.provider) / \(report.model.model) @ \(report.model.baseURL)")
    print("  samples: \(report.sampleCount) (completed \(report.totals.completedCount), failed \(report.totals.failedCount))")
    print("  报告:    \(summary.reportURL.path)")
    print("  评分表:  \(summary.scoringTemplateURL.path)")
} catch let error as BenchError {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
} catch {
    // Deliberately generic: error descriptions must never leak environment values.
    FileHandle.standardError.write(Data(("运行失败: \(String(describing: error))\n").utf8))
    exit(1)
}
