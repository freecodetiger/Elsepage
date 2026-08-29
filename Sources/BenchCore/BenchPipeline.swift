import AgentRuntime
import ContextEngineering
import ContextRouting
import Foundation
import LibraryCore
import ReaderAgent
import ReaderCore
import ReflectionCore
import RetrievalCore

// MARK: - Run results

public enum BenchSampleStatus: String, Codable, Sendable {
    case completed
    case failed
}

public struct BenchSampleCitation: Codable, Sendable {
    public let marker: String
    public let evidenceID: String
    public let kind: String
    public let sourceID: String
    public let title: String?
}

public struct BenchSampleEvidence: Codable, Sendable {
    public let id: String
    public let kind: String
    public let sourceID: String
    public let title: String?
    public let excerpt: String
}

public struct BenchRoutingSummary: Codable, Sendable {
    public let intent: String
    public let usedFallback: Bool
    public let fallbackReason: String?
    public let connectedPastReflectionID: String?
    public let memoryEvidenceCount: Int
    public let assembledEvidenceCount: Int
}

public struct BenchTimings: Codable, Sendable {
    public let routingSeconds: Double
    public let retrievalSeconds: Double
    public let assemblySeconds: Double
    public let replySeconds: Double
    public let totalSeconds: Double
}

public struct BenchUsageSummary: Codable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
}

/// Structured per-sample result written into the run report.
public struct BenchSampleRun: Codable, Sendable {
    public let id: String
    public let index: Int
    public let category: String
    public let bookTitle: String
    public let chapter: String?
    public let status: BenchSampleStatus
    public let error: String?
    public let response: String?
    public let truncated: Bool
    public let citations: [BenchSampleCitation]
    /// Everything the reply could cite (E-numbered, exactly what was sent).
    public let evidence: [BenchSampleEvidence]
    public let routing: BenchRoutingSummary
    public let timings: BenchTimings
    public let usage: BenchUsageSummary?
    public let promptCharacterCount: Int
    public let expectedFeedbackNotes: [String]

    public static func failed(id: String, index: Int, sample: BenchSample, message: String) -> BenchSampleRun {
        BenchSampleRun(
            id: id, index: index, category: sample.category, bookTitle: sample.book.title,
            chapter: sample.book.chapter, status: .failed, error: message, response: nil,
            truncated: false, citations: [], evidence: [],
            routing: BenchRoutingSummary(
                intent: "unknown", usedFallback: false, fallbackReason: nil,
                connectedPastReflectionID: nil, memoryEvidenceCount: 0, assembledEvidenceCount: 0
            ),
            timings: BenchTimings(routingSeconds: 0, retrievalSeconds: 0, assemblySeconds: 0, replySeconds: 0, totalSeconds: 0),
            usage: nil, promptCharacterCount: 0, expectedFeedbackNotes: sample.expectedFeedbackNotes
        )
    }
}

// MARK: - Pipeline

/// Runs one bench sample through the same pipeline the app uses:
///
///   ContextRoutingInput (built like ReaderAgent.run)
///     → LLMReaderContextRouter → ContextPlanValidator
///     → ReflectionRetriever / MemoryRetriever (over sample history)
///     → ReaderAgentContextBuilder (over sample evidence)
///     → ContextAssembler → ReaderAgentPolicy.input
///     → AgentExecutor → AgentCitationValidator
///
/// Persistence and UI are the only layers replaced (bench boundary): sample
/// fixtures stand in for the repositories. No prompt/assembly logic is
/// duplicated — every prompt-facing component is the real production type.
public struct BenchPipeline: Sendable {
    public init() {}

