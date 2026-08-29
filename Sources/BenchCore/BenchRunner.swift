import AgentRuntime
import Foundation
import LibraryCore

// MARK: - Run report

public struct BenchRunReport: Codable, Sendable {
    public let runID: String
    public let startedAt: Date
    public let completedAt: Date
    public let dryRun: Bool
    public let model: BenchModelInfo
    public let promptVersion: String
    public let sampleCount: Int
    public let samples: [BenchSampleRun]
    public let totals: BenchTotals
    /// Present only when the run was started with `--judge` (BENCH-03).
    /// Old reports without this field keep decoding (optional key).
    public var judge: BenchJudgeRunSummary?
}

public struct BenchTotals: Codable, Sendable {
    public let completedCount: Int
    public let failedCount: Int
    public let totalSeconds: Double
}

// MARK: - Scoring template (PRD §16, 11 dimensions)

/// The 11 PRD §16 evaluation dimensions, used verbatim as CSV columns.
public enum BenchScoringDimensions {
    public static let all: [String] = [
        "理解用户", "理解书籍", "知识准确", "知识增量", "连接质量", "个性化",
        "追问质量", "克制", "恭维控制", "可追溯性", "用户自主",
    ]
}

// MARK: - Runner

public struct BenchRunOptions: Sendable {
    public var samplesDirectory: URL
    public var outputURL: URL
    public var dryRun: Bool
    public var limit: Int?
    /// BENCH-03: run the LLM-as-judge scoring pass after the pipeline.
    public var judgeEnabled: Bool
    /// BENCH-03: judge at most N samples (cheap smokes). Counts judge calls;
    /// samples skipped for lack of a response do not consume the budget.
    public var judgeLimit: Int?
    public var environment: [String: String]

    public init(
        samplesDirectory: URL, outputURL: URL, dryRun: Bool = false,
        limit: Int? = nil, judgeEnabled: Bool = false, judgeLimit: Int? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.samplesDirectory = samplesDirectory
        self.outputURL = outputURL
        self.dryRun = dryRun
        self.limit = limit
        self.judgeEnabled = judgeEnabled
        self.judgeLimit = judgeLimit
        self.environment = environment
    }
}

public struct BenchRunSummary: Sendable {
    public let reportURL: URL
    public let scoringTemplateURL: URL
    public let report: BenchRunReport
}

