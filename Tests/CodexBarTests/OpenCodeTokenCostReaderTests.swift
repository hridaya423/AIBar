#if os(macOS)

import Foundation
import SQLite3
import Testing
@testable import CodexBarCore

struct OpenCodeTokenCostReaderTests {

    @Test func parsesModelJSON() {
        let parsed = OpenCodeTokenCostReader.parseModel(#"{"id":"gpt-5.5","providerID":"openai","variant":"low"}"#)
        #expect(parsed.providerID == "openai")
        #expect(parsed.modelID == "gpt-5.5")
    }

    @Test func parsesBareModelString() {
        let parsed = OpenCodeTokenCostReader.parseModel("gpt-5.5")
        #expect(parsed.providerID.isEmpty)
        #expect(parsed.modelID == "gpt-5.5")
    }

    @Test func tokenPricesWhenPricingKnown() {
        let pricing = ModelsDevPricingInfo(
            providerID: "openai",
            providerName: "OpenAI",
            modelID: "gpt-5.5",
            modelName: "GPT-5.5",
            inputCostPerToken: 0.000_001,
            outputCostPerToken: 0.000_010,
            cacheReadInputCostPerToken: 0.000_000_5,
            cacheCreationInputCostPerToken: nil,
            contextWindow: nil,
            thresholdTokens: nil,
            inputCostPerTokenAboveThreshold: nil,
            outputCostPerTokenAboveThreshold: nil,
            cacheReadInputCostPerTokenAboveThreshold: nil,
            cacheCreationInputCostPerTokenAboveThreshold: nil)

        let cost = OpenCodeTokenCostReader.sessionCostUSD(
            tokens: .init(input: 1_000_000, output: 100_000, cacheRead: 200_000),
            recordedCost: 0,
            pricing: pricing)
        #expect(abs(cost - 2.1) < 0.000_001)
    }

    @Test func fallsBackToRecordedCostWhenUnpriceable() {
        let cost = OpenCodeTokenCostReader.sessionCostUSD(
            tokens: .init(input: 5000, output: 5000),
            recordedCost: 4.2,
            pricing: nil)
        #expect(cost == 4.2)
    }


    @Test func aggregatesRecordedCostByDayForUnpriceableModels() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCodeTokenCostReaderTests-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }
        try Self.createSessionTable(at: dbURL)

        let day1 = Date(timeIntervalSince1970: 1_770_000_000) // distinct day
        let day2 = day1.addingTimeInterval(2 * 86400)
        try Self.insertSession(
            dbURL: dbURL,
            updatedMs: self.ms(day1),
            model: #"{"id":"mystery-model","providerID":"openai"}"#,
            cost: 1.5,
            tokens: (input: 100, output: 50))
        try Self.insertSession(
            dbURL: dbURL,
            updatedMs: self.ms(day1),
            model: #"{"id":"mystery-model","providerID":"openai"}"#,
            cost: 2.5,
            tokens: (input: 200, output: 80))
        try Self.insertSession(
            dbURL: dbURL,
            updatedMs: self.ms(day2),
            model: #"{"id":"mystery-model","providerID":"openai"}"#,
            cost: 4.0,
            tokens: (input: 10, output: 5))

        let emptyCacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCodeTokenCostReaderTests-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyCacheRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyCacheRoot) }

        let reader = OpenCodeTokenCostReader(databaseURL: dbURL, cacheRoot: emptyCacheRoot)
        let report = reader.loadDailyReport(
            since: day1.addingTimeInterval(-86400),
            until: day2.addingTimeInterval(86400))

        #expect(report.data.count == 2)
        #expect(report.summary?.totalCostUSD == 8.0)

        let day1Key = CostUsageScanner.CostUsageDayRange.dayKey(from: day1)
        let day1Entry = try #require(report.data.first { $0.date == day1Key })
        #expect(day1Entry.costUSD == 4.0)
        #expect(day1Entry.requestCount == 2)
        #expect(day1Entry.totalTokens == 430) // (100+50)+(200+80) input+output, no cache
    }

    @Test func excludesNonOpenAIProviders() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCodeTokenCostReaderTests-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: dbURL) }
        try Self.createSessionTable(at: dbURL)

        let day = Date(timeIntervalSince1970: 1_770_000_000)
        try Self.insertSession(
            dbURL: dbURL,
            updatedMs: self.ms(day),
            model: #"{"id":"gpt-5.5","providerID":"openai"}"#,
            cost: 1.0,
            tokens: (input: 10, output: 5))
        try Self.insertSession(
            dbURL: dbURL,
            updatedMs: self.ms(day),
            model: #"{"id":"kimi-k2.7-code","providerID":"opencode-go"}"#,
            cost: 50.0,
            tokens: (input: 9999, output: 9999))

        let emptyCacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenCodeTokenCostReaderTests-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyCacheRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyCacheRoot) }

        let report = OpenCodeTokenCostReader(databaseURL: dbURL, cacheRoot: emptyCacheRoot)
            .loadDailyReport(since: day.addingTimeInterval(-86400), until: day.addingTimeInterval(86400))

        #expect(report.summary?.totalCostUSD == 1.0)
        #expect(report.data.first?.requestCount == 1)
    }

    @Test func returnsEmptyWhenDatabaseMissing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).db")
        let report = OpenCodeTokenCostReader(databaseURL: missing)
            .loadDailyReport(since: Date(timeIntervalSince1970: 0), until: Date())
        #expect(report.data.isEmpty)
    }


    private func ms(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private static func createSessionTable(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw SQLiteReaderTestError.open }
        defer { sqlite3_close(db) }
        var message: UnsafeMutablePointer<CChar>?
        let sql = """
            CREATE TABLE session (
              id TEXT PRIMARY KEY,
              time_updated INTEGER,
              model TEXT,
              cost REAL,
              tokens_input INTEGER,
              tokens_output INTEGER,
              tokens_reasoning INTEGER,
              tokens_cache_read INTEGER,
              tokens_cache_write INTEGER
            );
        """
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            sqlite3_free(message)
            throw SQLiteReaderTestError.exec
        }
    }

    private static func insertSession(
        dbURL: URL,
        updatedMs: Int64,
        model: String,
        cost: Double,
        tokens: (input: Int, output: Int)) throws
    {
        let (input, output) = tokens
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { throw SQLiteReaderTestError.open }
        defer { sqlite3_close(db) }

        let sql = """
            INSERT INTO session
              (id, time_updated, model, cost, tokens_input, tokens_output, tokens_reasoning,
               tokens_cache_read, tokens_cache_write)
            VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw SQLiteReaderTestError.exec }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, UUID().uuidString, -1, transient)
        sqlite3_bind_int64(stmt, 2, updatedMs)
        sqlite3_bind_text(stmt, 3, model, -1, transient)
        sqlite3_bind_double(stmt, 4, cost)
        sqlite3_bind_int64(stmt, 5, Int64(input))
        sqlite3_bind_int64(stmt, 6, Int64(output))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw SQLiteReaderTestError.exec }
    }
}

private enum SQLiteReaderTestError: Error {
    case open
    case exec
}

#endif
