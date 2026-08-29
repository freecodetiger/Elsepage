import AgentRuntime
import Foundation

// MARK: - Judge result types (BENCH-03)

public enum BenchJudgeStatus: String, Codable, Sendable, Equatable {
    /// Judge scored all 11 dimensions.
    case ok
    /// Judge call or JSON parse failed — the run itself still completes.
    case failed
    /// No response to judge (the sample's pipeline run failed).
    case skipped
}

/// One dimension's score: canonical PRD §16 name, 0–2 integer, one-line reason.
public struct BenchJudgeDimensionScore: Codable, Sendable, Equatable {
    public let dimension: String
    public let score: Int
    public let justification: String

    public init(dimension: String, score: Int, justification: String) {
        self.dimension = dimension
        self.score = score
        self.justification = justification
    }
}

/// Per-sample judge section attached to `BenchSampleRun.judge`.
public struct BenchSampleJudgeResult: Codable, Sendable {
    public let status: BenchJudgeStatus
    public let error: String?
    public let scores: [BenchJudgeDimensionScore]
    /// Sum over the 11 dimensions (0...22); present only for `.ok`.
    public let total: Int?
    public let comment: String?
    public let usage: BenchUsageSummary?
    public let seconds: Double?

    public static func ok(
        scores: [BenchJudgeDimensionScore], comment: String?,
        usage: BenchUsageSummary?, seconds: Double
    ) -> BenchSampleJudgeResult {
        BenchSampleJudgeResult(
            status: .ok, error: nil, scores: scores,
            total: scores.reduce(0) { $0 + $1.score },
            comment: comment, usage: usage, seconds: seconds
        )
    }

    public static func failed(message: String, seconds: Double?) -> BenchSampleJudgeResult {
        BenchSampleJudgeResult(status: .failed, error: message, scores: [], total: nil, comment: nil, usage: nil, seconds: seconds)
    }

    public static func skipped(reason: String) -> BenchSampleJudgeResult {
        BenchSampleJudgeResult(status: .skipped, error: reason, scores: [], total: nil, comment: nil, usage: nil, seconds: nil)
    }
}

/// Run-level aggregate over all per-sample judge results.
public struct BenchJudgeAggregate: Codable, Sendable, Equatable {
    public let judgedCount: Int
    public let failedCount: Int
    public let skippedCount: Int
    /// Canonical dimension order, average over `.ok` samples.
    public let dimensionAverages: [BenchDimensionAverage]
    /// Average per-sample total (0...22) over `.ok` samples.
    public let totalAverage: Double
}

public struct BenchDimensionAverage: Codable, Sendable, Equatable {
    public let dimension: String
    public let average: Double
    public let judgeCount: Int
}

/// Run-level judge header: which model judged, with which prompt version.
public struct BenchJudgeRunSummary: Codable, Sendable {
    public let model: BenchModelInfo
    public let promptVersion: String
    public let aggregate: BenchJudgeAggregate
}

// MARK: - Judge input

/// The material the judge sees for one sample. Decoupled from `BenchSampleRun`
/// so tests and other callers can construct it directly.
public struct BenchJudgeEvidence: Sendable, Equatable {
    public let id: String
    public let kind: String
    public let title: String?
    public let excerpt: String

    public init(id: String, kind: String, title: String?, excerpt: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.excerpt = excerpt
    }
}

public struct BenchJudgeInput: Sendable {
    public let sampleID: String
    public let category: String
    public let reflection: String
    public let expectedFeedbackNotes: [String]
    public let response: String
    public let truncated: Bool
    public let evidence: [BenchJudgeEvidence]
    /// Citation markers that appeared in the response AND passed validation.
    public let citationMarkers: [String]

    public init(
        sampleID: String, category: String, reflection: String,
        expectedFeedbackNotes: [String], response: String, truncated: Bool,
        evidence: [BenchJudgeEvidence], citationMarkers: [String]
    ) {
        self.sampleID = sampleID
        self.category = category
        self.reflection = reflection
        self.expectedFeedbackNotes = expectedFeedbackNotes
        self.response = response
        self.truncated = truncated
        self.evidence = evidence
        self.citationMarkers = citationMarkers
    }

    /// Maps a completed pipeline run plus its sample onto the judge input.
    public init(sample: BenchSample, run: BenchSampleRun) {
        self.init(
            sampleID: sample.id,
            category: sample.category,
            reflection: sample.currentReflection,
            expectedFeedbackNotes: sample.expectedFeedbackNotes,
            response: run.response ?? "",
            truncated: run.truncated,
            evidence: run.evidence.map { BenchJudgeEvidence(id: $0.id, kind: $0.kind, title: $0.title, excerpt: $0.excerpt) },
            citationMarkers: run.citations.map(\.marker)
        )
    }
}

