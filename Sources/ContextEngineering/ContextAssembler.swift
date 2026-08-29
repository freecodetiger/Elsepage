import ContextRouting
import Foundation
import LibraryCore
import ReaderCore
import ReflectionCore
import RetrievalCore

/// Pre-pack provenance for one evidence-shaped context unit. Carries everything
/// `AgentResponseEvidence` needs for citation validation + persistence.
public struct AssembledEvidence: Hashable, Sendable {
    public let kind: AgentEvidenceKind
    public let sourceID: String
    public let bookID: BookID
    public let title: String?
    public let excerpt: String
    public let locator: BookLocator?

    public init(kind: AgentEvidenceKind, sourceID: String, bookID: BookID, title: String?, excerpt: String, locator: BookLocator?) {
        self.kind = kind
        self.sourceID = sourceID
        self.bookID = bookID
        self.title = title
        self.excerpt = excerpt
        self.locator = locator
    }
}

public struct EvidenceAssemblyResult: Hashable, Sendable {
    public let evidence: [AssembledEvidence]
    public let stats: ContextAssemblyStats
    /// Brain items that survived packing (source .brain/.pinnedBrain). They
    /// reach the prompt as the user's own formed thinking — never as [E]-
    /// citable `AssembledEvidence` (see phase 16 CONTEXT: brain items are not
    /// external, verifiable evidence).
    public let brainCandidates: [ContextCandidate]

    public init(evidence: [AssembledEvidence], stats: ContextAssemblyStats, brainCandidates: [ContextCandidate] = []) {
        self.evidence = evidence
        self.stats = stats
        self.brainCandidates = brainCandidates
    }
}

/// A pre-built nearby-passage candidate (text + provenance; truncation/budgeting
/// happens in the ranker, matching the plan's per-source caps).
public struct NearbyPassageCandidate: Hashable, Sendable {
    public let text: String
    public let sourceID: String
    public let locator: BookLocator

    public init(text: String, sourceID: String, locator: BookLocator) {
        self.text = text
        self.sourceID = sourceID
        self.locator = locator
    }
}

/// Turns raw evidence sources (nearby passage, book evidence, past reflection,
/// memories) into a budgeted, deduplicated, source-prioritized evidence bundle
/// for ReaderAgent. ReaderAgent no longer competes sources by hand — this layer
/// owns source competition, per-source token budgeting and dedup; ReaderAgent maps
/// the result back to `AgentResponseEvidence` (E-numbered) for the citation path.
/// Budgets come from the compiled `ContextExecutionPlan` (planner protocol v2).
public struct ContextAssembler: Sendable {
    private let ranker: ContextCandidateRanker

    public init(ranker: ContextCandidateRanker = .init()) { self.ranker = ranker }

    /// Memory isn't a field of `ContextBudget` (ADR-safe: traces keep decoding);
    /// the memory lane gets a derived slice of the past-thought budget.
    public static func derivedMemoryCharacters(from pastThoughtCharacters: Int) -> Int {
        max(0, pastThoughtCharacters / 2)
    }

    public func assemble(
        nearby: NearbyPassageCandidate?,
        bookEvidence: [BookEvidence],
        previousReflection: Reflection?,
        memories: [ReaderMemory],
        reflectionBookID: BookID,
        budget: ContextBudget,
        brainCandidates: [ContextCandidate] = []
    ) -> EvidenceAssemblyResult {
        var candidates: [ContextCandidate] = []
        var provenance: [String: AssembledEvidence] = [:]

        func register(_ candidate: ContextCandidate, _ evidence: AssembledEvidence) {
            let key = "\(candidate.source.rawValue):\(candidate.id)"
            candidates.append(candidate)
            provenance[key] = evidence
        }

        if let nearby {
            register(
                ContextCandidate(id: nearby.sourceID, source: .nearbyPassage, content: nearby.text, relevance: 1.0, tokenCost: nearby.text.count),
                AssembledEvidence(kind: .nearbyPassage, sourceID: nearby.sourceID, bookID: reflectionBookID, title: "当前阅读位置", excerpt: nearby.text, locator: nearby.locator)
            )
        }
        for item in bookEvidence {
            let title = [item.chapterTitle, item.sectionTitle].compactMap { $0 }.joined(separator: " / ")
            register(
                ContextCandidate(id: item.id.rawValue, source: .bookPassage, content: item.excerpt, relevance: item.score, tokenCost: item.excerpt.count),
                AssembledEvidence(kind: .bookPassage, sourceID: item.id.rawValue, bookID: item.bookID, title: title.isEmpty ? item.locator.href : title, excerpt: item.excerpt, locator: item.locator)
            )
        }
        if let previousReflection {
            register(
                ContextCandidate(id: previousReflection.id.description, source: .pastReflection, content: previousReflection.originalText, relevance: 1.0, tokenCost: previousReflection.originalText.count),
                AssembledEvidence(kind: .pastReflection, sourceID: previousReflection.id.description, bookID: reflectionBookID, title: "过去的想法", excerpt: previousReflection.originalText, locator: nil)
            )
        }
        for memory in memories {
            let id = memory.id.uuidString.lowercased()
            register(
                ContextCandidate(id: id, source: .memory, content: memory.claim, relevance: 1.0, tokenCost: memory.claim.count),
                AssembledEvidence(kind: .pastReflection, sourceID: id, bookID: reflectionBookID, title: "长期记忆", excerpt: memory.claim, locator: nil)
            )
        }

        // Brain candidates are already ContextCandidates (bridged by
        // BrainContextProvider); they carry no citation provenance by design.
        candidates.append(contentsOf: brainCandidates)

        let profile = ContextBudgetProfile(
            totalCharacters: budget.totalCharacters,
            perSource: [
                .nearbyPassage: budget.nearbyCharacters,
                .bookPassage: budget.bookEvidenceCharacters,
                .pastReflection: budget.pastThoughtCharacters,
                .memory: Self.derivedMemoryCharacters(from: budget.pastThoughtCharacters),
                // Compiled policy constants (phase 16): retrieved brain items get
                // a bounded slice; the pinned item is unbounded within the total
                // so it always enters the bundle.
                .brain: Self.brainCharacters,
                .pinnedBrain: budget.totalCharacters,
            ]
        )
        let packed = ranker.build(from: candidates, budget: profile)
        let brain = packed.bundle.candidates.filter { $0.source == .brain || $0.source == .pinnedBrain }
        let evidence = packed.bundle.candidates
            .filter { $0.source != .brain && $0.source != .pinnedBrain }
            .compactMap { candidate -> AssembledEvidence? in
                guard let base = provenance["\(candidate.source.rawValue):\(candidate.id)"] else { return nil }
                return AssembledEvidence(kind: base.kind, sourceID: base.sourceID, bookID: base.bookID, title: base.title, excerpt: candidate.content, locator: base.locator)
            }
        return EvidenceAssemblyResult(evidence: evidence, stats: packed.stats, brainCandidates: brain)
    }

    /// Compiled policy constant: character budget for retrieved brain items.
    static let brainCharacters = 1_200
}
