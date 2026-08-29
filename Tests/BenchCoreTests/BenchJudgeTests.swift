import AgentRuntime
import BenchCore
import Foundation
import Testing

/// Resolves repo paths from the test file location (tests run from the package root).
private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // Tests/BenchCoreTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // package root

private let samplesDirectory = packageRoot.appendingPathComponent("Fixtures/BenchSamples", isDirectory: true)
private let committedBaselineURL = packageRoot.appendingPathComponent("docs/bench/runs/2026-08-29-baseline.json")

private func temporaryOutput() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("readloop-bench-judge-tests-\(UUID().uuidString)")
        .appendingPathComponent("bench-report.json")
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("readloop-bench-judge-tests-\(UUID().uuidString)", isDirectory: true)
}

private func judgeJSON(scores: [String: Int], comment: String = "总体成立") -> String {
    let order = ["理解用户", "理解书籍", "知识准确", "知识增量", "连接质量", "个性化", "追问质量", "克制", "恭维控制", "可追溯性", "用户自主"]
    let entries = order.map { dimension -> String in
        let score = scores[dimension] ?? 1
        return #"{"dimension": "\#(dimension)", "score": \#(score), "justification": "理由-\#(dimension)"}"#
    }
    return #"{"scores": [\#(entries.joined(separator: ","))], "comment": "\#(comment)"}"#
}

private func fakeJudgeClient(_ content: String, terminalFailure: ModelFailure? = nil) -> FakeModelClient {
    FakeModelClient(
        events: [.started, .textDelta(content), .completed(ModelResponse(id: "judge-test", content: content, finishReason: "stop"))],
        terminalFailure: terminalFailure
    )
}

private func makeJudgeInput(response: String = "[E1] 这个说法有依据。") -> BenchJudgeInput {
    BenchJudgeInput(
        sampleID: "test-sample",
        category: "观点",
        reflection: "我觉得作者说的差序格局其实就是人情社会。",
        expectedFeedbackNotes: ["理解用户:确认隐含前提", "克制:80–140 字"],
        response: response,
        truncated: false,
        evidence: [BenchJudgeEvidence(id: "E1", kind: "nearbyPassage", title: "当前阅读位置", excerpt: "乡土社会的差序格局像水波纹。")],
        citationMarkers: ["E1"]
    )
}

// MARK: - Prompt assembly

@Suite struct JudgePromptTests {
    @Test func systemMessageEncodesAllDimensionsRubricAndContract() {
        let prompt = JudgePrompt.systemMessage
        for dimension in BenchScoringDimensions.all {
            #expect(prompt.contains(dimension), "judge prompt 缺少维度: \(dimension)")
        }
        #expect(BenchScoringDimensions.all.count == 11)
        // 0–2 rubric anchors aligned with the Phase 5 human rubric.
        #expect(prompt.contains("0–2"))
        #expect(prompt.contains("明显违背"))
        #expect(prompt.contains("合格但不突出"))
        #expect(prompt.contains("做得明显好"))
        // Strict JSON output contract.
        #expect(prompt.contains("JSON"))
        #expect(prompt.contains("justification"))
        #expect(prompt.contains("scores"))
    }

    @Test func userMessageCarriesSampleMaterial() {
        let message = JudgePrompt.userMessage(input: makeJudgeInput())
        #expect(message.contains("test-sample"))
        #expect(message.contains("观点"))
        #expect(message.contains("差序格局"))
        #expect(message.contains("80–140 字"))
        #expect(message.contains("[E1] 这个说法有依据。"))
        #expect(message.contains("E1 (nearbyPassage, 当前阅读位置)"))
        #expect(message.contains("通过校验的引用标记: [E1]"))
    }

