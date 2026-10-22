import Foundation
#if canImport(WebKit)
import WebKit

extension OpenAIDashboardFetcher {
    nonisolated static let dashboardAcceptLanguage = "en-US,en;q=0.9"
    private nonisolated static let dashboardUsageAPIURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    struct DashboardAPIData {
        let primaryLimit: RateWindow?
        let secondaryLimit: RateWindow?
        let extraRateWindows: [NamedRateWindow]
        let creditsRemaining: Double?
        let accountPlan: String?

        var hasUsageData: Bool {
            self.primaryLimit != nil || self.secondaryLimit != nil || self.creditsRemaining != nil
        }
    }

    /// Build a dashboard snapshot from API data, preserving history and page-only fields from a
    /// previous scrape of the same account.
    nonisolated static func snapshotByMergingAPI(
        apiData: DashboardAPIData,
        verifiedEmail: String,
        previous: OpenAIDashboardSnapshot?,
        updatedAt: Date = Date()) -> OpenAIDashboardSnapshot
    {
        let email = verifiedEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let reusable: OpenAIDashboardSnapshot? = switch previous?.signedInEmail {
        case let prevEmail?:
            prevEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(email) == .orderedSame ? previous : nil
        case nil:
            previous
        }
        return OpenAIDashboardSnapshot(
            signedInEmail: email.isEmpty ? nil : email,
            codeReviewRemainingPercent: reusable?.codeReviewRemainingPercent,
            codeReviewLimit: reusable?.codeReviewLimit,
            creditEvents: reusable?.creditEvents ?? [],
            dailyBreakdown: reusable?.dailyBreakdown ?? [],
            usageBreakdown: reusable?.usageBreakdown ?? [],
            creditsPurchaseURL: reusable?.creditsPurchaseURL,
            primaryLimit: apiData.primaryLimit ?? reusable?.primaryLimit,
            secondaryLimit: apiData.secondaryLimit ?? reusable?.secondaryLimit,
            extraRateWindows: apiData.extraRateWindows.isEmpty ? reusable?.extraRateWindows : apiData.extraRateWindows,
            creditsRemaining: apiData.creditsRemaining ?? reusable?.creditsRemaining,
            accountPlan: reusable?.accountPlan ?? apiData.accountPlan,
            updatedAt: updatedAt)
    }

    /// Resolve the dashboard snapshot without touching a WebView. Falls back to the previous
    /// snapshot, and throws when nothing usable exists.
    static func snapshotSkippingPageScrape(
        apiData: DashboardAPIData?,
        verifiedSignedInEmail: String?,
        previous: OpenAIDashboardSnapshot?,
        logger: ((String) -> Void)?) throws -> OpenAIDashboardSnapshot
    {
        if let apiData, apiData.hasUsageData, let verifiedSignedInEmail {
            logger?("usage api supplied verified dashboard data; skipping WebView")
            return self.snapshotByMergingAPI(
                apiData: apiData,
                verifiedEmail: verifiedSignedInEmail,
                previous: previous)
        }
        if let previous {
            logger?("page scrape disabled; returning previous dashboard snapshot")
            return previous
        }
        throw FetchError.noDashboardData(body: "OpenAI dashboard APIs unavailable and page scrape disabled.")
    }

    nonisolated static func dashboardAPIData(from response: CodexUsageResponse) -> DashboardAPIData {
        DashboardAPIData(
            primaryLimit: self.rateWindow(from: response.rateLimit?.primaryWindow),
            secondaryLimit: self.rateWindow(from: response.rateLimit?.secondaryWindow),
            extraRateWindows: CodexAdditionalRateLimitMapper.extraRateWindows(
                from: response.additionalRateLimits),
            creditsRemaining: response.credits?.balance,
            accountPlan: response.planType?.rawValue)
    }

    static func fetchDashboardAPIPreflight(
        websiteDataStore: WKWebsiteDataStore,
        deadline: Date,
        logger: @escaping (String) -> Void)
        async throws -> (apiData: DashboardAPIData?, verifiedSignedInEmail: String?)
    {
        let cookieHeader = try await self.chatGPTCookieHeader(in: websiteDataStore, deadline: deadline)
        let apiData = await self.fetchDashboardUsageAPI(
            cookieHeader: cookieHeader,
            deadline: deadline,
            logger: logger)
        let verifiedEmail: String? = if apiData?.hasUsageData == true {
            await self.fetchSignedInEmailFromAPI(
                cookieHeader: cookieHeader,
                deadline: deadline,
                logger: logger)
        } else {
            nil
        }

        if apiData?.hasUsageData == true, verifiedEmail != nil {
            logger("usage api supplied verified dashboard data; continuing WebView scrape")
        }
        return (apiData, verifiedEmail)
    }

