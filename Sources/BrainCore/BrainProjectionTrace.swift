import Foundation

/// One projection pass, persisted as derived observability data (ADR 0001:
/// never the observation text or reflection body — action shape, outcome and
/// corrections only).
public struct BrainProjectionTrace: Codable, Hashable, Sendable {
    public let id: UUID
    public let reflectionID: String
    public let createdAt: Date
    public let action: BrainMutationAction
    public let applied: Bool
    public let corrections: [String]
    public let candidateCount: Int
    public let decodeFailed: Bool
    public let durationSeconds: Double

    public init(
        id: UUID = UUID(), reflectionID: String, createdAt: Date = Date(),
        action: BrainMutationAction, applied: Bool, corrections: [String],
        candidateCount: Int, decodeFailed: Bool, durationSeconds: Double
    ) {
        self.id = id
        self.reflectionID = reflectionID
        self.createdAt = createdAt
        self.action = action
        self.applied = applied
        self.corrections = corrections
        self.candidateCount = candidateCount
        self.decodeFailed = decodeFailed
        self.durationSeconds = durationSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case id, reflectionID, createdAt, action, applied, corrections
        case candidateCount, decodeFailed, durationSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        reflectionID = try container.decode(String.self, forKey: .reflectionID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        action = try container.decode(BrainMutationAction.self, forKey: .action)
        applied = try container.decode(Bool.self, forKey: .applied)
        corrections = try container.decodeIfPresent([String].self, forKey: .corrections) ?? []
        candidateCount = try container.decodeIfPresent(Int.self, forKey: .candidateCount) ?? 0
        decodeFailed = try container.decodeIfPresent(Bool.self, forKey: .decodeFailed) ?? false
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(reflectionID, forKey: .reflectionID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(action, forKey: .action)
        try container.encode(applied, forKey: .applied)
        try container.encode(corrections, forKey: .corrections)
        try container.encode(candidateCount, forKey: .candidateCount)
        try container.encode(decodeFailed, forKey: .decodeFailed)
        try container.encode(durationSeconds, forKey: .durationSeconds)
    }
}

/// Aggregated projection quality (phase 19): acceptance rate, fragmentation
/// rejections and the action mix — the deterministic half of Brain quality
/// measurement (LLM-judge evaluation is deferred until real samples exist).
public struct BrainProjectionDiagnostics: Hashable, Sendable {
    public let totalRuns: Int
    public let appliedCount: Int
    /// appliedCount / totalRuns; nil when no runs.
    public let acceptanceRate: Double?
    /// Runs rejected by the fragmentation guard specifically.
    public let fragmentationRejections: Int
    public let actionDistribution: [String: Int]

    public init(traces: [BrainProjectionTrace]) {
        totalRuns = traces.count
        appliedCount = traces.filter(\.applied).count
        acceptanceRate = traces.isEmpty ? nil : Double(appliedCount) / Double(traces.count)
        fragmentationRejections = traces.filter { trace in
            !trace.applied && trace.corrections.contains { $0.contains("fragmentation guard") }
        }.count
        var distribution: [String: Int] = [:]
        for trace in traces { distribution[trace.action.rawValue, default: 0] += 1 }
        actionDistribution = distribution
    }
}

public protocol BrainProjectionTraceRepository: Sendable {
    func save(_ trace: BrainProjectionTrace) async throws
    func recentTraces(limit: Int) async throws -> [BrainProjectionTrace]
    func diagnostics() async throws -> BrainProjectionDiagnostics
}
