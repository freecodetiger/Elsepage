import Foundation

public protocol SecretStore: Sendable {
    func secret(for reference: SecretReference) async throws -> String?
    func save(_ secret: String, for reference: SecretReference) async throws
    func removeSecret(for reference: SecretReference) async throws
    /// Deletes every credential held for this app ("清除所有本地数据", PRD §13.3).
    /// Must not touch anything outside this app's own keychain items.
    func removeAllSecrets() async throws
}

public actor InMemorySecretStore: SecretStore {
    private var values: [SecretReference: String] = [:]

    public init() {}
    public func secret(for reference: SecretReference) -> String? { values[reference] }
    public func save(_ secret: String, for reference: SecretReference) { values[reference] = secret }
    public func removeSecret(for reference: SecretReference) { values[reference] = nil }
    public func removeAllSecrets() { values.removeAll() }
}

#if canImport(Security)
import Security

public enum KeychainSecretStoreError: Error, Equatable, Sendable { case operationFailed(OSStatus) }

/// The only production secret persistence implementation. It never writes a key
/// to UserDefaults, SQLite, or logs.
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.readloop.reader.model-provider") { self.service = service }

    public func secret(for reference: SecretReference) async throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainSecretStoreError.operationFailed(status)
        }
        return value
    }

    public func save(_ secret: String, for reference: SecretReference) async throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(secret.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.rawValue,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw KeychainSecretStoreError.operationFailed(insertStatus) }
        } else if status != errSecSuccess {
            throw KeychainSecretStoreError.operationFailed(status)
        }
    }

    public func removeSecret(for reference: SecretReference) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.operationFailed(status)
        }
    }

    /// Credential reset: removes every generic password under this store's
    /// service (chat, embedding and reranker keys share it). The service string
    /// scopes the delete to this app's own items.
    public func removeAllSecrets() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.operationFailed(status)
        }
    }
}
#endif
