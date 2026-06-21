import CodexBarCore

protocol KimiK2TokenStoring: Sendable {
    func loadToken() throws -> String?
    func storeToken(_ token: String?) throws
}

struct KeychainKimiK2TokenStore: KimiK2TokenStoring {
    private let store = KeychainStringStore(account: "kimi-k2-api-token", promptKind: .kimiK2Token)

    func loadToken() throws -> String? {
        try self.store.load()
    }

    func storeToken(_ token: String?) throws {
        try self.store.store(token)
    }
}
