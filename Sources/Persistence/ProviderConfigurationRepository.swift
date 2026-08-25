import Foundation
import GRDB
import ModelProviders

public final class GRDBProviderConfigurationRepository: ProviderConfigurationRepository, @unchecked Sendable {
    private let db: AppDatabase

    public init(database: AppDatabase) { db = database }

    public func currentConfiguration() async throws -> ProviderConfiguration? {
        try await db.writer.read { db in
            try ProviderConfigurationRecord.fetchOne(db)?.domain()
        }
    }

    public func save(_ configuration: ProviderConfiguration) async throws {
        try await db.writer.write { db in
            try db.execute(sql: "DELETE FROM providerConfigurations")
            try ProviderConfigurationRecord(configuration).insert(db)
        }
    }

    public func deleteCurrentConfiguration() async throws {
        _ = try await db.writer.write { db in
            try ProviderConfigurationRecord.deleteAll(db)
        }
    }
}

private struct ProviderConfigurationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "providerConfigurations"
    let id, provider, baseURL, modelID, secretReference: String
    let streamingEnabled: Bool
    let embeddingModelID: String?

    init(_ configuration: ProviderConfiguration) {
        id = configuration.id.uuidString.lowercased()
        provider = configuration.provider.rawValue
        baseURL = configuration.baseURL.absoluteString
        modelID = configuration.modelID
        secretReference = configuration.secretReference.rawValue
        streamingEnabled = configuration.streamingEnabled
        embeddingModelID = configuration.embeddingModelID
    }

    func domain() throws -> ProviderConfiguration {
        guard let id = UUID(uuidString: id),
              let provider = ModelProviderKind(rawValue: provider),
              let baseURL = URL(string: baseURL) else {
            throw PersistenceError.corruptRecord(
                table: Self.databaseTableName, recordID: self.id, field: "configuration"
            )
        }
        return ProviderConfiguration(
            id: id,
            provider: provider,
            baseURL: baseURL,
            modelID: modelID,
            secretReference: .init(rawValue: secretReference),
            streamingEnabled: streamingEnabled,
            embeddingModelID: embeddingModelID
        )
    }
}
