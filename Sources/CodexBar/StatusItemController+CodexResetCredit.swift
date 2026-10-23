import AppKit
import CodexBarCore

extension StatusItemController {
    func confirmAndConsumeCodexResetCredit(id creditID: String) {
        let confirm = NSAlert()
        confirm.messageText = L("Use a limit reset credit?")
        confirm.informativeText = L("This spends one credit and resets your Codex limits now. It cannot be undone.")
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: L("Cancel"))
        confirm.addButton(withTitle: L("Use reset"))
        guard confirm.runModal() == .alertSecondButtonReturn else { return }
        // Provider-specific by design: limit reset credits are a Codex account feature.
        let context = self.store.makeFetchContext(provider: .codex, override: nil)
        let workspaceID = context.codexWorkspaceID
        let environment = context.env
        Task { @MainActor in
            do {
                _ = try await Task.detached {
                    let credentials = try CodexOAuthCredentialsStore.loadOAuthTokens(env: environment)
                    guard !credentials.needsRefresh else { throw CodexOAuthFetchError.unauthorized }
                    return try await CodexOAuthUsageFetcher.consumeRateLimitResetCredit(
                        id: creditID,
                        accessToken: credentials.accessToken,
                        accountId: workspaceID ?? credentials.accountId,
                        env: environment)
                }.value
                // Provider-specific by design: a consumed credit changes the Codex quota windows.
                await self.store.refreshProvider(.codex)
            } catch {
                self.presentLoginAlert(
                    title: L("Could not use reset credit"),
                    message: error.localizedDescription)
            }
        }
    }
}
