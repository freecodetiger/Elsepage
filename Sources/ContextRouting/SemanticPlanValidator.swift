import Foundation

/// Validates a semantic plan against runtime state and hard business rules.
///
/// Responsibility split (planner protocol v2): this type validates and repairs
/// *semantic* decisions — source availability, empty queries, conversation hard
/// rules — and never chooses numeric execution policy. Numeric limits, retrieval
/// implementation policy and token budgets are assigned by
/// `ContextPolicyCompiler`. The validator never touches locators, so it can
/// never expand the `ReadingBoundary`; the anti-spoiler boundary stays a hard
/// data-access rule owned by retrieval code.
public struct SemanticPlanValidator: Sendable {
    public init() {}

    /// Returns the corrected plan plus human-readable descriptions of every
    /// correction (persisted in routing traces as `validationCorrections`).
    public func validate(_ proposed: SemanticContextPlan, input: ContextRoutingInput) -> (plan: SemanticContextPlan, corrections: [String]) {
        var corrections: [String] = []
        var requests: [ContextRequest] = []

        for request in proposed.requests {
            switch request {
            case .nearby:
                if input.availableSources.hasNearbyPassage {
                    requests.append(.nearby)
                } else {
                    corrections.append("dropped nearby request: no current locator")
                }
            case .book(let book):
                guard input.availableSources.hasBookIndex, input.currentReading?.hasCurrentLocator == true else {
                    corrections.append("dropped book request: book index or reading locator unavailable")
                    continue
                }
                let query = book.query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    corrections.append("dropped book request: empty query")
                    continue
                }
                requests.append(.book(BookContextRequest(
                    query: query,
                    purpose: book.purpose,
                    scope: book.scope,
                    denseQuery: Self.repairedQuery(book.denseQuery, fallback: query),
                    lexicalTerms: Self.repairedQuery(book.lexicalTerms, fallback: query)
                )))
            case .pastThought(let past):
                guard input.availableSources.hasPastThoughts else {
                    corrections.append("dropped past-thought request: no past thoughts available")
                    continue
                }
                let query = past.query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    corrections.append("dropped past-thought request: empty query")
                    continue
                }
                requests.append(.pastThought(PastThoughtContextRequest(query: query, purpose: past.purpose)))
            }
        }

        var response = proposed.response
        if input.previousAgentAskedQuestion, response.posture == .mayAskQuestion {
            // Hard conversation rule, enforced in code regardless of model output.
            response = SemanticResponsePlan(length: response.length, posture: .respondOnly)
            corrections.append("posture forced to respondOnly: previous agent turn asked a question")
        }
        if input.interactionMode == .reflection, response.length == .long {
            // Reflection replies stay restrained; depth comes from context, not length.
            response = SemanticResponsePlan(length: .medium, posture: response.posture)
            corrections.append("length capped from long to medium in reflection mode")
        }

        return (SemanticContextPlan(intent: proposed.intent, requests: requests, response: response), corrections)
    }

    /// A secondary query that is blank after trimming falls back to the primary
    /// query (the same default the wire normalizer applies) so requests never
    /// carry whitespace-only retrieval text.
    private static func repairedQuery(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
