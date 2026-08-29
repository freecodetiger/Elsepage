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
    public var environment: [String: String]

    public init(
        samplesDirectory: URL, outputURL: URL, dryRun: Bool = false,
        limit: Int? = nil, environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.samplesDirectory = samplesDirectory
        self.outputURL = outputURL
        self.dryRun = dryRun
        self.limit = limit
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
///      evidence used, routing info, timings, usage), and
///   2. a human scoring template (CSV) with the 11 PRD §16 dimensions as columns.
public enum BenchRunner {
    public static func run(options: BenchRunOptions, now: Date = Date()) async throws -> BenchRunSummary {
        var samples = try BenchSampleLoader.load(from: options.samplesDirectory)
        if let limit = options.limit, limit >= 0 {
            samples = Array(samples.prefix(limit))
        }

        let (client, modelInfo) = try BenchModelClientFactory.make(dryRun: options.dryRun, environment: options.environment)
        let pipeline = BenchPipeline()

        var runs: [BenchSampleRun] = []
        runs.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() {
            let bookID = BookID(rawValue: stableUUID("book:\(sample.book.title)"))
            let run = await pipeline.run(sample, index: index, bookID: bookID, client: client)
            runs.append(run)
        }

        let totalSeconds = runs.reduce(0.0) { $0 + $1.timings.totalSeconds }
        let report = BenchRunReport(
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
    static func scoringTemplate(report: BenchRunReport) -> String {
        var header = ["sample_id", "category", "status"]
        header.append(contentsOf: BenchScoringDimensions.all)
        header.append(contentsOf: ["overall_0_10", "notes"])

        var lines = [header.map(Self.csvField).joined(separator: ",")]
        for sample in report.samples {
            var row = [sample.id, sample.category, sample.status.rawValue]
            row.append(contentsOf: BenchScoringDimensions.all.map { _ in "" })
            row.append("")
            row.append("")
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
