import AgentRuntime
import BenchCore
import Foundation
import Testing

// MARK: - Synthetic judged-report construction
//
// BenchRunReport has no public memberwise init on purpose (reports are produced
// by the runner); tests build judged reports as JSON dictionaries and go through
// the real Codable path, which also exercises report backward compatibility.

private let dimensions = ["理解用户", "理解书籍", "知识准确", "知识增量", "连接质量", "个性化", "追问质量", "克制", "恭维控制", "可追溯性", "用户自主"]

private func judgedReportData(
    runID: String,
    samples: [(id: String, dimensionScores: [String: Int])],
    includeJudge: Bool = true,
    judgeStatus: String = "ok",
    judgeError: String? = nil
) throws -> Data {
    let sampleObjects: [[String: Any]] = samples.map { sample in
        let scores: [[String: Any]] = dimensions.map { dimension in
            [
                "dimension": dimension,
                "score": sample.dimensionScores[dimension] ?? 1,
                "justification": "合成评分",
            ]
        }
        var object: [String: Any] = [
            "id": sample.id,
            "index": 0,
            "category": "合成",
            "bookTitle": "合成书",
            "chapter": NSNull(),
            "status": "completed",
            "error": NSNull(),
            "response": "合成回应。",
            "truncated": false,
            "citations": [] as [[String: Any]],
            "evidence": [] as [[String: Any]],
            "routing": [
                "intent": "passageObservation",
                "usedFallback": false,
                "memoryEvidenceCount": 0,
                "assembledEvidenceCount": 0,
            ],
            "timings": [
                "routingSeconds": 0.0, "retrievalSeconds": 0.0,
                "assemblySeconds": 0.0, "replySeconds": 0.0, "totalSeconds": 0.0,
            ],
            "promptCharacterCount": 1,
            "expectedFeedbackNotes": [] as [String],
        ]
        if includeJudge {
            var judgeSection: [String: Any] = [
                "status": judgeStatus,
                "scores": scores,
                "total": scores.reduce(0) { $0 + (($1["score"] as? Int) ?? 0) },
                "comment": "合成总评",
                "seconds": 0.1,
            ]
            judgeSection["error"] = judgeError ?? NSNull()
            object["judge"] = judgeSection
        }
        return object
    }
    let report: [String: Any] = [
        "runID": runID,
        "startedAt": "2026-08-29T00:00:00Z",
        "completedAt": "2026-08-29T00:00:01Z",
        "dryRun": false,
        "model": ["provider": "openAICompatible", "model": "deepseek-chat", "baseURL": "https://api.deepseek.com/v1"],
        "promptVersion": "reader-reflection-v3",
        "sampleCount": samples.count,
        "samples": sampleObjects,
        "totals": ["completedCount": samples.count, "failedCount": 0, "totalSeconds": 0.0],
    ]
    return try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
}

private func decodeReport(_ data: Data) throws -> BenchRunReport {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(BenchRunReport.self, from: data)
}

private func snapshot(_ data: Data) throws -> BenchJudgeSnapshot {
    try BenchJudgeSnapshotExtractor.extract(from: decodeReport(data))
}

private func uniformScores(_ value: Int) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: dimensions.map { ($0, value) })
}

// MARK: - Snapshot extraction

@Suite struct BenchJudgeSnapshotExtractionTests {
    @Test func extractsCompleteJudgedReports() throws {
        let data = try judgedReportData(runID: "r1", samples: [
            ("s1", uniformScores(1)), ("s2", uniformScores(2)),
        ])
        let snapshot = try snapshot(data)
        #expect(snapshot.runID == "r1")
        #expect(snapshot.samples.count == 2)
        #expect(snapshot.totalAverage() == 16.5) // (11 + 22) / 2
        #expect(snapshot.dimensionAverages()["理解用户"] == 1.5)
    }

    @Test func rejectsReportsWithoutJudgeData() throws {
        let data = try judgedReportData(runID: "r1", samples: [("s1", uniformScores(1))], includeJudge: false)
        do {
            _ = try snapshot(data)
            Issue.record("无 judge 数据应被拒绝")
        } catch let error as BenchCompareError {
            #expect(error.message.contains("judge"))
        }
    }

    @Test func rejectsJudgeFailedAndOutOfRangeScores() throws {
        // judge 状态为 failed 的样本会被拒绝,并携带原因。
        let failedData = try judgedReportData(
            runID: "r1", samples: [("s1", uniformScores(1))],
            judgeStatus: "failed", judgeError: "judge JSON 无法解析"
        )
        do {
            _ = try snapshot(failedData)
            Issue.record("judge failed 应被拒绝")
        } catch let error as BenchCompareError {
            #expect(error.message.contains("s1"))
            #expect(error.message.contains("judge JSON 无法解析"))
        }

        // 超出 0–2 范围的评分会被拒绝。
        let outOfRange = try judgedReportData(runID: "r2", samples: [("s1", ["克制": 3])])
        do {
            _ = try snapshot(outOfRange)
            Issue.record("超范围分数应被拒绝")
        } catch let error as BenchCompareError {
            #expect(error.message.contains("0–2"))
        }
    }
}

