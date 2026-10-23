import Foundation

extension OpenCodeGoLocalUsageReader {
    static func openAI(environment: [String: String]) -> OpenCodeGoLocalUsageReader {
        // Provider-specific by design: OpenCode records Codex-priced sessions under the openai provider id.
        OpenCodeGoLocalUsageReader(
            homeDirectory: environment["HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.homeDirectoryForCurrentUser,
            providerID: "openai")
    }

    func mergingCodexUsage(
        into daily: CostUsageDailyReport,
        since: Date,
        until: Date,
        calendar: Calendar,
        cacheRoot: URL?) -> CostUsageDailyReport
    {
        guard let rows = try? self.cachedRows(), !rows.isEmpty else { return daily }
        let start = calendar.startOfDay(for: since)
        let resolver = CostUsagePricing.CodexResolver(
            catalog: CostUsagePricing.modelsDevCatalog(now: until, cacheRoot: cacheRoot)
                ?? ModelsDevCatalog(providers: [:]))
        let customPricing = CostUsagePricing.customPricingOverlay()
        let entries = rows.compactMap { row -> CostUsageDailyReport.Entry? in
            let date = Date(timeIntervalSince1970: TimeInterval(row.createdMs) / 1000)
            let model = row.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard date >= start, date <= until, !model.isEmpty, let tokens = row.tokens else { return nil }
            let input = tokens.input ?? 0
            let cacheRead = tokens.cache?.read ?? 0
            let cacheWrite = tokens.cache?.write ?? 0
            let output = tokens.output ?? 0
            let reasoning = tokens.reasoning ?? 0
            let cost = CostUsagePricing.codexCostUSD(
                model: model,
                inputTokens: input + cacheRead + cacheWrite,
                cachedInputTokens: cacheRead,
                outputTokens: output + reasoning,
                cacheWriteInputTokens: cacheWrite,
                pricingDate: date,
                customPricing: customPricing,
                pricingResolver: resolver)
            return CostUsageDailyReport.Entry(
                date: CostUsageScanner.CostUsageDayRange.dayKey(from: date, calendar: calendar),
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cacheRead,
                cacheCreationTokens: cacheWrite,
                reasoningTokens: reasoning,
                totalTokens: tokens.resolvedTotal,
                requestCount: 1,
                costUSD: cost,
                modelsUsed: [model],
                modelBreakdowns: [CostUsageDailyReport.ModelBreakdown(
                    modelName: model,
                    costUSD: cost,
                    totalTokens: tokens.resolvedTotal,
                    requestCount: 1,
                    inputTokens: input,
                    outputTokens: output,
                    cacheReadTokens: cacheRead,
                    cacheCreationTokens: cacheWrite,
                    reasoningTokens: reasoning)],
                unpricedRequestCount: cost == nil ? 1 : 0,
                estimatedRequestCount: cost == nil ? 0 : 1)
        }
        guard !entries.isEmpty else { return daily }
        return CostUsageDailyReport.merged([daily, .init(data: entries, summary: nil)], calendar: calendar)
    }
}