    public func run(
        _ sample: BenchSample,
        index: Int,
        bookID: BookID,
        client: any ModelClient
    ) async -> BenchSampleRun {
        let clock = ContinuousClock()
        let totalStart = clock.now
        do {
            let reflectionID = ReflectionID(rawValue: stableUUID("reflection:\(sample.id)"))
            let reflection = Reflection(
                id: reflectionID, bookID: bookID,
                originalText: sample.currentReflection, inputKind: .text
            )
            // Root replies only (Reflection Mode); conversation follow-ups are out
            // of scope for the v1 sample set.
            let messages: [ReflectionMessage] = []

            var currentEvidence: [ReflectionEvidence] = []
            let locator: BookLocator?
            if let benchLocator = sample.currentLocator {
                let built = try makeBookLocator(benchLocator)
                locator = built
                currentEvidence = [try ReflectionEvidence(
                    reflectionID: reflectionID, sourceType: .bookLocator, locator: built
                )]
            } else {
                locator = nil
            }

            // Past reflections: listed newest first; same-book ones also feed the
            // session context exactly like SessionContextBuilder does.
            let pastReflections = sample.userHistory.pastReflections.enumerated().map { position, past -> Reflection in
                let pastBookID: BookID = past.sameBook
                    ? bookID
                    : BookID(rawValue: stableUUID("book:\(past.bookTitle ?? "unknown")"))
                return Reflection(
                    id: ReflectionID(rawValue: stableUUID("past:\(past.id ?? sample.id):\(position)")),
                    bookID: pastBookID,
                    originalText: past.text,
                    inputKind: .text,
                    createdAt: Date(timeIntervalSinceNow: -Double(position + 1) * 86_400)
                )
            }
            let sameBookCandidates = pastReflections.filter { $0.bookID == bookID }
            let crossBookCandidates = pastReflections.filter { $0.bookID != bookID }
            let sessionContext = SessionContext(
                session: nil, sessionHighlights: [], sessionNotes: [],
                bookReflections: sameBookCandidates
            )
            let memoryRepository = BenchMemoryRepository(sample.userHistory.memoryClaims, sampleID: sample.id)

            // --- Routing (same construction as ReaderAgent.run) ---
            let matchedMemories = await MemoryRetriever().matchingMemories(
                routingText: reflection.originalText, in: memoryRepository, topN: 2
            )
            let routingInput = ContextRoutingInput(
                interactionMode: .reflection,
                currentReflection: reflection.originalText,
                recentConversation: messages.suffix(6).map {
                    RoutingMessage(role: $0.author == .user ? "user" : "agent", content: String($0.content.prefix(500)))
                },
                currentReading: .init(
                    bookID: bookID,
                    selectedText: locator?.textHighlight,
                    nearbyTextPreview: Self.nearbyPreview(locator),
                    hasCurrentLocator: locator != nil
                ),
                availableSources: .init(
                    hasNearbyPassage: locator != nil,
                    hasBookIndex: !sample.retrievalEvidence.isEmpty,
                    hasPastThoughts: !pastReflections.isEmpty,
                    hasSessionHighlight: sessionContext.hasSessionHighlight,
                    hasSessionNote: sessionContext.hasSessionNote,
                    hasBookReflections: !sameBookCandidates.isEmpty
                ),
                previousAgentAskedQuestion: Self.previousAgentAskedQuestion(in: messages)
            )

            let routingStart = clock.now
            let routingResult = await LLMReaderContextRouter().route(routingInput, using: client)
            let routingSeconds = Self.seconds(from: routingStart, to: clock.now)
            let plan = ContextPlanValidator().validate(routingResult.plan, input: routingInput)

            // --- Past-thought connection (WS3 same-book preference, as in ReaderAgent.run) ---
            var connection: ReflectionConnection?
            if let pastPlan = plan.pastThoughtRetrieval {
                if let sameBookMatch = await ReflectionRetriever().strongestMatch(for: pastPlan.query, among: sameBookCandidates) {
                    connection = ReflectionConnection(
                        reflectionID: reflectionID, sourceReflectionID: sameBookMatch.reflection.id, relevance: sameBookMatch.relevance
                    )
                } else if let crossBookMatch = await ReflectionRetriever().strongestMatch(for: pastPlan.query, among: crossBookCandidates) {
                    connection = ReflectionConnection(
                        reflectionID: reflectionID, sourceReflectionID: crossBookMatch.reflection.id, relevance: crossBookMatch.relevance
                    )
                }
            }
            let prior = connection.flatMap { connection in pastReflections.first { $0.id == connection.sourceReflectionID } }

            // --- Book evidence via the real context builder over sample fixtures ---
            let repository = BenchBookIndexRepository(sample: sample, bookID: bookID)
            let contextBuilder = ReaderAgentContextBuilder(retriever: BenchBookRetriever(sample: sample, bookID: bookID), repository: repository)
            let retrievalStart = clock.now
            var bookContext: ReaderAgentBookContext?
            if let retrieval = plan.bookRetrieval {
                bookContext = try? await contextBuilder.build(
                    bookID: bookID,
                    reflection: retrieval.query,
                    currentLocator: locator,
                    evidenceLimit: retrieval.maximumEvidenceCount,
                    characterBudget: plan.budget.bookEvidenceCharacters,
                    scope: retrieval.preferredScope == .readSoFar ? .readSoFar : .currentResource
                )
            }
            let retrievalSeconds = Self.seconds(from: retrievalStart, to: clock.now)

            // --- Assembly (real ContextAssembler, same inputs as ReaderAgent.run) ---
            var nearbyCandidate: NearbyPassageCandidate?
            if plan.nearbyPassage == .include, let locator {
                let text = [locator.textBefore, locator.textHighlight, locator.textAfter].compactMap { $0 }.joined()
                nearbyCandidate = text.isEmpty ? nil : NearbyPassageCandidate(
                    text: text, sourceID: currentEvidence.first?.id.uuidString.lowercased() ?? "", locator: locator
                )
            }
            let assemblyStart = clock.now
            let assembly = ContextAssembler().assemble(
                nearby: nearbyCandidate,
                bookEvidence: bookContext?.evidence ?? [],
                previousReflection: prior,
                memories: matchedMemories,
                reflectionBookID: bookID,
                plan: plan
            )
            let assemblySeconds = Self.seconds(from: assemblyStart, to: clock.now)

            let messageID = UUID()
            let responseEvidence = assembly.evidence.enumerated().map { offset, item in
                AgentResponseEvidence(
                    id: "E\(offset + 1)", messageID: messageID, kind: item.kind,
                    sourceID: item.sourceID, bookID: item.bookID, title: item.title,
                    excerpt: item.excerpt, locator: item.locator
                )
            }

            // --- Prompt assembly (the real ReaderAgentPolicy) ---
            let citationBoundary: ReadingBoundary?
            if let locator {
                citationBoundary = await contextBuilder.readingBoundary(for: bookID, locator: locator)
            } else {
                citationBoundary = nil
            }
            let input = ReaderAgentPolicy().input(
                for: reflection,
                messages: messages,
                currentEvidence: currentEvidence,
                previousReflection: prior,
                bookEvidence: bookContext?.evidence ?? [],
                responseEvidence: responseEvidence,
                includeNearbyPassage: plan.nearbyPassage == .include,
                responseGuidance: plan.responseGuidance,
                nearbyCharacterBudget: plan.budget.nearbyCharacters,
                pastThoughtCharacterBudget: plan.budget.pastThoughtCharacters,
                conversationCharacterBudget: plan.budget.conversationCharacters,
                sessionContext: sessionContext
            )
            let promptCharacterCount = input.messages.reduce(0) { $0 + $1.content.count }

            // --- Execution (real AgentExecutor with the reader-reply budget) ---
            let replyStart = clock.now
            var truncated = false
            var usage: TokenUsage?
            var completed: AgentResult?
            var failure: AgentFailure?
            for await event in AgentExecutor(client: client, budget: .readerReply).run(input: input) {
                switch event {
                case .textDelta: break
                case .truncated: truncated = true
                case .usageUpdated(let update): usage = update
                case .completed(let result): completed = result
                case .failed(let agentFailure): failure = agentFailure
                case .cancelled: failure = .unknown
                case .runStarted, .modelStarted: break
                }
            }
            let replySeconds = Self.seconds(from: replyStart, to: clock.now)
            guard let completed else {
                throw BenchPipelineError.modelFailure(Self.failureName(failure ?? .unknown))
            }
            // The OpenAI-compatible client carries usage on the completed response
            // (it never yields a separate .usageUpdated event).
            let replyUsage = completed.response.usage ?? usage

            // --- Citation validation (real validator, bench chunk store) ---
            let validated = await AgentCitationValidator().validate(
                content: completed.response.content,
                messageID: messageID,
                evidence: responseEvidence,
                bookIndex: repository,
                readingBoundary: citationBoundary
            )
            guard !validated.content.isEmpty else { throw BenchPipelineError.emptyResponse }

            return BenchSampleRun(
                id: sample.id,
                index: index,
                category: sample.category,
                bookTitle: sample.book.title,
                chapter: sample.book.chapter,
                status: .completed,
                error: nil,
                response: validated.content,
                truncated: truncated,
                citations: validated.citations.compactMap { citation in
                    guard let evidence = responseEvidence.first(where: { $0.id == citation.evidenceID }) else { return nil }
                    return BenchSampleCitation(
                        marker: citation.marker, evidenceID: citation.evidenceID,
                        kind: evidence.kind.rawValue, sourceID: evidence.sourceID, title: evidence.title
                    )
                },
                evidence: responseEvidence.map {
                    BenchSampleEvidence(id: $0.id, kind: $0.kind.rawValue, sourceID: $0.sourceID, title: $0.title, excerpt: $0.excerpt)
                },
                routing: BenchRoutingSummary(
                    intent: plan.intent.rawValue,
                    usedFallback: routingResult.usedFallback,
                    fallbackReason: routingResult.fallbackReason?.rawValue,
                    connectedPastReflectionID: connection?.sourceReflectionID.description,
                    memoryEvidenceCount: matchedMemories.count,
                    assembledEvidenceCount: assembly.evidence.count
                ),
                timings: BenchTimings(
                    routingSeconds: routingSeconds,
                    retrievalSeconds: retrievalSeconds,
                    assemblySeconds: assemblySeconds,
                    replySeconds: replySeconds,
                    totalSeconds: Self.seconds(from: totalStart, to: clock.now)
                ),
                usage: replyUsage.map {
                    BenchUsageSummary(inputTokens: $0.inputTokens, outputTokens: $0.outputTokens, totalTokens: $0.totalTokens)
                },
                promptCharacterCount: promptCharacterCount,
                expectedFeedbackNotes: sample.expectedFeedbackNotes
            )
        } catch {
            return .failed(
                id: sample.id, index: index, sample: sample,
                message: error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription
            )
        }
    }

