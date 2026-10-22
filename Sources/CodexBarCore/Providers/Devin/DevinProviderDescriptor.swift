import Foundation

public enum DevinProviderDescriptor {
    public static let descriptor: ProviderDescriptor = Self.makeDescriptor()

    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .devin,
            metadata: ProviderMetadata(
                id: .devin,
                displayName: "Devin",
                sessionLabel: "Daily",
                weeklyLabel: "Weekly",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Devin usage",
                cliName: "devin",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: ProviderBrowserCookieDefaults.devinCookieImportOrder,
                dashboardURL: "https://app.devin.ai",
                subscriptionDashboardURL: "https://app.devin.ai/settings/usage",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .devin,
                iconResourceName: "ProviderIcon-devin",
                color: ProviderColor(red: 70 / 255, green: 180 / 255, blue: 130 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Devin cost summary is not supported." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [DevinWebFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "devin",
                versionDetector: nil))
    }
}

struct DevinWebFetchStrategy: ProviderFetchStrategy {
    let id: String = "devin.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        let settings = context.settings?.devin
        let source = settings?.cookieSource ?? .auto
        guard source != .off else { return false }
        if context.selectedTokenAccountID != nil {
            return DevinUsageFetcher.manualAuth(from: context.env["DEVIN_BEARER_TOKEN"]) != nil
        }
        if source == .manual {
            return DevinUsageFetcher.manualAuth(from: Self.bearerTokenOverride(context: context)) != nil
        }
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let fetcher = DevinUsageFetcher(browserDetection: context.browserDetection)
        let settings = context.settings?.devin
        let logger: ((String) -> Void)? = context.verbose
            ? { msg in CodexBarLog.logger(LogCategories.devin).verbose(msg) }
            : nil
        // A selected token account must never fall back to the configured manual token:
        // that would bill a different account while displaying this account's label.
        let bearerToken: String? = if context.selectedTokenAccountID != nil {
            context.env["DEVIN_BEARER_TOKEN"]
        } else if settings?.cookieSource == .manual {
            Self.bearerTokenOverride(context: context)
        } else {
            nil
        }
        let snapshot = try await self.fetchWithSelfHeal(
            fetcher: fetcher,
            context: context,
            bearerToken: bearerToken,
            organizationOverride: Self.organizationOverride(context: context),
            logger: logger)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "web")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private func fetchWithSelfHeal(
        fetcher: DevinUsageFetcher,
        context: ProviderFetchContext,
        bearerToken: String?,
        organizationOverride: String?,
        logger: ((String) -> Void)?) async throws -> DevinUsageSnapshot
    {
        do {
            return try await fetcher.fetch(
                bearerTokenOverride: bearerToken,
                organizationOverride: organizationOverride,
                timeout: context.webTimeout,
                logger: logger)
        } catch DevinUsageError.invalidCredentials {
            #if os(macOS)
            if let accountID = context.selectedTokenAccountID,
               let session = Self.healedSession(context: context, logger: logger)
            {
                await context.tokenAccountTokenUpdater?(.devin, accountID, session.accessToken)
                logger?("[devin] Stored token was rejected; re-imported session and retrying")
                return try await DevinUsageFetcher.fetchQuotaUsage(
                    auth: DevinUsageFetcher.RequestAuth(
                        bearerToken: session.accessToken,
                        organization: session.organization,
                        internalOrganizationID: session.internalOrganizationID,
                        sourceLabel: session.sourceLabel),
                    organizationOverride: organizationOverride,
                    timeout: context.webTimeout,
                    logger: logger)
            }
            #endif
            throw DevinUsageError.invalidCredentials
        }
    }

    #if os(macOS)
    private static func healedSession(
        context: ProviderFetchContext,
        logger: ((String) -> Void)?) -> DevinSessionImporter.SessionInfo?
    {
        let sessions = DevinSessionImporter.importSessions(
            browserDetection: context.browserDetection,
            logger: logger)
        let organization = DevinUsageFetcher.normalizedOrganization(context.settings?.devin?.organization)
        let matched = sessions.filter {
            DevinSessionIdentity.matches(session: $0, normalizedOrganization: organization)
        }
        // Without an org to disambiguate on, only trust an unambiguous single session:
        // writing another profile's token would silently re-identity the account.
        guard let first = matched.first, organization != nil || matched.count == 1 else {
            return nil
        }
        return first
    }
    #endif

    private static func bearerTokenOverride(context: ProviderFetchContext) -> String? {
        context.env["DEVIN_BEARER_TOKEN"]
            ?? context.env["DEVIN_AUTHORIZATION"]
            ?? context.settings?.devin?.manualBearerToken
    }

    private static func organizationOverride(context: ProviderFetchContext) -> String? {
        context.env["DEVIN_ORGANIZATION"]
            ?? context.env["DEVIN_ORG"]
            ?? context.settings?.devin?.organization
    }
}
