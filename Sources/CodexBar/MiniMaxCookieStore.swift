import CodexBarCore

protocol MiniMaxCookieStoring: Sendable {
    func loadCookieHeader() throws -> String?
    func storeCookieHeader(_ header: String?) throws
}

struct KeychainMiniMaxCookieStore: MiniMaxCookieStoring {
    private let store = KeychainStringStore(
        account: "minimax-cookie",
        promptKind: .minimaxCookie,
        validator: { value in
            guard MiniMaxCookieHeader.normalized(from: value) != nil else { return nil }
            return value
        })

    func loadCookieHeader() throws -> String? {
        try self.store.load()
    }

    func storeCookieHeader(_ header: String?) throws {
        try self.store.store(header)
    }
}
