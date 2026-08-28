import Foundation
import ModelProviders

/// "清除所有本地数据" (PRD §13.3 Delete All Local Data) for the persistent stores:
/// one transactional wipe of every user-data table plus the credential reset on
/// the Keychain. Book files, UserDefaults and the in-memory object graph are
/// cleared by the caller (they are not database concerns). Safe to call twice:
/// both steps are idempotent on an already-wiped store.
public struct LocalDataWipeService: Sendable {
    private let database: AppDatabase
    private let secrets: any SecretStore

    public init(database: AppDatabase, secrets: any SecretStore) {
        self.database = database
        self.secrets = secrets
    }

    public func wipeAllUserData() async throws {
        try await database.wipeAllUserData()
        try await secrets.removeAllSecrets()
    }
}
