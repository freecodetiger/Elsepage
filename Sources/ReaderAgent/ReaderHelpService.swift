import AgentRuntime
import ContextEngineering
import ContextRouting
import Foundation
import LibraryCore
import ReaderCore
import ReflectionCore
import RetrievalCore

/// Ephemeral in-reader question answering.
///
/// This type deliberately has no Reflection, Brain, session, or trace
/// repository. It reuses only the stateless execution/retrieval/validation
/// layers shared with ReaderAgent.
public struct ReaderHelpService: Sendable {
    private let models: any ModelClientFactory
    private let contextBuilder: ReaderAgentContextBuilder?
    private let policy: ReaderHelpPolicy
    private let budget: ExecutionBudget

    public init(
        models: any ModelClientFactory,
        contextBuilder: ReaderAgentContextBuilder? = nil,
        policy: ReaderHelpPolicy = .init(),
        budget: ExecutionBudget? = nil
    ) {
        self.models = models
        self.contextBuilder = contextBuilder
        self.policy = policy
        self.budget = budget ?? ExecutionBudget(
            maxModelCalls: 1,
            maxWallTime: .seconds(45),
            maxOutputTokens: 1_200
        )
    }

    public func answer(_ request: ReaderHelpRequest) -> AsyncStream<ReaderHelpEvent> {
        AsyncStream { continuation in
            let task = Task {
                await run(request, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ request: ReaderHelpRequest,
        continuation: AsyncStream<ReaderHelpEvent>.Continuation
    ) async {
        let validated: ValidatedRequest
        switch Self.validate(request) {
        case .success(let value):
            validated = value
        case .failure(let failure):
            continuation.yield(.failed(failure))
            continuation.finish()
            return
        }

        let client: any ModelClient
        do {
            client = try await models.makeClient()
        } catch is CancellationError {
            continuation.yield(.cancelled)
            continuation.finish()
            return
        } catch {
            continuation.yield(.failed(.providerNotConfigured))
            continuation.finish()
            return
        }
        guard !Task.isCancelled else {
            continuation.yield(.cancelled)
            continuation.finish()
            return
        }

        continuation.yield(.started)

        let boundary = await contextBuilder?.readingBoundary(
            for: request.bookID,
            locator: request.anchor
        )
        let nearbyText = await contextBuilder?.nearbyText(
            for: request.bookID,
            locator: request.anchor,
            boundary: boundary
        ) ?? Self.fallbackNearbyText(request.anchor)

        let nearbyCandidate = nearbyText.map {
            NearbyPassageCandidate(
                text: $0,
                sourceID: UUID().uuidString.lowercased(),
                locator: request.anchor
            )
        }

        let indexAvailable = await contextBuilder?.isAvailable(for: request.bookID) ?? false
        let bookContext: ReaderAgentBookContext?
        if let contextBuilder,
           boundary?.progression != nil,
           indexAvailable {
            let retrievalQuery = "\(validated.selectedText)\n\(validated.question)"
            bookContext = try? await contextBuilder.build(
                bookID: request.bookID,
                reflection: retrievalQuery,
                currentLocator: request.anchor,
                boundary: boundary,
                evidenceLimit: 2,
                characterBudget: 2_000,
                scope: .readSoFar
            )
        } else {
            bookContext = nil
        }

        let assembly = ContextAssembler().assemble(
            nearby: nearbyCandidate,
            bookEvidence: bookContext?.evidence ?? [],
            previousReflection: nil,
            reflectionBookID: request.bookID,
            budget: ContextBudget(
                totalCharacters: 3_000,
                nearbyCharacters: 1_000,
                bookEvidenceCharacters: 2_000,
                pastThoughtCharacters: 0,
                conversationCharacters: 0
            )
        )
        let messageID = UUID()
        let responseEvidence = assembly.evidence.enumerated().map { offset, item in
            AgentResponseEvidence(
                id: "E\(offset + 1)",
                messageID: messageID,
                kind: item.kind,
                sourceID: item.sourceID,
                bookID: item.bookID,
                title: item.title,
                excerpt: item.excerpt,
                locator: item.locator
            )
        }

        let failClosedReason: ReaderHelpFailClosedReason?
        if contextBuilder == nil || !indexAvailable {
            failClosedReason = .indexUnavailable
        } else if boundary == nil {
            failClosedReason = .unresolvedReadingBoundary
        } else if boundary?.progression == nil {
            failClosedReason = .missingProgression
        } else {
            failClosedReason = nil
        }

        let normalizedRequest = ReaderHelpRequest(
            bookID: request.bookID,
            anchor: request.anchor,
            selectedText: validated.selectedText,
            question: validated.question,
            recentTurns: request.recentTurns
        )
        continuation.yield(.contextPrepared(ReaderHelpContextSummary(
            includedNearbyPassage: nearbyCandidate != nil,
            retrievedBookEvidenceCount: assembly.evidence.filter { $0.kind == .bookPassage }.count,
            usedActiveChunk: boundary?.activeChunkID != nil && nearbyCandidate != nil,
            failClosedReason: failClosedReason
        )))

        let input = policy.input(
            for: normalizedRequest,
            selectedText: validated.selectedText,
            nearbyText: nearbyCandidate?.text,
            responseEvidence: responseEvidence
        )
        var completedResponse: ModelResponse?
        var isTruncated = false

        for await event in AgentExecutor(client: client, budget: budget).run(input: input) {
            switch event {
            case .textDelta(let text):
                continuation.yield(.textDelta(text))
            case .truncated:
                isTruncated = true
            case .completed(let result):
                completedResponse = result.response
            case .cancelled:
                continuation.yield(.cancelled)
                continuation.finish()
                return
            case .failed(let failure):
                continuation.yield(.failed(.runtime(failure)))
                continuation.finish()
                return
            case .runStarted, .modelStarted, .usageUpdated:
                break
            }
        }

        guard let completedResponse else {
            continuation.yield(.failed(.emptyResponse))
            continuation.finish()
            return
        }

        let validatedResponse = await AgentCitationValidator().validate(
            content: completedResponse.content,
            messageID: messageID,
            evidence: responseEvidence,
            bookIndex: contextBuilder?.repository,
            readingBoundary: boundary
        )
        guard !validatedResponse.content.isEmpty else {
            continuation.yield(.failed(.emptyResponse))
            continuation.finish()
            return
        }

        let provenance = AgentResponseProvenance(
            evidence: responseEvidence,
            citations: validatedResponse.citations
        )
        continuation.yield(.citationsValidated(provenance))
        continuation.yield(.completed(ReaderHelpResponse(
            id: messageID,
            content: validatedResponse.content,
            provenance: provenance,
            isTruncated: isTruncated
        )))
        continuation.finish()
    }

    private struct ValidatedRequest {
        let selectedText: String
        let question: String
    }

    private static func validate(_ request: ReaderHelpRequest) -> Result<ValidatedRequest, ReaderHelpFailure> {
        let selected = (request.selectedText ?? request.anchor.textHighlight ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return .failure(.invalidSelection) }
        guard selected.count <= 1_000 else { return .failure(.selectionTooLong) }

        let question = request.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return .failure(.emptyQuestion) }
        guard question.count <= 500 else { return .failure(.questionTooLong) }

        return .success(ValidatedRequest(selectedText: selected, question: question))
    }

    private static func fallbackNearbyText(_ locator: BookLocator) -> String? {
        let text = [locator.textBefore, locator.textHighlight]
            .compactMap { $0 }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(1_000))
    }
}