/// Loads samples, runs them sequentially through `BenchPipeline` with one model
/// client, and writes:
///   1. a timestamped structured JSON run report (per-sample response, citations,
///      evidence used, routing info, timings, usage — plus per-sample LLM-as-judge
///      scores and aggregate dimension averages when `--judge` is on), and
///   2. a human scoring template (CSV) with the 11 PRD §16 dimensions as columns.
public enum BenchRunner {
    public static func run(options: BenchRunOptions, now: Date = Date()) async throws -> BenchRunSummary {
        var samples = try BenchSampleLoader.load(from: options.samplesDirectory)
        if let limit = options.limit, limit >= 0 {
            samples = Array(samples.prefix(limit))
        }

        let (client, modelInfo) = try BenchModelClientFactory.make(dryRun: options.dryRun, environment: options.environment)
        // Judge client is created up front so a missing key fails before any
        // pipeline call is spent on a run that could not be scored.
        var judgeClient: (any ModelClient)?
        var judgeModelInfo: BenchModelInfo?
        if options.judgeEnabled {
            let judgeFactoryResult = try BenchJudgeModelFactory.make(dryRun: options.dryRun, environment: options.environment)
            judgeClient = judgeFactoryResult.client
            judgeModelInfo = judgeFactoryResult.info
        }
        let pipeline = BenchPipeline()

        var runs: [BenchSampleRun] = []
        runs.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() {
            let bookID = BookID(rawValue: stableUUID("book:\(sample.book.title)"))
            let run = await pipeline.run(sample, index: index, bookID: bookID, client: client)
            runs.append(run)
        }

        // --- LLM-as-judge pass (BENCH-03) ---
        // A judge failure (call or parse) marks the sample's judge section as
        // `.failed` and never aborts the run; skipped samples (no response)
        // don't consume the --judge-limit budget.
        if options.judgeEnabled, let judgeClient {
            let judge = BenchJudge()
            var judgeCalls = 0
            for index in runs.indices {
                if let judgeLimit = options.judgeLimit, judgeCalls >= judgeLimit { break }
                guard runs[index].status == .completed, runs[index].response != nil else {
                    runs[index].judge = .skipped(reason: "样本管线未产出回应,无可评分")
                    continue
                }
                judgeCalls += 1
                let input = BenchJudgeInput(sample: samples[index], run: runs[index])
                runs[index].judge = await judge.run(input: input, client: judgeClient)
            }
        }

        let totalSeconds = runs.reduce(0.0) { $0 + $1.timings.totalSeconds }
        let judgeSummary: BenchJudgeRunSummary?
        if options.judgeEnabled, let judgeModelInfo {
            judgeSummary = BenchJudgeRunSummary(
                model: judgeModelInfo,
                promptVersion: JudgePrompt.version,
                aggregate: BenchJudgeAggregator.aggregate(runs: runs)
            )
        } else {
            judgeSummary = nil
        }
        var report = BenchRunReport(
            runID: stableUUID("run:\(now.timeIntervalSince1970):\(samples.count)").description,
            startedAt: now,
            completedAt: Date(),
            dryRun: options.dryRun,
            model: modelInfo,
            promptVersion: "reader-reflection-v3",
            sampleCount: runs.count,
            samples: runs,
            totals: BenchTotals(
                completedCount: runs.filter { $0.status == .completed }.count,
                failedCount: runs.filter { $0.status == .failed }.count,
                totalSeconds: totalSeconds
            )
        )
        report.judge = judgeSummary

        // Write the JSON report and the scoring CSV next to it.
        let output = options.outputURL
        let directory = output.deletingLastPathComponent()
        if !directory.path.isEmpty {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reportData = try encoder.encode(report)
        try reportData.write(to: output, options: .atomic)

        let scoringURL = output.deletingPathExtension().appendingPathExtension("csv")
        try scoringTemplate(report: report).write(to: scoringURL, atomically: true, encoding: .utf8)

        return BenchRunSummary(reportURL: output, scoringTemplateURL: scoringURL, report: report)
    }

    // MARK: Scoring template

    /// CSV: one row per sample; the 11 PRD dimensions are empty columns for the
    /// human scorer to fill (suggested scale 0–2, see docs/bench/README.md).
    /// When the run was judged, the trailing `judge_status` / `judge_total_0_22`
    /// columns carry the automated score for reference; the human columns stay
    /// human.
    static func scoringTemplate(report: BenchRunReport) -> String {
        var header = ["sample_id", "category", "status"]
        header.append(contentsOf: BenchScoringDimensions.all)
        header.append(contentsOf: ["overall_0_10", "notes", "judge_status", "judge_total_0_22"])

        var lines = [header.map(Self.csvField).joined(separator: ",")]
        for sample in report.samples {
            var row = [sample.id, sample.category, sample.status.rawValue]
            row.append(contentsOf: BenchScoringDimensions.all.map { _ in "" })
            row.append("")
            row.append("")
            if let judge = sample.judge {
                row.append(judge.status.rawValue)
                if let total = judge.total {
                    row.append(String(total))
                } else {
                    row.append("")
                }
            } else {
                row.append("")
                row.append("")
            }
            lines.append(row.map(Self.csvField).joined(separator: ","))
        }
        // UTF-8 BOM so Chinese headers open correctly in Excel/Numbers.
        return "\u{FEFF}" + lines.joined(separator: "\n") + "\n"
    }

    static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