    @Test func userMessageMarksTruncationAndEmptyEvidence() {
        var input = makeJudgeInput(response: "被截断的回应")
        input = BenchJudgeInput(
            sampleID: "t", category: "情绪", reflection: "r", expectedFeedbackNotes: [],
            response: "被截断的回应", truncated: true, evidence: [], citationMarkers: []
        )
        let message = JudgePrompt.userMessage(input: input)
        #expect(message.contains("被截断"))
        #expect(message.contains("无——本样本没有可引用证据"))
        #expect(message.contains("引用标记: 无"))
    }
}

// MARK: - Tolerant JSON parsing

@Suite struct JudgeOutputParserTests {
    private let allDimensions = BenchScoringDimensions.all

    @Test func parsesPlainFencedAndProseWrappedJSON() {
        for variant in [judgeJSON(scores: [:]), "```json\n\(judgeJSON(scores: [:]))\n```", "好的,以下是评分:\n\(judgeJSON(scores: [:]))\n以上。"] {
            let parsed: BenchJudgeOutputParser.ParsedJudge
            switch BenchJudgeOutputParser.parse(variant) {
            case .success(let value): parsed = value
            case .failure(let error): Issue.record("应可解析: \(error.message)"); return
            }
            #expect(parsed.scores.count == 11)
            #expect(parsed.scores.map(\.dimension) == allDimensions)
            #expect(parsed.scores.allSatisfy { $0.justification.contains("理由-") })
            #expect(parsed.comment == "总体成立")
        }
    }

    @Test func clampsAndRoundsScoresIntoRange() {
        // 全 11 维齐全,其中三个维度给越界/小数分数,验证收敛到 0...2 整数。
        let overrides: [String: String] = [
            "理解用户": "2.6", "克制": "-0.4", "恭维控制": "1.5",
        ]
        let entries = BenchScoringDimensions.all.map { dimension -> String in
            let raw = overrides[dimension] ?? "1"
            return #"{"dimension": "\#(dimension)", "score": \#(raw), "justification": "x"}"#
        }
        let text = #"{"scores": [\#(entries.joined(separator: ","))]}"#
        guard case .success(let parsed) = BenchJudgeOutputParser.parse(text) else {
            Issue.record("应可解析"); return
        }
        #expect(parsed.scores.first { $0.dimension == "理解用户" }?.score == 2)
        #expect(parsed.scores.first { $0.dimension == "克制" }?.score == 0)
        #expect(parsed.scores.first { $0.dimension == "恭维控制" }?.score == 2)
    }

    @Test func toleratesUnknownDimensionsAndOverallCommentAlias() {
        let canonical = BenchScoringDimensions.all.map { dimension -> String in
            let score = dimension == "理解用户" ? 2 : 1
            return #"{"dimension": "\#(dimension)", "score": \#(score), "justification": "a"}"#
        }
        let text = #"{"scores": [\#((canonical + [#"{"dimension":"总分","score":9,"justification":"多余项"}"#]).joined(separator: ","))], "overall_comment": "别名总评"}"#
        guard case .success(let parsed) = BenchJudgeOutputParser.parse(text) else {
            Issue.record("应可解析"); return
        }
        #expect(parsed.scores.count == 11)
        #expect(parsed.scores.first { $0.dimension == "理解用户" }?.score == 2)
        #expect(parsed.comment == "别名总评")
    }

