import Foundation
import LibraryCore

public enum ReaderInteractionMode: String, Codable, Sendable { case reflection, conversation }
public enum ReflectionIntent: String, Codable, Sendable {
    case emotionalRecord, passageObservation, authorDisagreement, conceptualQuestion
    case personalConnection, conversationContinuation, unclear
}
public enum NearbyPassagePlan: String, Codable, Sendable { case include, omit }
public enum RetrievalPurpose: String, Codable, Sendable {
    case clarifyCurrentPassage, findEarlierSupport, findEarlierContrast, traceConcept, verifyBookFact
}
public enum PreferredBookScope: String, Codable, Sendable { case currentSection, currentChapter, readSoFar }
public enum PastThoughtPurpose: String, Codable, Sendable { case findContinuation, findChange, findContradiction, findRecurringQuestion }
public enum ResponseLength: String, Codable, Sendable { case short, medium, long }

public struct RoutingMessage: Hashable, Codable, Sendable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct CurrentReadingSummary: Hashable, Codable, Sendable {
    public let bookID: BookID
    public let chapterTitle: String?
    public let selectedText: String?
    public let nearbyTextPreview: String?
    public let hasCurrentLocator: Bool
    public init(bookID: BookID, chapterTitle: String? = nil, selectedText: String? = nil,
                nearbyTextPreview: String? = nil, hasCurrentLocator: Bool) {
        self.bookID = bookID; self.chapterTitle = chapterTitle; self.selectedText = selectedText
        self.nearbyTextPreview = nearbyTextPreview; self.hasCurrentLocator = hasCurrentLocator
    }
}

public struct AvailableContextSources: Hashable, Codable, Sendable {
    public let hasNearbyPassage: Bool
    public let hasBookIndex: Bool
    public let hasPastThoughts: Bool
    public init(hasNearbyPassage: Bool, hasBookIndex: Bool, hasPastThoughts: Bool) {
        self.hasNearbyPassage = hasNearbyPassage; self.hasBookIndex = hasBookIndex; self.hasPastThoughts = hasPastThoughts
    }
}

public struct ContextRoutingInput: Hashable, Codable, Sendable {
    public let interactionMode: ReaderInteractionMode
    public let currentReflection: String
    public let recentConversation: [RoutingMessage]
    public let currentReading: CurrentReadingSummary?
    public let availableSources: AvailableContextSources
    public let previousAgentAskedQuestion: Bool
    public init(interactionMode: ReaderInteractionMode, currentReflection: String,
                recentConversation: [RoutingMessage], currentReading: CurrentReadingSummary?,
                availableSources: AvailableContextSources, previousAgentAskedQuestion: Bool) {
        self.interactionMode = interactionMode; self.currentReflection = currentReflection
        self.recentConversation = recentConversation; self.currentReading = currentReading
        self.availableSources = availableSources; self.previousAgentAskedQuestion = previousAgentAskedQuestion
    }
}

public struct BookRetrievalPlan: Hashable, Codable, Sendable {
    public let query: String
    public let purpose: RetrievalPurpose
    public let preferredScope: PreferredBookScope
    public let maximumEvidenceCount: Int
    public init(query: String, purpose: RetrievalPurpose, preferredScope: PreferredBookScope, maximumEvidenceCount: Int) {
        self.query = query; self.purpose = purpose; self.preferredScope = preferredScope; self.maximumEvidenceCount = maximumEvidenceCount
    }
}

public struct PastThoughtRetrievalPlan: Hashable, Codable, Sendable {
    public let query: String
    public let purpose: PastThoughtPurpose
    public let maximumEvidenceCount: Int
    public init(query: String, purpose: PastThoughtPurpose, maximumEvidenceCount: Int) {
        self.query = query; self.purpose = purpose; self.maximumEvidenceCount = maximumEvidenceCount
    }
}

public struct ResponseGuidance: Hashable, Codable, Sendable {
    public let targetLength: ResponseLength
    public let allowQuestion: Bool
    public let shouldNaturallyEnd: Bool
    public init(targetLength: ResponseLength, allowQuestion: Bool, shouldNaturallyEnd: Bool) {
        self.targetLength = targetLength; self.allowQuestion = allowQuestion; self.shouldNaturallyEnd = shouldNaturallyEnd
    }
}

public struct ReaderContextPlan: Hashable, Codable, Sendable {
    public let intent: ReflectionIntent
    public let nearbyPassage: NearbyPassagePlan
    public let bookRetrieval: BookRetrievalPlan?
    public let pastThoughtRetrieval: PastThoughtRetrievalPlan?
    public let responseGuidance: ResponseGuidance
    public let rationale: String?
    public init(intent: ReflectionIntent, nearbyPassage: NearbyPassagePlan,
                bookRetrieval: BookRetrievalPlan?, pastThoughtRetrieval: PastThoughtRetrievalPlan?,
                responseGuidance: ResponseGuidance, rationale: String? = nil) {
        self.intent = intent; self.nearbyPassage = nearbyPassage; self.bookRetrieval = bookRetrieval
        self.pastThoughtRetrieval = pastThoughtRetrieval; self.responseGuidance = responseGuidance; self.rationale = rationale
    }
}

public struct ContextBudget: Hashable, Sendable {
    public let totalCharacters: Int
    public let nearbyCharacters: Int
    public let bookEvidenceCharacters: Int
    public let pastThoughtCharacters: Int
    public let conversationCharacters: Int
}

public struct ValidatedContextPlan: Hashable, Sendable {
    public let intent: ReflectionIntent
    public let nearbyPassage: NearbyPassagePlan
    public let bookRetrieval: BookRetrievalPlan?
    public let pastThoughtRetrieval: PastThoughtRetrievalPlan?
    public let responseGuidance: ResponseGuidance
    public let budget: ContextBudget
}

public enum RoutingFallbackReason: String, Hashable, Sendable { case invalidStructuredOutput, modelFailure }
public struct ContextRoutingResult: Hashable, Sendable {
    public let plan: ReaderContextPlan
    public let usedFallback: Bool
    public let fallbackReason: RoutingFallbackReason?
}
