import Foundation

// MARK: - Judge snapshot extraction (BENCH-04)
//
// The regression gate compares judge-scored reports. `BenchJudgeSnapshot` is the
// minimal comparable projection of a run report: sample IDs plus per-sample
// dimension scores. Extraction is strict — the gate refuses to compare reports
// that are incomplete (failed pipeline samples, failed/missing judge sections),
// because a gate on partial data would silently weaken the discipline.

public struct BenchJudgedSample: Sendable, Equatable {
    public let id: String
    /// dimension (canonical PRD §16 name) → score 0...2
    public let scores: [String: Int]

    public init(id: String, scores: [String: Int]) {
        self.id = id
        self.scores = scores
    }

    public var total: Int { scores.values.reduce(0, +) }
}

public struct BenchJudgeSnapshot: Sendable, Equatable {
    public let runID: String
    public let samples: [BenchJudgedSample]

    public init(runID: String, samples: [BenchJudgedSample]) {
        self.runID = runID
        self.samples = samples
    }

    public func sample(id: String) -> BenchJudgedSample? {
        samples.first { $0.id == id }
    }

    /// Per-dimension average (0...2) over all samples, for the canonical dimensions.
    public func dimensionAverages() -> [String: Double] {
        var averages: [String: Double] = [:]
        for dimension in BenchScoringDimensions.all {
            let values = samples.compactMap { $0.scores[dimension] }
            averages[dimension] = values.isEmpty ? 0 : Double(values.reduce(0, +)) / Double(values.count)
        }
        return averages
    }

    /// Average per-sample total (0...22).
    public func totalAverage() -> Double {
        guard !samples.isEmpty else { return 0 }
        return Double(samples.reduce(0) { $0 + $1.total }) / Double(samples.count)
    }
}

public enum BenchCompareError: Error, Equatable, Sendable {
    /// The report cannot serve as a gate input (incomplete judging). The detail
    /// string names samples/reasons; it never contains environment values.
    case missingJudgeData(String)
    /// The two reports cover different sample sets.
    case sampleSetMismatch(onlyInBaseline: [String], onlyInCandidate: [String])

    public var message: String {
        switch self {
        case .missingJudgeData(let detail):
            return "报告缺少完整 judge 评分,无法对比: \(detail)"
        case .sampleSetMismatch(let onlyInBaseline, let onlyInCandidate):
            var parts: [String] = []
            if !onlyInBaseline.isEmpty {
                parts.append("仅基线包含: \(onlyInBaseline.joined(separator: ", "))")
            }
            if !onlyInCandidate.isEmpty {
                parts.append("仅候选包含: \(onlyInCandidate.joined(separator: ", "))")
            }
            return "两份报告的样本集不一致(\(parts.joined(separator: "; ")))。回归对比要求两边跑同一组样本。"
        }
    }
}

public enum BenchJudgeSnapshotExtractor {
    /// Extracts a complete judge snapshot from a run report, or throws with a
    /// precise reason. Every sample must be completed and judged `.ok` with all
    /// 11 canonical dimensions in range.
    public static func extract(from report: BenchRunReport) throws -> BenchJudgeSnapshot {
        guard !report.samples.isEmpty else {
            throw BenchCompareError.missingJudgeData("报告不包含任何样本")
        }
        var judged: [BenchJudgedSample] = []
        for sample in report.samples {
            guard sample.status == .completed else {
                throw BenchCompareError.missingJudgeData(
                    "样本 \(sample.id) 管线状态为 \(sample.status.rawValue),无完整回应可评;请重跑后对比"
                )
            }
            guard let judge = sample.judge else {
                throw BenchCompareError.missingJudgeData(
                    "样本 \(sample.id) 没有 judge 评分;请用 --judge 重跑该报告"
                )
            }
            guard judge.status == .ok else {
                throw BenchCompareError.missingJudgeData(
                    "样本 \(sample.id) judge 评分失败(\(judge.error ?? "未知原因"));请重跑后对比"
                )
            }
            var scores: [String: Int] = [:]
            for entry in judge.scores {
                scores[entry.dimension] = entry.score
            }
            let missing = BenchScoringDimensions.all.filter { scores[$0] == nil }
            guard missing.isEmpty else {
                throw BenchCompareError.missingJudgeData("样本 \(sample.id) 缺少维度评分: \(missing.joined(separator: "/"))")
            }
            let outOfRange = scores.values.contains { $0 < 0 || $0 > 2 }
            guard !outOfRange else {
                throw BenchCompareError.missingJudgeData("样本 \(sample.id) 存在超出 0–2 范围的评分")
            }
            judged.append(BenchJudgedSample(id: sample.id, scores: scores))
        }
        return BenchJudgeSnapshot(runID: report.runID, samples: judged)
    }
}