    static func fetchDashboardUsageAPI(
        websiteDataStore: WKWebsiteDataStore,
        logger: @escaping (String) -> Void) async -> DashboardAPIData?
    {
        guard let cookieHeader = try? await self.chatGPTCookieHeader(in: websiteDataStore, deadline: nil) else {
            return nil
        }
        return await self.fetchDashboardUsageAPI(cookieHeader: cookieHeader, deadline: nil, logger: logger)
    }

    static func fetchDashboardUsageAPI(
        cookieHeader: String,
        deadline: Date?,
        logger: @escaping (String) -> Void) async -> DashboardAPIData?
    {
        guard !cookieHeader.isEmpty else { return nil }
        let remaining = deadline.map { self.remainingTimeout(until: $0) } ?? 4
        guard remaining > 0 else { return nil }

        do {
            let (data, response) = try await ProviderHTTPClient.shared.data(
                for: self.dashboardUsageAPIRequest(cookieHeader: cookieHeader, timeout: min(4, remaining)))
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger("usage api status=\(status)")
            guard status >= 200, status < 300 else { return nil }
            let decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            let result = self.dashboardAPIData(from: decoded)
            if result.hasUsageData {
                logger("usage api supplied language-independent rate/credit data")
            }
            return result
        } catch {
            logger("usage api unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    static func fetchSignedInEmailFromAPI(
        cookieHeader: String,
        deadline: Date?,
        logger: @escaping (String) -> Void) async -> String?
    {
        guard !cookieHeader.isEmpty else { return nil }

        let endpoints = [
            URL(string: "https://chatgpt.com/backend-api/me"),
            URL(string: "https://chatgpt.com/api/auth/session"),
        ].compactMap(\.self)

        for url in endpoints {
            let remaining = deadline.map { self.remainingTimeout(until: $0) } ?? 2
            guard remaining > 0 else { return nil }
            do {
                let (data, response) = try await ProviderHTTPClient.shared.data(
                    for: self.dashboardIdentityAPIRequest(
                        url: url,
                        cookieHeader: cookieHeader,
                        timeout: min(2, remaining)))
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger("identity api \(url.path) status=\(status)")
                guard status >= 200, status < 300 else { continue }
                if let email = self.findFirstEmail(inJSONData: data) {
                    return email.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                logger("identity api \(url.path) unavailable: \(error.localizedDescription)")
            }
        }

        return nil
    }

    static func chatGPTCookieHeader(in store: WKWebsiteDataStore, deadline: Date?) async throws -> String {
        let cookies = try await OpenAIDashboardBrowserCookieImporter.runBoundedValueCallback(
            deadline: deadline)
        { completion in
            store.httpCookieStore.getAllCookies(completion)
        }

        return cookies
            .filter { $0.domain.lowercased().contains("chatgpt.com") }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    nonisolated static func findFirstEmail(inJSONData data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        var queue: [Any] = [json]
        var seen = 0
        while !queue.isEmpty, seen < 2000 {
            let current = queue.removeFirst()
            seen += 1
            if let string = current as? String, string.contains("@") {
                return string
            }
            if let dictionary = current as? [String: Any] {
                for (key, value) in dictionary {
                    if key.lowercased() == "email",
                       let string = value as? String,
                       string.contains("@")
                    {
                        return string
                    }
                    queue.append(value)
                }
            } else if let array = current as? [Any] {
                queue.append(contentsOf: array)
            }
        }
        return nil
    }

    nonisolated static func rateWindow(from window: CodexUsageResponse.WindowSnapshot?) -> RateWindow? {
        guard let window else { return nil }
        let resetDate = Date(timeIntervalSince1970: TimeInterval(window.resetAt))
        return RateWindow(
            usedPercent: Double(window.usedPercent),
            windowMinutes: window.limitWindowSeconds / 60,
            resetsAt: resetDate,
            resetDescription: UsageFormatter.resetDescription(from: resetDate))
    }

    nonisolated static func dashboardUsageAPIRequest(
        cookieHeader: String,
        timeout: TimeInterval = 4) -> URLRequest
    {
        var request = URLRequest(url: Self.dashboardUsageAPIURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.dashboardAcceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue("CodexBar", forHTTPHeaderField: "User-Agent")
        return request
    }

    nonisolated static func dashboardIdentityAPIRequest(
        url: URL,
        cookieHeader: String,
        timeout: TimeInterval = 2) -> URLRequest
    {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.dashboardAcceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue("CodexBar", forHTTPHeaderField: "User-Agent")
        return request
    }
}
#endif
