import Foundation

/// What the projection LLM may propose (docs/brain.md §8). A closed tagged
/// union: the LLM picks one action per observation, never writes directly.
public enum BrainMutationAction: String, Hashable, Codable, Sendable, CaseIterable {
    case attachEvidence, createThought, updateThought, createQuestion, updateQuestion, proposeMemory, noChange
}

public enum BrainMutationProposal: Hashable, Sendable {
    case attachEvidence(itemID: BrainItemID, relation: EvidenceRelation)
    case createThought(title: String, statement: String, stage: ThoughtStage)
    case updateThought(itemID: BrainItemID, statement: String, stage: ThoughtStage?)
    case createQuestion(question: String)
    case updateQuestion(itemID: BrainItemID, question: String, state: QuestionState?)
    case proposeMemory(content: String)
    case noChange

    public var action: BrainMutationAction {
        switch self {
        case .attachEvidence: .attachEvidence
        case .createThought: .createThought
        case .updateThought: .updateThought
        case .createQuestion: .createQuestion
        case .updateQuestion: .updateQuestion
        case .proposeMemory: .proposeMemory
        case .noChange: .noChange
        }
    }
}

/// Result of one projection pass: what the model proposed, whether the
/// validator approved and executed it, and every correction applied.
public struct BrainMutationOutcome: Hashable, Sendable {
    public let proposal: BrainMutationProposal
    public let applied: Bool
    public let corrections: [String]

    public init(proposal: BrainMutationProposal, applied: Bool, corrections: [String]) {
        self.proposal = proposal
        self.applied = applied
        self.corrections = corrections
    }
}