// MARK: - Comparison & exit semantics

@Suite struct BenchReportComparatorTests {
    private func baselineSnapshot() throws -> BenchJudgeSnapshot {
        try snapshot(try judgedReportData(runID: "baseline", samples: [("s1", uniformScores(1)), ("s2", uniformScores(1))]))
    }

    @Test func selfCompareHasZeroDiffAndPassesWithExitCodeZero() throws {
        let baseline = try baselineSnapshot()
        let result = try BenchReportComparator.compare(baseline: baseline, candidate: baseline)
        #expect(result.passed)
        #expect(result.violations.isEmpty)
        #expect(result.dimensionDiffs.allSatisfy { $0.delta == 0 })
        #expect(result.totalDelta == 0)
        #expect(BenchReportComparator.exitCode(for: result) == 0)
    }

    @Test func degradedCandidateTripsEveryDimensionAndTotal() throws {
        let baseline = try baselineSnapshot()
        let degraded = try snapshot(try judgedReportData(runID: "candidate", samples: [
            ("s1", uniformScores(0)), ("s2", uniformScores(0)),
        ]))
        let result = try BenchReportComparator.compare(baseline: baseline, candidate: degraded)
        #expect(!result.passed)
        #expect(BenchReportComparator.exitCode(for: result) == 1)
        // 11 dimensions + total all violated.
        #expect(result.violations.count == 12)
        #expect(result.dimensionDiffs.allSatisfy { $0.delta == -1.0 })
        #expect(result.violations.contains { $0.contains("总分") })
    }

    @Test func thresholdOverridesFlipTheVerdict() throws {
        let baseline = try baselineSnapshot()
        // Candidate: one sample drops 克制 by 1 → dimension drop 0.5, total drop 0.5.
        var degradedScores = uniformScores(1)
        degradedScores["克制"] = 0
        let candidate = try snapshot(try judgedReportData(runID: "candidate", samples: [
            ("s1", degradedScores), ("s2", uniformScores(1)),
        ]))

        // Defaults: total drop 0.5 > 0.3 → FAIL (dimension 0.5 is not > 0.5).
        let defaultResult = try BenchReportComparator.compare(baseline: baseline, candidate: candidate, thresholds: BenchCompareThresholds.standard)
        #expect(!defaultResult.passed)
        #expect(defaultResult.violations.count == 1)
        #expect(defaultResult.violations[0].contains("总分"))

        // Relax total limit above the drop → PASS (dimension exactly at limit is not a violation).
        let relaxed = try BenchReportComparator.compare(
            baseline: baseline, candidate: candidate,
            thresholds: BenchCompareThresholds(dimensionDropLimit: 0.5, totalDropLimit: 0.6)
        )
        #expect(relaxed.passed)
        #expect(BenchReportComparator.exitCode(for: relaxed) == 0)

        // Tighten the dimension limit below the drop → dimension violation flips it back to FAIL.
        let tightened = try BenchReportComparator.compare(
            baseline: baseline, candidate: candidate,
            thresholds: BenchCompareThresholds(dimensionDropLimit: 0.4, totalDropLimit: 0.6)
        )
        #expect(!tightened.passed)
        #expect(tightened.violations.count == 1)
        #expect(tightened.violations[0].contains("克制"))
    }

    @Test func improvementPassesEvenWhenPositive() throws {
        let baseline = try baselineSnapshot()
        let better = try snapshot(try judgedReportData(runID: "candidate", samples: [
            ("s1", uniformScores(2)), ("s2", uniformScores(2)),
        ]))
        let result = try BenchReportComparator.compare(baseline: baseline, candidate: better)
        #expect(result.passed)
        #expect(result.totalDelta == 11.0)
    }

    @Test func mismatchedSampleSetsAreRejected() throws {
        let baseline = try baselineSnapshot()
        let other = try snapshot(try judgedReportData(runID: "candidate", samples: [("s1", uniformScores(1)), ("sX", uniformScores(1))]))
        do {
            _ = try BenchReportComparator.compare(baseline: baseline, candidate: other)
            Issue.record("样本集不一致应被拒绝")
        } catch let error as BenchCompareError {
            #expect(error.message.contains("仅候选包含: sX"))
            #expect(error.message.contains("仅基线包含: s2"))
        }
    }
}
