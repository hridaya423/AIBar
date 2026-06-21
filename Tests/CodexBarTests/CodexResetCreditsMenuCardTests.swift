import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexResetCreditsMenuCardTests {
    @Test
    func `reset credits render when optional usage is enabled`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let usage = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            codexResetCredits: CodexRateLimitResetCreditsSnapshot(
                credits: [
                    CodexRateLimitResetCredit(
                        id: "reset-1",
                        resetType: "codex_rate_limits",
                        status: .available,
                        grantedAt: now,
                        expiresAt: now.addingTimeInterval(86400),
                        redeemStartedAt: nil,
                        redeemedAt: nil,
                        title: "One free rate limit reset",
                        description: nil),
                ],
                availableCount: 1,
                updatedAt: now),
            updatedAt: now,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "user@example.com",
                accountOrganization: nil,
                loginMethod: "pro"))

        let model = UsageMenuCardView.Model.make(Self.input(
            metadata: metadata,
            snapshot: usage,
            showOptionalUsage: true,
            now: now))

        #expect(model.codexResetCredits?.text == "1 reset available")
        #expect(model.codexResetCredits?.detailText == "Next expires in 1d")
        #expect(model.codexResetCredits?.helpText?.contains("available, in 1d (") == true)
        #expect(model.codexResetCredits?.creditToConsume?.id == "reset-1")
    }

    @Test
    func `reset credits render when optional usage disabled`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let now = Date(timeIntervalSince1970: 1_781_726_400)
        let usage = UsageSnapshot(
            primary: RateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            codexResetCredits: CodexRateLimitResetCreditsSnapshot(
                credits: [],
                availableCount: 2,
                updatedAt: now),
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(Self.input(
            metadata: metadata,
            snapshot: usage,
            showOptionalUsage: false,
            now: now))

        // Reset credits are decoupled from the "credits + extra usage" toggle: they still render.
        #expect(model.codexResetCredits?.text == "2 resets available")
    }

    private static func input(
        metadata: ProviderMetadata,
        snapshot: UsageSnapshot,
        showOptionalUsage: Bool,
        now: Date) -> UsageMenuCardView.Model.Input
    {
        UsageMenuCardView.Model.Input(
            provider: .codex,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: showOptionalUsage,
            hidePersonalInfo: false,
            now: now)
    }
}
