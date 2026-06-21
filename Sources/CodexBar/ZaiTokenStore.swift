import CodexBarCore

protocol ZaiTokenStoring: Sendable {
    func loadToken() throws -> String?
    func storeToken(_ token: String?) throws
}

struct KeychainZaiTokenStore: ZaiTokenStoring {
    private let store = KeychainStringStore(
        account: "zai-api-token",
        promptKind: .zaiToken,
        cachePolicy: .init(ttl: 1800))

    func loadToken() throws -> String? {
        try self.store.load()
    }

    func storeToken(_ token: String?) throws {
        try self.store.store(token)
    }
}
