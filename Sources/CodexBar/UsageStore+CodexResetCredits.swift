import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    func handleCodexResetCreditNotifications(snapshot: UsageSnapshot) {
        guard self.settings.showOptionalCreditsAndExtraUsage,
              let resetCredits = snapshot.codexResetCredits
        else { return }
        CodexResetCreditExpiryNotifier().postExpiringCreditsIfNeeded(snapshot: resetCredits)
    }

    func codexResetCreditEnvironment(codexActiveSourceOverride: CodexActiveSource? = nil) -> [String: String] {
        self.makeFetchContext(
            provider: .codex,
            override: nil,
            codexActiveSourceOverride: codexActiveSourceOverride).env
    }

    func fetchCodexResetCreditsIfAvailable(env: [String: String]) async -> CodexRateLimitResetCreditsSnapshot? {
        // Reset credits are surfaced independently of the "credits + extra usage" toggle: banked
        // resets expire and are worth seeing even when other optional sections are hidden.
        do {
            var credentials = try CodexOAuthCredentialsStore.loadOAuthTokens(env: env)
            if credentials.needsRefresh, !credentials.refreshToken.isEmpty {
                credentials = try await CodexTokenRefresher.refresh(credentials)
                try CodexOAuthCredentialsStore.save(credentials, env: env)
            }
            return try await CodexOAuthUsageFetcher.fetchRateLimitResetCredits(
                accessToken: credentials.accessToken,
                accountId: credentials.accountId,
                env: env)
        } catch {
            return nil
        }
    }

    func consumeCodexResetCredit(_ credit: CodexRateLimitResetCredit) async throws
    -> CodexRateLimitResetCreditConsumption {
        let env = self.codexResetCreditEnvironment()
        var credentials = try CodexOAuthCredentialsStore.loadOAuthTokens(env: env)
        if credentials.needsRefresh, !credentials.refreshToken.isEmpty {
            credentials = try await CodexTokenRefresher.refresh(credentials)
            try CodexOAuthCredentialsStore.save(credentials, env: env)
        }
        let result = try await CodexOAuthUsageFetcher.consumeRateLimitResetCredit(
            id: credit.id,
            accessToken: credentials.accessToken,
            accountId: credentials.accountId,
            env: env)
        await self.refreshProvider(.codex)
        return result
    }
}
