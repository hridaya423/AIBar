import CodexBarCore
import Foundation
import Security

enum KeychainStringStoreError: LocalizedError {
    case keychainStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .keychainStatus(status):
            "Keychain error: \(status)"
        case .invalidData:
            "Keychain returned invalid data."
        }
    }
}

struct KeychainStringStore {
    struct CachePolicy {
        let ttl: TimeInterval
    }

    private struct CachedValue {
        let value: String?
        let timestamp: Date
        let ttl: TimeInterval

        var isExpired: Bool {
            Date().timeIntervalSince(self.timestamp) > self.ttl
        }
    }

    private nonisolated(unsafe) static var cache: [String: CachedValue] = [:]
    private static let cacheLock = NSLock()

    let service: String
    let account: String
    let promptKind: KeychainPromptContext.Kind
    let cachePolicy: CachePolicy?
    let validator: @Sendable (String) -> String?

    init(
        service: String = "com.steipete.CodexBar",
        account: String,
        promptKind: KeychainPromptContext.Kind,
        cachePolicy: CachePolicy? = nil,
        validator: @escaping @Sendable (String) -> String? = { $0 })
    {
        self.service = service
        self.account = account
        self.promptKind = promptKind
        self.cachePolicy = cachePolicy
        self.validator = validator
    }

    func load() throws -> String? {
        guard !KeychainAccessGate.isDisabled else {
            return nil
        }
        if let cached = self.cachedValue() {
            return cached
        }

        var result: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        if case .interactionRequired = KeychainAccessPreflight
            .checkGenericPassword(service: self.service, account: self.account)
        {
            KeychainPromptHandler.handler?(KeychainPromptContext(
                kind: self.promptKind,
                service: self.service,
                account: self.account))
        }

        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            self.updateCache(nil)
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStringStoreError.keychainStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainStringStoreError.invalidData
        }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalValue = value.flatMap(self.validator)
        self.updateCache(finalValue)
        return finalValue
    }

    func store(_ value: String?) throws {
        guard !KeychainAccessGate.isDisabled else {
            return
        }
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let finalValue = self.validator(raw)
        else {
            try self.deleteIfPresent()
            self.clearCache()
            return
        }

        let data = finalValue.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            self.updateCache(finalValue)
            return
        }
        if updateStatus != errSecItemNotFound {
            throw KeychainStringStoreError.keychainStatus(updateStatus)
        }

        var addQuery = query
        for (key, attribute) in attributes {
            addQuery[key] = attribute
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStringStoreError.keychainStatus(addStatus)
        }

        self.updateCache(finalValue)
    }

    private func deleteIfPresent() throws {
        guard !KeychainAccessGate.isDisabled else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw KeychainStringStoreError.keychainStatus(status)
    }

    private func cacheKey() -> String {
        "\(self.service)::\(self.account)"
    }

    private func cachedValue() -> String?? {
        guard self.cachePolicy != nil else { return .none }
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        guard let cached = Self.cache[self.cacheKey()] else { return .none }
        guard !cached.isExpired else {
            Self.cache.removeValue(forKey: self.cacheKey())
            return .none
        }
        return .some(cached.value)
    }

    private func updateCache(_ value: String?) {
        guard let cachePolicy = self.cachePolicy else { return }
        Self.cacheLock.lock()
        Self.cache[self.cacheKey()] = CachedValue(value: value, timestamp: Date(), ttl: cachePolicy.ttl)
        Self.cacheLock.unlock()
    }

    private func clearCache() {
        guard self.cachePolicy != nil else { return }
        Self.cacheLock.lock()
        Self.cache.removeValue(forKey: self.cacheKey())
        Self.cacheLock.unlock()
    }
}
