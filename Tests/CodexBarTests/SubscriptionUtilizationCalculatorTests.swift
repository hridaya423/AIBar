import Foundation
import Testing
@testable import CodexBarCore

struct SubscriptionUtilizationCalculatorTests {
    private static func now() -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 20
        comps.hour = 12
        return Calendar.current.date(from: comps)!
    }

    private static func entry(daysAgo: Int, cost: Double, from now: Date) -> CostUsageDailyReport.Entry {
        let date = SubscriptionUtilizationCalculator.dayKey(from: now.addingTimeInterval(-Double(daysAgo) * 86400))
        return CostUsageDailyReport.Entry(
            date: date,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: nil,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: nil)
    }

    @Test func extrapolatesPartialWeekToMonthlyCeiling() throws {
        let now = Self.now()
        let daily = (0...5).map { Self.entry(daysAgo: $0, cost: 2, from: now) }
        let estimate = try #require(SubscriptionUtilizationCalculator.estimate(
            daily: daily,
            weeklyUsedPercent: 60,
            weeklyResetsAt: now.addingTimeInterval(2 * 86400),
            weeklyWindowMinutes: 7 * 24 * 60,
            now: now))

        #expect(abs(estimate.monthlyMaxUSD - (20.0 * 30.0 / 7.0)) < 0.001)
        #expect(estimate.monthlyUsedUSD == 12)
        #expect(abs(estimate.utilizationPercent - (12.0 / (20.0 * 30.0 / 7.0) * 100)) < 0.001)
        #expect(estimate.isProjected)
    }

    @Test func exhaustedWeekIsNotProjected() throws {
        let now = Self.now()
        let daily = (0...5).map { Self.entry(daysAgo: $0, cost: 5, from: now) }
        let estimate = try #require(SubscriptionUtilizationCalculator.estimate(
            daily: daily,
            weeklyUsedPercent: 100,
            weeklyResetsAt: now.addingTimeInterval(86400),
            weeklyWindowMinutes: 7 * 24 * 60,
            now: now))
        #expect(!estimate.isProjected)
        #expect(abs(estimate.monthlyMaxUSD - (30.0 * 30.0 / 7.0)) < 0.001)
    }

    @Test func returnsNilBelowMinimumWeeklyFill() {
        let now = Self.now()
        let daily = [Self.entry(daysAgo: 0, cost: 1, from: now)]
        #expect(SubscriptionUtilizationCalculator.estimate(
            daily: daily,
            weeklyUsedPercent: 3,
            weeklyResetsAt: now,
            weeklyWindowMinutes: 7 * 24 * 60,
            now: now) == nil)
    }

    @Test func returnsNilWhenNoSpendInWindow() {
        let now = Self.now()
        let daily = [Self.entry(daysAgo: 40, cost: 9, from: now)]
        #expect(SubscriptionUtilizationCalculator.estimate(
            daily: daily,
            weeklyUsedPercent: 50,
            weeklyResetsAt: now,
            weeklyWindowMinutes: 7 * 24 * 60,
            now: now) == nil)
    }
}