// MARK: - Judge model factory

/// Builds the judge's model client. Same environment contract as the run client
/// (`DEEPSEEK_API_KEY` / `DEEPSEEK_BASE_URL`), with its own model selection:
/// `DEEPSEEK_JUDGE_MODEL` overrides, default `deepseek-chat` — deliberately
/// independent of `DEEPSEEK_MODEL` so the judge stays comparable across runs
/// even when the judged model changes.
public enum BenchJudgeModelFactory {
    public static let judgeModelEnvKey = "DEEPSEEK_JUDGE_MODEL"

    public static func make(
        dryRun: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> (client: any ModelClient, info: BenchModelInfo) {
        if dryRun {
            let scripted = scriptedJudgeResponse()
            let client = FakeModelClient(events: [
                .started,
                .textDelta(scripted),
                .completed(ModelResponse(id: "dry-run-judge", content: scripted, finishReason: "stop")),
            ])
            return (client, BenchModelInfo(provider: "fake", model: "scripted-judge-dry-run", baseURL: "local://dry-run"))
        }
        let override = environment[judgeModelEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (override?.isEmpty == false) ? override! : BenchModelClientFactory.defaultModel
        return try BenchModelClientFactory.make(dryRun: false, environment: environment, modelOverride: model)
    }

    /// Deterministic scripted judge output for `--dry-run --judge` (offline CI
    /// smoke of the judge plumbing; says nothing about real scoring quality).
    public static func scriptedJudgeResponse() -> String {
        let scores = BenchScoringDimensions.all.map { dimension in
            ["dimension": dimension, "score": 1, "justification": "(dry-run) 脚本化评分,不代表真实模型质量"]
        }
        let payload: [String: Any] = ["scores": scores, "comment": "(dry-run) 脚本化评审输出"]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Tolerant judge JSON parser

public enum BenchJudgeParseError: Error, Equatable, Sendable {
    case emptyResponse
    case noJSONObject
    case undecodable(String)
    case missingDimensions([String])

    public var message: String {
        switch self {
        case .emptyResponse:
            "judge 返回了空内容"
        case .noJSONObject:
            "judge 输出中找不到 JSON 对象"
        case .undecodable(let detail):
            "judge JSON 无法解析: \(detail)"
        case .missingDimensions(let names):
            "judge JSON 缺少维度评分: \(names.joined(separator: "/"))"
        }
    }
}

public enum BenchJudgeOutputParser {
    struct RawJudge: Decodable {
        struct RawScore: Decodable {
            let dimension: String
            let score: Double
            let justification: String?
        }
        let scores: [RawScore]
        let comment: String?
        let overallComment: String?

        enum CodingKeys: String, CodingKey {
            case scores, comment
            case overallComment = "overall_comment"
        }

        var resolvedComment: String? { comment ?? overallComment }
    }

    public struct ParsedJudge: Equatable {
        public let scores: [BenchJudgeDimensionScore]
        public let comment: String?

        public init(scores: [BenchJudgeDimensionScore], comment: String?) {
            self.scores = scores
            self.comment = comment
        }
    }

    /// Tolerant parse: strips markdown fences / surrounding prose, extracts the
    /// outermost JSON object, then requires every canonical dimension exactly
    /// once with a numeric score (rounded and clamped to 0...2).
    public static func parse(_ text: String) -> Result<ParsedJudge, BenchJudgeParseError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyResponse) }

        let jsonText = extractJSONObject(from: trimmed)
        guard let jsonText else { return .failure(.noJSONObject) }

        let raw: RawJudge
        do {
            raw = try JSONDecoder().decode(RawJudge.self, from: Data(jsonText.utf8))
        } catch {
            return .failure(.undecodable(Self.summarize(error)))
        }
        guard !raw.scores.isEmpty else { return .failure(.missingDimensions(BenchScoringDimensions.all)) }

        var byDimension: [String: RawJudge.RawScore] = [:]
        for entry in raw.scores {
            let name = entry.dimension.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            // First occurrence of a canonical dimension wins; extra/unknown
            // entries are tolerated and ignored.
            if BenchScoringDimensions.all.contains(name), byDimension[name] == nil {
                byDimension[name] = entry
            }
        }

        let missing = BenchScoringDimensions.all.filter { byDimension[$0] == nil }
        guard missing.isEmpty else { return .failure(.missingDimensions(missing)) }

        let scores = BenchScoringDimensions.all.map { dimension -> BenchJudgeDimensionScore in
            let entry = byDimension[dimension]!
            return BenchJudgeDimensionScore(
                dimension: dimension,
                score: Self.clamp(entry.score),
                justification: entry.justification ?? ""
            )
        }
        return .success(ParsedJudge(scores: scores, comment: raw.resolvedComment))
    }

    /// Strips markdown code fences, then isolates the substring from the first
    /// `{` to the last `}` (judges sometimes prepend a sentence despite the
    /// instruction to output JSON only).
    static func extractJSONObject(from text: String) -> String? {
        let working = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        guard let start = working.firstIndex(of: "{"), let end = working.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(working[start...end])
    }

    static func clamp(_ value: Double) -> Int {
        min(2, max(0, Int(value.rounded())))
    }

    /// Short, key-free summary of a decoding failure for the report error field.
    static func summarize(_ error: Error) -> String {
        let description = String(describing: error)
        return description.count > 200 ? String(description.prefix(200)) + "…" : description
    }
}

// MARK: - Judge engine

/// Runs one judge call for one sample and produces a tolerant, non-throwing
/// result: parse/call failures become `.failed` with an error string — never an
/// exception that could abort the run (BENCH-03 guard).
public struct BenchJudge: Sendable {
    public init() {}