    @Test func failurePaths() {
        for (text, expected) in [("   ", BenchJudgeParseError.emptyResponse), ("评分如下: 10 分。", BenchJudgeParseError.noJSONObject)] {
            guard case .failure(let error) = BenchJudgeOutputParser.parse(text) else {
                Issue.record("应失败"); return
            }
            #expect(error == expected)
        }
        // 缺一个维度 → 整体失败,并指名缺失维度。
        let partial = judgeJSON(scores: [:]).replacingOccurrences(of: #"{"dimension": "克制""#, with: #"{"dimension": "多余""#)
        guard case .failure(let error) = BenchJudgeOutputParser.parse(partial) else {
            Issue.record("应失败"); return
        }
        if case .missingDimensions(let names) = error {
            #expect(names == ["克制"])
        } else {
            Issue.record("应为 missingDimensions: \(error)")
        }
        // 分数不是数字 → 解码失败。
        guard case .failure = BenchJudgeOutputParser.parse(#"{"scores":[{"dimension":"克制","score":"两分","justification":"x"}]}"#) else {
            Issue.record("应失败"); return
        }
    }
}

// MARK: - Judge engine (non-throwing failure contract)

@Suite struct BenchJudgeEngineTests {
    @Test func validJudgeResponseProducesOkResultWithTotal() async {
        let result = await BenchJudge().run(input: makeJudgeInput(), client: fakeJudgeClient(judgeJSON(scores: ["克制": 0])))
        #expect(result.status == .ok)
        #expect(result.error == nil)
        #expect(result.scores.count == 11)
        #expect(result.total == 10) // 10×1 + 0
        #expect(result.comment == "总体成立")
        #expect((result.seconds ?? -1) >= 0)
    }

    @Test func garbageResponseBecomesFailedStatusNotThrow() async {
        let result = await BenchJudge().run(input: makeJudgeInput(), client: fakeJudgeClient("这不是 JSON。"))
        #expect(result.status == .failed)
        #expect(result.error?.isEmpty == false)
        #expect(result.scores.isEmpty)
        #expect(result.total == nil)
    }

    @Test func modelFailureBecomesFailedStatusWithoutSecrets() async {
        let result = await BenchJudge().run(input: makeJudgeInput(), client: fakeJudgeClient("", terminalFailure: .network))
        #expect(result.status == .failed)
        #expect(result.error?.contains("network") == true)
        #expect(result.error?.contains("sk-") == false)
    }

    @Test func emptyStreamResponseIsFailed() async {
        let client = FakeModelClient(events: [.started, .completed(ModelResponse(id: "e", content: "", finishReason: "stop"))])
        let result = await BenchJudge().run(input: makeJudgeInput(), client: client)
        #expect(result.status == .failed)
        #expect(result.error?.contains("空") == true)
    }
}

// MARK: - Judge model factory

@Suite struct BenchJudgeModelFactoryTests {
    @Test func judgeModelDefaultsToDeepseekChatIndependentOfRunModel() throws {
        let baseEnvironment = [
            "DEEPSEEK_API_KEY": "secret-do-not-print",
            "DEEPSEEK_BASE_URL": "https://api.deepseek.com/v1",
        ]
        let made = try BenchJudgeModelFactory.make(
            dryRun: false,
            environment: baseEnvironment.merging(["DEEPSEEK_MODEL": "deepseek-reasoner"]) { $1 }
        )
        #expect(made.info.model == "deepseek-chat")
        let override = try BenchJudgeModelFactory.make(
            dryRun: false,
            environment: baseEnvironment.merging(["DEEPSEEK_JUDGE_MODEL": "deepseek-r1"]) { $1 }
        )
        #expect(override.info.model == "deepseek-r1")
    }

    @Test func dryRunJudgeUsesScriptedClientAndValidJSON() throws {
        let made = try BenchJudgeModelFactory.make(dryRun: true, environment: ["DEEPSEEK_API_KEY": "unused"])
        #expect(made.info.model == "scripted-judge-dry-run")
        guard case .success(let parsed) = BenchJudgeOutputParser.parse(BenchJudgeModelFactory.scriptedJudgeResponse()) else {
            Issue.record("脚本化 judge 输出必须能被真实解析器接受"); return
        }
        #expect(parsed.scores.count == 11)
    }
}

// MARK: - Runner integration

@Suite struct BenchRunnerJudgeIntegrationTests {
    @Test func judgeOffLeavesNoJudgeFieldsAnywhere() async throws {
        let output = temporaryOutput()
        let summary = try await BenchRunner.run(options: BenchRunOptions(
            samplesDirectory: samplesDirectory, outputURL: output, dryRun: true, limit: 2
        ))
        #expect(summary.report.judge == nil)
        #expect(summary.report.samples.allSatisfy { $0.judge == nil })
        let reportText = try String(contentsOf: summary.reportURL, encoding: .utf8)
        #expect(!reportText.contains("\"judge\""), "judge 关闭时报告不应出现 judge 字段")
        #expect(!reportText.contains("judge_status"))
        try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
    }

