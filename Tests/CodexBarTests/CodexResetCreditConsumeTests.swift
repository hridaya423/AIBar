import Foundation
import Testing
@testable import CodexBarCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CodexResetCreditConsumeTests {
    private static let listJSON = """
    {"available_count":1,"credits":[
      {"id":"RateLimitResetCredit_raw","reset_type":"codex_rate_limits","status":"available",
       "granted_at":"2026-06-12T04:03:43Z","expires_at":"2099-07-12T04:03:43Z"},
      {"id":"RateLimitResetCredit_used","reset_type":"codex_rate_limits","status":"redeemed",
       "granted_at":"2026-06-12T04:03:43Z"}
    ]}
    """

    private static func respond(_ request: URLRequest, status: Int = 200, body: String) throws
        -> (Data, URLResponse)
    {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (Data(body.utf8), response)
    }

    @Test
    func `posts raw credit id to the consume path for the target account`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            if request.httpMethod == "GET" { return try Self.respond(request, body: Self.listJSON) }
            return try Self.respond(request, body: #"{"code":"ok","windows_reset":2}"#)
        }
        let stableID = CodexRateLimitResetCredit.stableID(forProviderID: "RateLimitResetCredit_raw")

        let result = try await CodexOAuthUsageFetcher.consumeRateLimitResetCredit(
            id: stableID,
            accessToken: "test-token",
            accountId: "workspace-1",
            env: ["CODEX_HOME": "/tmp/codexbar-reset-credit-consume-test"],
            session: transport)

        #expect(result == CodexRateLimitResetCreditConsumption(code: "ok", windowsReset: 2))
        let requests = await transport.requests()
        #expect(requests.map(\.httpMethod) == ["GET", "POST"])
        let post = try #require(requests.last)
        #expect(post.url?.absoluteString == "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits/consume")
        #expect(post.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(post.value(forHTTPHeaderField: "ChatGPT-Account-ID") == "workspace-1")
        #expect(post.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(post.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["credit_id"] == "RateLimitResetCredit_raw")
        #expect(json["redeem_request_id"].flatMap(UUID.init(uuidString:)) != nil)
    }

    @Test
    func `refuses a credit that is not available on the account without posting`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            try Self.respond(request, body: Self.listJSON)
        }
        let redeemed = CodexRateLimitResetCredit.stableID(forProviderID: "RateLimitResetCredit_used")
        for id in ["codex-reset-credit-v1-unknown", redeemed] {
            await #expect(throws: CodexOAuthFetchError.self) {
                _ = try await CodexOAuthUsageFetcher.consumeRateLimitResetCredit(
                    id: id,
                    accessToken: "test-token",
                    accountId: "workspace-1",
                    env: ["CODEX_HOME": "/tmp/codexbar-reset-credit-consume-test"],
                    session: transport)
            }
        }
        #expect(await transport.requests().allSatisfy { $0.httpMethod == "GET" })
    }

    @Test
    func `maps an unauthorized consume response`() async throws {
        let transport = ProviderHTTPTransportStub { request in
            if request.httpMethod == "GET" { return try Self.respond(request, body: Self.listJSON) }
            return try Self.respond(request, status: 401, body: "{}")
        }
        do {
            _ = try await CodexOAuthUsageFetcher.consumeRateLimitResetCredit(
                id: CodexRateLimitResetCredit.stableID(forProviderID: "RateLimitResetCredit_raw"),
                accessToken: "test-token",
                accountId: nil,
                env: ["CODEX_HOME": "/tmp/codexbar-reset-credit-consume-test"],
                session: transport)
            Issue.record("expected unauthorized")
        } catch CodexOAuthFetchError.unauthorized {}
    }
}