// MARK: - Comparison

/// Regression thresholds on the 0–2 dimension scale:
/// - any dimension average dropping more than `dimensionDropLimit` (default 0.5), or
/// - the average total (0–22) dropping more than `totalDropLimit` (default 0.3)
/// is a violation.
public struct BenchCompareThresholds: Sendable, Equatable {
    public var dimensionDropLimit: Double
    public var totalDropLimit: Double

    public static let standard = BenchCompareThresholds(dimensionDropLimit: 0.5, totalDropLimit: 0.3)

    public init(dimensionDropLimit: Double = 0.5, totalDropLimit: Double = 0.3) {
        self.dimensionDropLimit = dimensionDropLimit
        self.totalDropLimit = totalDropLimit
    }
}

public struct BenchDimensionDiff: Sendable, Equatable {
    public let dimension: String
    public let baseline: Double
    public let candidate: Double
    /// candidate − baseline; negative means the candidate regressed.
    public var delta: Double { candidate - baseline }
}

public struct BenchCompareResult: Sendable, Equatable {
    public let baselineRunID: String
    public let candidateRunID: String
    public let sampleCount: Int
    /// Canonical dimension order.
    public let dimensionDiffs: [BenchDimensionDiff]
    public let totalBaseline: Double
    public let totalCandidate: Double
    public let thresholds: BenchCompareThresholds
    /// Human-readable reasons for every threshold violation.
    public let violations: [String]

    public var passed: Bool { violations.isEmpty }
    public var totalDelta: Double { totalCandidate - totalBaseline }
}

public enum BenchReportComparator {
    public static func compare(
        baseline: BenchJudgeSnapshot,
        candidate: BenchJudgeSnapshot,
        thresholds: BenchCompareThresholds = .standard
    ) throws -> BenchCompareResult {
        let baselineIDs = Set(baseline.samples.map(\.id))
        let candidateIDs = Set(candidate.samples.map(\.id))
        guard baselineIDs == candidateIDs else {
            throw BenchCompareError.sampleSetMismatch(
                onlyInBaseline: baselineIDs.subtracting(candidateIDs).sorted(),
                onlyInCandidate: candidateIDs.subtracting(baselineIDs).sorted()
            )
        }

        let baselineAverages = baseline.dimensionAverages()
        let candidateAverages = candidate.dimensionAverages()
        var violations: [String] = []
        var diffs: [BenchDimensionDiff] = []
        for dimension in BenchScoringDimensions.all {
            let base = baselineAverages[dimension] ?? 0
            let cand = candidateAverages[dimension] ?? 0
            diffs.append(BenchDimensionDiff(dimension: dimension, baseline: base, candidate: cand))
            let drop = base - cand
            if drop > thresholds.dimensionDropLimit {
                violations.append(
                    "维度「\(dimension)」平均分 \(Self.decimal(base)) → \(Self.decimal(cand)),降幅 \(Self.decimal(drop)) 超过阈值 \(Self.decimal(thresholds.dimensionDropLimit))"
                )
            }
        }

        let totalBase = baseline.totalAverage()
        let totalCand = candidate.totalAverage()
        let totalDrop = totalBase - totalCand
        if totalDrop > thresholds.totalDropLimit {
            violations.append(
                "总分平均(0–22)\(Self.decimal(totalBase)) → \(Self.decimal(totalCand)),降幅 \(Self.decimal(totalDrop)) 超过阈值 \(Self.decimal(thresholds.totalDropLimit))"
            )
        }

        return BenchCompareResult(
            baselineRunID: baseline.runID,
            candidateRunID: candidate.runID,
            sampleCount: baseline.samples.count,
            dimensionDiffs: diffs,
            totalBaseline: totalBase,
            totalCandidate: totalCand,
            thresholds: thresholds,
            violations: violations
        )
    }

    /// Exit-code mapping for the compare CLI: 0 = pass, 1 = regression.
    public static func exitCode(for result: BenchCompareResult) -> Int {
        result.passed ? 0 : 1
    }

    static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
