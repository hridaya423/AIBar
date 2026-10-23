#if os(macOS)

import Foundation
import SQLite3
import Testing
@testable import CodexBarCore

struct CodexOpenCodeOpenAIUsageTests {
    private static let now = Date(timeIntervalSince1970: 1_772_798_400)
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test
    func `merges only openai rows priced with the Codex resolver`() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("opencode.db")
        let rowMs = Int64(Self.now.timeIntervalSince1970 * 1000) - 60000
        try Self.createDatabase(at: database, rows: [
            (
                "openai",
                "gpt-5",
                rowMs,
                ["input": 1000, "output": 400, "reasoning": 100, "cache": ["read": 200, "write": 0]]),
            (
                "opencode-go",
                "kimi-k2",
                rowMs,
                ["input": 5000, "output": 5000, "reasoning": 0, "cache": ["read": 0, "write": 0]]),
            (
                "anthropic",
                "claude-sonnet-4-5",
                rowMs,
                ["input": 7, "output": 7, "reasoning": 0, "cache": ["read": 0, "write": 0]]),
        ])
        let reader = OpenCodeGoLocalUsageReader(
            authURL: root.appendingPathComponent("auth.json"), databaseURL: database, providerID: "openai")

        let merged = reader.mergingCodexUsage(
            into: CostUsageDailyReport(data: [], summary: nil),
            since: Self.now.addingTimeInterval(-86400),
            until: Self.now,
            calendar: Self.calendar,
            cacheRoot: root)

        let expected = try #require(CostUsagePricing.codexCostUSD(
            model: "gpt-5",
            inputTokens: 1200,
            cachedInputTokens: 200,
            outputTokens: 500,
            modelsDevCacheRoot: root))
        let entry = try #require(merged.data.first)
        #expect(merged.data.count == 1)
        #expect(entry.modelsUsed == ["gpt-5"])
        #expect(entry.requestCount == 1)
        #expect(abs((entry.costUSD ?? 0) - expected) < 1e-9)
        #expect(expected > 0)
    }

    @Test
    func `leaves the report untouched when there are no openai rows`() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("opencode.db")
        try Self.createDatabase(at: database, rows: [])
        let reader = OpenCodeGoLocalUsageReader(
            authURL: root.appendingPathComponent("auth.json"), databaseURL: database, providerID: "openai")
        let entry = CostUsageDailyReport.Entry(
            date: "2026-03-06",
            inputTokens: 1,
            outputTokens: 1,
            totalTokens: 2,
            costUSD: 1,
            modelsUsed: ["gpt-5"],
            modelBreakdowns: nil)
        let base = CostUsageDailyReport(data: [entry], summary: nil)

        let merged = reader.mergingCodexUsage(
            into: base,
            since: Self.now.addingTimeInterval(-86400),
            until: Self.now,
            calendar: Self.calendar,
            cacheRoot: root)

        #expect(merged.data == base.data)
    }

    @Test
    func `go reader keeps reading opencode-go rows by default`() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("opencode.db")
        let rowMs = Int64(Self.now.timeIntervalSince1970 * 1000) - 60000
        try Self.createDatabase(at: database, rows: [
            ("openai", "gpt-5", rowMs, ["input": 1, "output": 1, "reasoning": 0, "cache": ["read": 0, "write": 0]]),
            (
                "opencode-go",
                "kimi-k2",
                rowMs,
                ["input": 1, "output": 1, "reasoning": 0, "cache": ["read": 0, "write": 0]]),
        ])
        let reader = OpenCodeGoLocalUsageReader(
            authURL: root.appendingPathComponent("auth.json"),
            databaseURL: database)

        #expect(try reader.cachedRows().count == 1)
    }

    private enum SQLiteTestError: Error {
        case open, prepare, step
    }

    private static func tokens(input: Int, output: Int, reasoning: Int = 0, cacheRead: Int = 0) -> [String: Any] {
        ["input": input, "output": output, "reasoning": reasoning, "cache": ["read": cacheRead, "write": 0]]
    }

    private static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexOpenCodeOpenAIUsageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func createDatabase(
        at url: URL,
        rows: [(provider: String, model: String, createdMs: Int64, tokens: [String: Any])]) throws
    {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw SQLiteTestError.open }
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE message (
          id TEXT PRIMARY KEY, session_id TEXT NOT NULL, data TEXT NOT NULL, time_created INTEGER, time_updated INTEGER
        );
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { throw SQLiteTestError.step }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for row in rows {
            let payload: [String: Any] = [
                "providerID": row.provider,
                "role": "assistant",
                "modelID": row.model,
                "cost": 0,
                "time": ["created": row.createdMs],
                "tokens": row.tokens,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let json = String(bytes: data, encoding: .utf8) else { throw SQLiteTestError.prepare }
            var stmt: OpaquePointer?
            let insert = "INSERT INTO message VALUES (?, 's', ?, ?, ?)"
            guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK else { throw SQLiteTestError.prepare }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, UUID().uuidString, -1, transient)
            sqlite3_bind_text(stmt, 2, json, -1, transient)
            sqlite3_bind_int64(stmt, 3, row.createdMs)
            sqlite3_bind_int64(stmt, 4, row.createdMs)
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw SQLiteTestError.step }
        }
    }
}

#endif