    enum BenchPipelineError: Error, CustomStringConvertible {
        case modelFailure(String)
        case emptyResponse

        var description: String {
            switch self {
            case .modelFailure(let name): "模型调用失败: \(name)"
            case .emptyResponse: "模型返回了空回应"
            }
        }
    }

    /// Deterministic placeholder reply used by `--dry-run` (FakeModelClient). It
    /// exercises the full plumbing including an inline citation marker; it says
    /// nothing about real model quality.
    static let dryRunReply = "(dry-run) 占位回应：样本已走完「路由→装配→执行→引用校验」管线，你的想法已被完整接收并留档。本行不代表任何真实模型质量。[E1]"

    private static func seconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let components = start.duration(to: end).components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private static func failureName(_ failure: AgentFailure) -> String {
        switch failure {
        case .authentication: "authentication"
        case .rateLimited: "rateLimited"
        case .providerUnavailable: "providerUnavailable"
        case .network: "network"
        case .malformedProviderResponse: "malformedProviderResponse"
        case .budgetExceeded: "budgetExceeded"
        case .unknown: "unknown"
        }
    }

    private static func nearbyPreview(_ locator: BookLocator?) -> String? {
        guard let locator else { return nil }
        let text = [locator.textBefore, locator.textHighlight, locator.textAfter].compactMap { $0 }.joined()
        return text.isEmpty ? nil : String(text.prefix(600))
    }

    private static func previousAgentAskedQuestion(in messages: [ReflectionMessage]) -> Bool {
        guard let agent = messages.last(where: { $0.author == .agent }) else { return false }
        return agent.content.contains("？") || agent.content.contains("?")
    }
}