    public func run(input: BenchJudgeInput, client: any ModelClient) async -> BenchSampleJudgeResult {
        let clock = ContinuousClock()
        let start = clock.now

        let request = ModelRequest(
            messages: [
                ModelMessage(role: .system, content: JudgePrompt.systemMessage),
                ModelMessage(role: .user, content: JudgePrompt.userMessage(input: input)),
            ],
            temperature: 0,
            maxOutputTokens: 1500,
            responseFormat: .jsonObject
        )

        var completed: ModelResponse?
        var deltas: [String] = []
        do {
            for try await event in client.stream(request: request) {
                switch event {
                case .started: break
                case .textDelta(let text): deltas.append(text)
                case .usage: break
                case .completed(let response): completed = response
                }
            }
        } catch is CancellationError {
            return .failed(message: "judge 调用被取消", seconds: Self.seconds(from: start, to: clock.now))
        } catch {
            // Model failure descriptions are enum cases (no secrets); unknown
            // errors are described without echoing environment values.
            let detail: String
            if let failure = error as? ModelFailure {
                detail = String(describing: failure)
            } else {
                detail = String(describing: error)
            }
            return .failed(message: "judge 模型调用失败: \(detail)", seconds: Self.seconds(from: start, to: clock.now))
        }

        // Prefer the completed response; fall back to accumulated deltas for
        // clients that stream content without a terminal completed event.
        let text = completed?.content.isEmpty == false ? completed!.content : deltas.joined()
        guard !text.isEmpty else {
            return .failed(message: BenchJudgeParseError.emptyResponse.message, seconds: Self.seconds(from: start, to: clock.now))
        }

        switch BenchJudgeOutputParser.parse(text) {
        case .success(let parsed):
            let usage = completed?.usage.map {
                BenchUsageSummary(inputTokens: $0.inputTokens, outputTokens: $0.outputTokens, totalTokens: $0.totalTokens)
            }
            return .ok(
                scores: parsed.scores, comment: parsed.comment,
                usage: usage, seconds: Self.seconds(from: start, to: clock.now)
            )
        case .failure(let parseError):
            return .failed(message: parseError.message, seconds: Self.seconds(from: start, to: clock.now))
        }
    }

    static func seconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let components = start.duration(to: end).components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}

// MARK: - Aggregation

public enum BenchJudgeAggregator {
    /// Aggregates per-sample judge results (status `.ok` only) into the
    /// run-level section: counts, per-dimension averages in canonical order,
    /// and the average total.
    public static func aggregate(runs: [BenchSampleRun]) -> BenchJudgeAggregate {
        let judged = runs.compactMap(\.judge).filter { $0.status == .ok }
        let failedCount = runs.compactMap(\.judge).filter { $0.status == .failed }.count
        let skippedCount = runs.compactMap(\.judge).filter { $0.status == .skipped }.count

        let dimensionAverages = BenchScoringDimensions.all.map { dimension -> BenchDimensionAverage in
            let values = judged.compactMap { result in
                result.scores.first { $0.dimension == dimension }?.score
            }
            let average = values.isEmpty ? 0.0 : Double(values.reduce(0, +)) / Double(values.count)
            return BenchDimensionAverage(dimension: dimension, average: average, judgeCount: values.count)
        }
        let totalAverage = judged.isEmpty
            ? 0.0
            : Double(judged.compactMap(\.total).reduce(0, +)) / Double(judged.count)

        return BenchJudgeAggregate(
            judgedCount: judged.count,
            failedCount: failedCount,
            skippedCount: skippedCount,
            dimensionAverages: dimensionAverages,
            totalAverage: totalAverage
        )
    }
}
