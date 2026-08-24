import Foundation

public protocol SecretStore: Sendable {
    func secret(for reference: SecretReference) async throws -> String?
    func save(_ secret: String, for reference: SecretReference) async throws
    func removeSecret(for reference: SecretReference) async throws
}

public actor InMemorySecretStore: SecretStore {
    private var values: [SecretReference: String] = [:]

    public init() {}
    public func secret(for reference: SecretReference) -> String? { values[reference] }
    public func save(_ secret: String, for reference: SecretReference) { values[reference] = secret }
    public func removeSecret(for reference: SecretReference) { values[reference] = nil }
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
}
#endif
