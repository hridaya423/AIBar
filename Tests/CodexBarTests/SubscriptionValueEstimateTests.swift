import Foundation
import Testing
@testable import CodexBarCore

struct SubscriptionValueEstimateTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let now = Date(timeIntervalSince1970: 1_772_798_400)

    private static func weekly(used: Double, resetsIn days: Double? = 2) -> RateWindow {
        RateWindow(
            usedPercent: used,
            windowMinutes: 10080,
            resetsAt: days.map { self.now.addingTimeInterval($0 * 86400) },
            resetDescription: nil)
    }

    private static func snapshot(slices: [(offsetDays: Double, cost: Double)]) -> CostUsageTokenSnapshot {
        let timed = slices.map {
            CostUsageTimedEntry(
                timestamp: self.now.addingTimeInterval($0.offsetDays * 86400),
                totalTokens: 1000,
                costUSD: $0.cost)
        }
        var perDay: [String: Double] = [:]
        for slice in timed {
            let key = CostUsageScanner.CostUsageDayRange.dayKey(from: slice.timestamp, calendar: self.calendar)
            perDay[key, default: 0] += slice.costUSD ?? 0
        }
        let daily = perDay.map {
            CostUsageDailyReport.Entry(
                date: $0.key,
                inputTokens: nil,
                outputTokens: nil,
                totalTokens: nil,
                costUSD: $0.value,
                modelsUsed: nil,
                modelBreakdowns: nil)
        }
        return CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            daily: daily,
            quotaSlices: timed,
            updatedAt: self.now)
    }

    @Test
    func `extrapolates the monthly cap from spend since the weekly reset`() throws {
        let snapshot = Self.snapshot(slices: [(-10, 40), (-5, 20), (-1, 30)])

        let estimate = SubscriptionValueEstimate.make(
            snapshot: snapshot,
            weekly: Self.weekly(used: 50),
            now: Self.now,
            calendar: Self.calendar)

        let days = try Double(#require(Self.calendar.range(of: .day, in: .month, for: Self.now)?.count))
        #expect(abs((estimate?.monthlyMaxUSD ?? 0) - 50 / 0.5 * days / 7) < 1e-9)
        #expect(estimate?.usedUSD == 50)
    }

    @Test
    func `declines below the minimum weekly fill`() {
        let snapshot = Self.snapshot(slices: [(-1, 30)])

        #expect(SubscriptionValueEstimate.make(
            snapshot: snapshot,
            weekly: Self.weekly(used: 5),
            now: Self.now,
            calendar: Self.calendar) == nil)
    }

    @Test
    func `declines without a weekly reset or spend`() {
        let snapshot = Self.snapshot(slices: [(-1, 30)])
        let idle = Self.snapshot(slices: [(-30, 30)])

        #expect(SubscriptionValueEstimate.make(
            snapshot: snapshot,
            weekly: Self.weekly(used: 50, resetsIn: nil),
            now: Self.now,
            calendar: Self.calendar) == nil)
        #expect(SubscriptionValueEstimate.make(
            snapshot: idle,
            weekly: Self.weekly(used: 50),
            now: Self.now,
            calendar: Self.calendar) == nil)
    }
}
