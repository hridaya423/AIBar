import Foundation
import Testing
@testable import CodexBarCore

struct CodexUsagePatternModelTests {
    private static var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        self.utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func saturdayEvents(hours: [Int], perHour: Int) -> [CodexUsagePatternModel.Event] {
        var events: [CodexUsagePatternModel.Event] = []
        for day in [6, 13, 20, 27] {
            for hour in hours {
                for _ in 0..<perHour {
                    events.append(.init(timestamp: Self.date(2024, 1, day, hour), weight: 1))
                }
            }
        }
        return events
    }

    @Test func buildNormalizesAndCounts() {
        let events = Self.saturdayEvents(hours: [10], perHour: 8) // 4 saturdays * 8 = 32 events
        let model = CodexUsagePatternModel.build(events: events, calendar: Self.utc)
        #expect(model.eventCount == 32)
        #expect(model.isUsable)
        let total = model.intensity.reduce(0) { $0 + $1.reduce(0, +) }
        #expect(abs(total - 1.0) < 1e-9)
        #expect(abs(model.intensity[6][10] - 1.0) < 1e-9)
    }

    @Test func notUsableBelowThreshold() {
        let events = Self.saturdayEvents(hours: [10], perHour: 2) // 8 events < 20
        let model = CodexUsagePatternModel.build(events: events, calendar: Self.utc)
        #expect(!model.isUsable)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 360,
            resetsAt: Self.date(2024, 1, 6, 12),
            resetDescription: nil)
        #expect(model.usagePace(window: window, now: Self.date(2024, 1, 6, 10), calendar: Self.utc) == nil)
    }

    @Test func massIsZeroOutsideActiveBuckets() {
        let model = CodexUsagePatternModel.build(
            events: Self.saturdayEvents(hours: [10], perHour: 8),
            calendar: Self.utc)
        #expect(model.mass(from: Self.date(2024, 1, 6, 10), to: Self.date(2024, 1, 6, 11), calendar: Self.utc) > 0.9)
        #expect(model.mass(from: Self.date(2024, 1, 7, 10), to: Self.date(2024, 1, 7, 12), calendar: Self.utc) == 0)
    }

    @Test func lastsToResetWhenRemainingTimeIsIdle() throws {
        let model = CodexUsagePatternModel.build(
            events: Self.saturdayEvents(hours: [10], perHour: 8),
            calendar: Self.utc)
        let window = RateWindow(
            usedPercent: 60,
            windowMinutes: 36 * 60, // windowStart = Sat 00:00
            resetsAt: Self.date(2024, 1, 7, 12), // Sunday noon
            resetDescription: nil)
        let pace = model.usagePace(window: window, now: Self.date(2024, 1, 7, 0), calendar: Self.utc)
        let resolved = try #require(pace)
        #expect(resolved.willLastToReset)
        #expect(resolved.etaSeconds == nil)
    }

    @Test func finiteEtaWhenAheadAndRemainingIsHeavy() throws {
        let model = CodexUsagePatternModel.build(
            events: Self.saturdayEvents(hours: [8, 9, 10, 11], perHour: 8),
            calendar: Self.utc)
        let window = RateWindow(
            usedPercent: 80,
            windowMinutes: 360, // windowStart = Sat 06:00
            resetsAt: Self.date(2024, 1, 6, 12),
            resetDescription: nil)
        let pace = model.usagePace(window: window, now: Self.date(2024, 1, 6, 10), calendar: Self.utc)
        let resolved = try #require(pace)
        let eta = try #require(resolved.etaSeconds)
        #expect(eta > 0)
        #expect(eta < 2 * 3600) // runs out before the 2h-away reset
        #expect(!resolved.willLastToReset)
    }
}
