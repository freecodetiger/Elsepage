import AgentRuntime
import BenchCore
import ContextRouting
import Foundation
import Testing

/// Resolves repo paths from the test file location (tests run from the package root).
private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // Tests/BenchCoreTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // package root

private let samplesDirectory = packageRoot.appendingPathComponent("Fixtures/BenchSamples", isDirectory: true)

private func temporaryOutput() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("readloop-bench-tests-\(UUID().uuidString)")
        .appendingPathComponent("bench-report.json")
}

@Suite struct BenchSampleSetTests {
    @Test func committedSampleSetIsCompleteAndValid() throws {
        let samples = try BenchSampleLoader.load(from: samplesDirectory)
        #expect(samples.count >= 8, "样本集应至少 8 份,当前 \(samples.count)")

        let ids = samples.map(\.id)
        #expect(Set(ids).count == ids.count, "样本 id 必须唯一")

        // PRD §16 五要素齐全:书上下文/用户历史(字段可空但结构存在)/当前 Reflection/检索证据/目标反馈。
        for sample in samples {
            #expect(!sample.book.title.isEmpty)
            #expect(!sample.currentReflection.isEmpty)
            #expect(!sample.category.isEmpty)
            #expect(!sample.expectedFeedbackNotes.isEmpty, "样本 \(sample.id) 缺少 expectedFeedbackNotes")
        }

        // 覆盖维度:复述/观点/情绪/提问/质疑,加一个克制样本与一个记忆连接样本。
        for expectedCategory in ["复述", "观点", "情绪", "提问", "质疑", "记忆连接"] {
            #expect(samples.contains { $0.category == expectedCategory }, "样本集缺少类别: \(expectedCategory)")
        }

        // 克制样本(情绪/短句)不应携带检索证据——测的是「没有上下文时保持安静」。
        for sample in samples where sample.category == "情绪" {
            #expect(sample.retrievalEvidence.isEmpty, "情绪样本 \(sample.id) 不应固定检索证据")
        }
        // 证据引用类样本必须有阅读位置,否则路由的 bookRetrieval 会被 Validator 剔除。
        for sample in samples where !sample.retrievalEvidence.isEmpty {
            #expect(sample.currentLocator != nil, "样本 \(sample.id) 固定了检索证据但没有 currentLocator")
        }
    }

    @Test func loaderRejectsMissingRequiredFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bench-loader-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("{}".utf8).write(to: directory.appendingPathComponent("broken.json"))
        do {
            _ = try BenchSampleLoader.load(from: directory)
            Issue.record("缺少 id 应抛错")
        } catch let error as BenchSampleError {
            #expect(error.message.contains("id"))
        }

        try Data(#"{"id":"x","book":{"title":"t"}}"#.utf8).write(to: directory.appendingPathComponent("broken.json"))
        do {
            _ = try BenchSampleLoader.load(from: directory)
            Issue.record("缺少 currentReflection 应抛错")
        } catch let error as BenchSampleError {
            #expect(error.message.contains("currentReflection"))
        }

        // 同名文件补全后即可加载。
        try Data(#"{"id":"x","book":{"title":"t"},"currentReflection":"r"}"#.utf8)
            .write(to: directory.appendingPathComponent("broken.json"))
        let samples = try BenchSampleLoader.load(from: directory)
        #expect(samples.count == 1)
        #expect(samples[0].id == "x")
    }
}

@Suite struct BenchDryRunTests {
    @Test func dryRunEndToEndWritesReportAndScoringTemplate() async throws {
        let output = temporaryOutput()
        let options = BenchRunOptions(
            samplesDirectory: samplesDirectory,
            outputURL: output,
            dryRun: true,
            limit: 3,
            environment: ["DEEPSEEK_API_KEY": "should-not-be-needed"]
        )
        let summary = try await BenchRunner.run(options: options)
        let report = summary.report

        #expect(report.dryRun)
        #expect(report.model.provider == "fake")
        #expect(report.sampleCount == 3)
        #expect(report.totals.completedCount == 3)
        #expect(report.totals.failedCount == 0)
        #expect(report.promptVersion == "reader-reflection-v3")

        for sample in report.samples {
            #expect(sample.status == .completed)
            #expect(sample.error == nil)
            let response = try #require(sample.response)
            #expect(!response.isEmpty)
            // 路由用同一个客户端跑过(失败即回退),装配与引用校验都应执行。
            #expect(sample.routing.assembledEvidenceCount >= 0)
            #expect(sample.timings.totalSeconds >= 0)
            #expect(sample.promptCharacterCount > 0)
        }

        // 报告文件是合法 JSON 且可回读(报告用 ISO-8601 日期编码)。
        let data = try Data(contentsOf: summary.reportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BenchRunReport.self, from: data)
        #expect(decoded.sampleCount == 3)

        // 评分模板:11 个 PRD 维度列 + 每样本一行。
        let csv = try String(contentsOf: summary.scoringTemplateURL, encoding: .utf8)
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.count == 1 + 3)
        for dimension in BenchScoringDimensions.all {
            #expect(csv.contains(dimension), "评分表缺少维度: \(dimension)")
        }
        #expect(BenchScoringDimensions.all.count == 11)

        // 清理临时目录
        try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
    }

    @Test func dryRunReportNeverContainsEnvironmentKey() async throws {
        let secret = "sk-bench-\(UUID().uuidString)"
        let output = temporaryOutput()
        let summary = try await BenchRunner.run(options: BenchRunOptions(
            samplesDirectory: samplesDirectory,
            outputURL: output,
            dryRun: true,
            limit: 1,
            environment: ["DEEPSEEK_API_KEY": secret]
        ))
        let reportText = try String(contentsOf: summary.reportURL, encoding: .utf8)
        #expect(!reportText.contains(secret), "报告绝不能包含 API key")
        #expect(!reportText.contains("DEEPSEEK_API_KEY"))
        try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
    }

    @Test func missingAPIKeyFailsWithActionableErrorAndNoSecretEcho() async {
        do {
            _ = try BenchModelClientFactory.make(dryRun: false, environment: ["DEEPSEEK_BASE_URL": "https://api.deepseek.com/v1"])
            Issue.record("缺少 key 应抛错")
        } catch let error as BenchError {
            #expect(error.localizedDescription.contains("DEEPSEEK_API_KEY"))
            #expect(error.localizedDescription.contains("--dry-run"))
        } catch {
            Issue.record("意外的错误类型: \(error)")
        }
    }
}