    @Test func dryRunWithJudgeAttachesScoresAndAggregate() async throws {
        let output = temporaryOutput()
        let summary = try await BenchRunner.run(options: BenchRunOptions(
            samplesDirectory: samplesDirectory, outputURL: output, dryRun: true, limit: 2, judgeEnabled: true
        ))
        let report = summary.report
        let judge = try #require(report.judge)
        #expect(judge.promptVersion == "reader-judge-v1")
        #expect(judge.model.model == "scripted-judge-dry-run")
        #expect(judge.aggregate.judgedCount == 2)
        #expect(judge.aggregate.failedCount == 0)
        #expect(judge.aggregate.dimensionAverages.count == 11)
        #expect(judge.aggregate.totalAverage == 11.0) // scripted all-1 scores × 11 dims
        for sample in report.samples {
            let result = try #require(sample.judge)
            #expect(result.status == .ok)
            #expect(result.scores.count == 11)
            #expect(result.total == 11)
        }

        // 报告文件可回读,judge 节完整保留。
        let data = try Data(contentsOf: summary.reportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BenchRunReport.self, from: data)
        #expect(decoded.judge?.aggregate.judgedCount == 2)
        #expect(decoded.samples.allSatisfy { $0.judge?.status == .ok })

        // CSV 模板新增 judge 参考列。
        let csv = try String(contentsOf: summary.scoringTemplateURL, encoding: .utf8)
        #expect(csv.contains("judge_status"))
        #expect(csv.contains("judge_total_0_22"))
        #expect(csv.contains("ok,11"))
        try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
    }

    @Test func judgeLimitJudgesOnlyFirstNSamples() async throws {
        let output = temporaryOutput()
        let summary = try await BenchRunner.run(options: BenchRunOptions(
            samplesDirectory: samplesDirectory, outputURL: output, dryRun: true, limit: 3,
            judgeEnabled: true, judgeLimit: 1
        ))
        let statuses = summary.report.samples.map { $0.judge?.status }
        #expect(statuses[0] == .ok)
        #expect(statuses[1] == nil)
        #expect(statuses[2] == nil)
        #expect(summary.report.judge?.aggregate.judgedCount == 1)
        try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
    }

    @Test func judgeRunReportNeverContainsEnvironmentKey() async throws {
        let secret = "sk-judge-\(UUID().uuidString)"
        let output = temporaryOutput()
        let summary = try await BenchRunner.run(options: BenchRunOptions(
            samplesDirectory: samplesDirectory, outputURL: output, dryRun: true, limit: 1,
            judgeEnabled: true, environment: ["DEEPSEEK_API_KEY": secret]
        ))
        let reportText = try String(contentsOf: summary.reportURL, encoding: .utf8)
        #expect(!reportText.contains(secret), "judge 报告绝不能包含 API key")
        #expect(!reportText.contains("DEEPSEEK_API_KEY"))
        let csvText = try String(contentsOf: summary.scoringTemplateURL, encoding: .utf8)
        #expect(!csvText.contains(secret))
        try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
    }
}

// MARK: - Backward compatibility with the Phase 5 baseline

@Suite struct ReportBackwardCompatibilityTests {
    @Test func committedPhase5BaselineStillDecodesAndHasNoJudgeData() throws {
        let data = try Data(contentsOf: committedBaselineURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(BenchRunReport.self, from: data)
        #expect(report.sampleCount == 10)
        #expect(report.samples.count == 10)
        #expect(report.judge == nil)
        #expect(report.samples.allSatisfy { $0.judge == nil })
    }
}
