import Foundation

#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

#if canImport(SQLite3) || canImport(CSQLite3)

public struct OpenCodeTokenCostReader: Sendable {
    static let codexProviderID = "openai"

    private let databaseURL: URL
    private let cacheRoot: URL?

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        cacheRoot: URL? = nil)
    {
        self.databaseURL = homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("opencode.db", isDirectory: false)
        self.cacheRoot = cacheRoot
    }

    public init(databaseURL: URL, cacheRoot: URL? = nil) {
        self.databaseURL = databaseURL
        self.cacheRoot = cacheRoot
    }

    public func loadDailyReport(since: Date, until: Date, now: Date = Date()) -> CostUsageDailyReport {
        guard FileManager.default.fileExists(atPath: self.databaseURL.path) else {
            return CostUsageDailyReport(data: [], summary: nil)
        }
        guard let rows = try? self.readRows(since: since, until: until) else {
            return CostUsageDailyReport(data: [], summary: nil)
        }
        let catalog = CostUsagePricing.modelsDevCatalog(now: now, cacheRoot: self.cacheRoot)
        return Self.report(rows: rows, catalog: catalog)
    }

    public func loadOpenAIUsageEvents(since: Date, until: Date) -> [(timestamp: Date, weight: Double)] {
        guard FileManager.default.fileExists(atPath: self.databaseURL.path) else { return [] }
        guard let rows = try? self.readRows(since: since, until: until) else { return [] }
        return rows.map { row in
            let tokens = row.inputTokens + row.outputTokens + row.reasoningTokens
                + row.cacheReadTokens + row.cacheWriteTokens
            return (
                timestamp: Date(timeIntervalSince1970: TimeInterval(row.updatedMs) / 1000),
                weight: max(1, Double(tokens)))
        }
    }

    private struct SessionRow {
        let updatedMs: Int64
        let providerID: String
        let modelID: String
        let recordedCost: Double
        let inputTokens: Int
        let outputTokens: Int
        let reasoningTokens: Int
        let cacheReadTokens: Int
        let cacheWriteTokens: Int
    }

    private static let sessionSQL = """
        SELECT time_updated, model, cost,
               COALESCE(tokens_input, 0), COALESCE(tokens_output, 0), COALESCE(tokens_reasoning, 0),
               COALESCE(tokens_cache_read, 0), COALESCE(tokens_cache_write, 0)
        FROM session
        WHERE time_updated >= ? AND time_updated <= ?
    """

    private func readRows(since: Date, until: Date) throws -> [SessionRow] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(self.databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.sessionSQL, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(since.timeIntervalSince1970 * 1000))
        sqlite3_bind_int64(stmt, 2, Int64(until.timeIntervalSince1970 * 1000))

        var rows: [SessionRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let updatedMs = sqlite3_column_int64(stmt, 0)
            let modelText = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let (providerID, modelID) = Self.parseModel(modelText)
            let recordedCost = sqlite3_column_double(stmt, 2)
            let row = SessionRow(
                updatedMs: updatedMs,
                providerID: providerID,
                modelID: modelID,
                recordedCost: recordedCost.isFinite ? max(0, recordedCost) : 0,
                inputTokens: Int(sqlite3_column_int64(stmt, 3)),
                outputTokens: Int(sqlite3_column_int64(stmt, 4)),
                reasoningTokens: Int(sqlite3_column_int64(stmt, 5)),
                cacheReadTokens: Int(sqlite3_column_int64(stmt, 6)),
                cacheWriteTokens: Int(sqlite3_column_int64(stmt, 7)))
            guard updatedMs > 0, !modelID.isEmpty, providerID == Self.codexProviderID else { continue }
            rows.append(row)
        }
        return rows
    }

    static func parseModel(_ text: String) -> (providerID: String, modelID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ("", trimmed)
        }
        let modelID = (object["id"] as? String) ?? (object["modelID"] as? String) ?? ""
        let providerID = (object["providerID"] as? String) ?? (object["provider"] as? String) ?? ""
        return (providerID, modelID)
    }

    private struct DayAccumulator {
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheWriteTokens = 0
        var totalTokens = 0
        var requestCount = 0
        var costUSD = 0.0
        var perModel: [String: (cost: Double, tokens: Int, requests: Int)] = [:]
    }

    private static func report(rows: [SessionRow], catalog: ModelsDevCatalog?) -> CostUsageDailyReport {
        var days: [String: DayAccumulator] = [:]

        for row in rows {
            let day = CostUsageScanner.CostUsageDayRange
                .dayKey(from: Date(timeIntervalSince1970: TimeInterval(row.updatedMs) / 1000))
            let pricing = catalog?.pricing(providerID: row.providerID, modelID: row.modelID)?.pricing
            let cost = Self.sessionCostUSD(
                tokens: TokenCounts(
                    input: row.inputTokens,
                    output: row.outputTokens,
                    reasoning: row.reasoningTokens,
                    cacheRead: row.cacheReadTokens,
                    cacheWrite: row.cacheWriteTokens),
                recordedCost: row.recordedCost,
                pricing: pricing)
            let tokens = row.inputTokens + row.outputTokens + row.reasoningTokens
                + row.cacheReadTokens + row.cacheWriteTokens

            var acc = days[day] ?? DayAccumulator()
            acc.inputTokens += row.inputTokens
            acc.outputTokens += row.outputTokens
            acc.cacheReadTokens += row.cacheReadTokens
            acc.cacheWriteTokens += row.cacheWriteTokens
            acc.totalTokens += tokens
            acc.requestCount += 1
            acc.costUSD += cost
            let label = Self.modelLabel(providerID: row.providerID, modelID: row.modelID)
            var entry = acc.perModel[label] ?? (cost: 0, tokens: 0, requests: 0)
            entry.cost += cost
            entry.tokens += tokens
            entry.requests += 1
            acc.perModel[label] = entry
            days[day] = acc
        }

        let entries = days.keys.sorted().map { day -> CostUsageDailyReport.Entry in
            let acc = days[day]!
            let breakdowns = acc.perModel
                .sorted { $0.key < $1.key }
                .map { name, value in
                    CostUsageDailyReport.ModelBreakdown(
                        modelName: name,
                        costUSD: value.cost,
                        totalTokens: value.tokens,
                        requestCount: value.requests)
                }
            return CostUsageDailyReport.Entry(
                date: day,
                inputTokens: acc.inputTokens,
                outputTokens: acc.outputTokens,
                cacheReadTokens: acc.cacheReadTokens,
                cacheCreationTokens: acc.cacheWriteTokens,
                totalTokens: acc.totalTokens,
                requestCount: acc.requestCount,
                costUSD: acc.costUSD,
                modelsUsed: acc.perModel.keys.sorted(),
                modelBreakdowns: breakdowns)
        }

        let summary = CostUsageDailyReport.Summary(
            totalInputTokens: entries.reduce(0) { $0 + ($1.inputTokens ?? 0) },
            totalOutputTokens: entries.reduce(0) { $0 + ($1.outputTokens ?? 0) },
            cacheReadTokens: entries.reduce(0) { $0 + ($1.cacheReadTokens ?? 0) },
            cacheCreationTokens: entries.reduce(0) { $0 + ($1.cacheCreationTokens ?? 0) },
            totalTokens: entries.reduce(0) { $0 + ($1.totalTokens ?? 0) },
            totalCostUSD: entries.reduce(0.0) { $0 + ($1.costUSD ?? 0) })

        return CostUsageDailyReport(data: entries, summary: summary)
    }

    struct TokenCounts: Sendable, Equatable {
        var input = 0
        var output = 0
        var reasoning = 0
        var cacheRead = 0
        var cacheWrite = 0
    }

    static func sessionCostUSD(
        tokens: TokenCounts,
        recordedCost: Double,
        pricing: ModelsDevPricingInfo?) -> Double
    {
        guard let pricing else { return recordedCost }
        let inputRate = pricing.inputCostPerToken
        let outputRate = pricing.outputCostPerToken
        let cacheReadRate = pricing.cacheReadInputCostPerToken ?? inputRate
        let cacheWriteRate = pricing.cacheCreationInputCostPerToken ?? inputRate
        let cost = Double(tokens.input) * inputRate
            + Double(tokens.output + tokens.reasoning) * outputRate
            + Double(tokens.cacheRead) * cacheReadRate
            + Double(tokens.cacheWrite) * cacheWriteRate
        return cost > 0 ? cost : recordedCost
    }

    private static func modelLabel(providerID: String, modelID: String) -> String {
        guard !providerID.isEmpty, providerID != "openai" else { return modelID }
        return "\(modelID) (\(providerID))"
    }
}

#else

public struct OpenCodeTokenCostReader: Sendable {
    public init(
        homeDirectory _: URL = FileManager.default.homeDirectoryForCurrentUser,
        cacheRoot _: URL? = nil) {}
    public init(databaseURL _: URL, cacheRoot _: URL? = nil) {}

    public func loadDailyReport(since _: Date, until _: Date, now _: Date = Date()) -> CostUsageDailyReport {
        CostUsageDailyReport(data: [], summary: nil)
    }

    public func loadOpenAIUsageEvents(since _: Date, until _: Date) -> [(timestamp: Date, weight: Double)] {
        []
    }
}

#endif
