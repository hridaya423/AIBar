import Foundation

public struct SubscriptionValueEstimate: Sendable, Equatable {
    public let usedUSD: Double
    public let monthlyMaxUSD: Double

    public var utilization: Double {
        self.monthlyMaxUSD > 0 ? self.usedUSD / self.monthlyMaxUSD : 0
    }

    public static func make(
        snapshot: CostUsageTokenSnapshot,
        weekly: RateWindow,
        now: Date,
        calendar: Calendar) -> SubscriptionValueEstimate?
    {
        let fill = weekly.usedPercent / 100
        guard fill >= 0.08,
              let week = snapshot.quotaWeekSummaries(
                  resetAt: CostUsageTokenSnapshot.quotaWeekReset(from: weekly),
                  windowMinutes: weekly.windowMinutes,
                  weekCount: 1,
                  now: now,
                  calendar: calendar).first(where: \.isCurrent),
              week.costIsComplete,
              let weekCost = week.totalCostUSD, weekCost > 0,
              let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count
        else { return nil }
        let monthKey = CostUsageScanner.CostUsageDayRange.dayKey(from: now, calendar: calendar).prefix(7)
        let used = snapshot.daily.reduce(0) { $0 + ($1.date.hasPrefix(monthKey) ? $1.costUSD ?? 0 : 0) }
        return SubscriptionValueEstimate(
            usedUSD: used,
            monthlyMaxUSD: weekCost / min(fill, 1) * Double(daysInMonth) / 7)
    }
}
