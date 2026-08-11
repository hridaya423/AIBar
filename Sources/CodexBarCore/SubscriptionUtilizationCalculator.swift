import Foundation

public struct SubscriptionUtilizationEstimate: Sendable, Equatable {
    public let monthlyMaxUSD: Double
    public let monthlyUsedUSD: Double
    public let utilizationPercent: Double
    public let currencyCode: String
    public let isProjected: Bool

    public init(
        monthlyMaxUSD: Double,
        monthlyUsedUSD: Double,
        utilizationPercent: Double,
        currencyCode: String,
        isProjected: Bool)
    {
        self.monthlyMaxUSD = monthlyMaxUSD
        self.monthlyUsedUSD = monthlyUsedUSD
        self.utilizationPercent = utilizationPercent
        self.currencyCode = currencyCode
        self.isProjected = isProjected
    }
}

public enum SubscriptionUtilizationCalculator {
    public static let minimumWeeklyFillPercent: Double = 8

    public static func estimate(
        daily: [CostUsageDailyReport.Entry],
        weeklyUsedPercent: Double,
        weeklyResetsAt: Date?,
        weeklyWindowMinutes: Int?,
        currencyCode: String = "USD",
        now: Date = Date()) -> SubscriptionUtilizationEstimate?
    {
        let fill = max(0, min(100, weeklyUsedPercent))
        guard fill >= self.minimumWeeklyFillPercent else { return nil }

        let windowSeconds = TimeInterval((weeklyWindowMinutes ?? (7 * 24 * 60)) * 60)
        let windowEnd = weeklyResetsAt ?? now
        let windowStart = windowEnd.addingTimeInterval(-windowSeconds)

        let nowKey = self.dayKey(from: now)
        let weekStartKey = self.dayKey(from: min(windowStart, now))
        let monthStartKey = self.dayKey(from: self.startOfMonth(for: now))

        let thisWeekSpend = self.sumCost(daily: daily, fromKey: weekStartKey, throughKey: nowKey)
        guard thisWeekSpend > 0 else { return nil }

        let weeklyCeiling = thisWeekSpend / (fill / 100)
        let daysInMonth = self.daysInMonth(for: now)
        let monthlyMax = weeklyCeiling * (Double(daysInMonth) / 7.0)

        let monthlyUsed = self.sumCost(daily: daily, fromKey: monthStartKey, throughKey: nowKey)
        let utilization = monthlyMax > 0 ? min(999, monthlyUsed / monthlyMax * 100) : 0

        return SubscriptionUtilizationEstimate(
            monthlyMaxUSD: monthlyMax,
            monthlyUsedUSD: monthlyUsed,
            utilizationPercent: utilization,
            currencyCode: currencyCode,
            isProjected: fill < 99.5)
    }

    static func dayKey(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 1970, comps.month ?? 1, comps.day ?? 1)
    }

    private static func sumCost(
        daily: [CostUsageDailyReport.Entry],
        fromKey: String,
        throughKey: String) -> Double
    {
        daily.reduce(0.0) { total, entry in
            guard entry.date >= fromKey, entry.date <= throughKey else { return total }
            return total + (entry.costUSD ?? 0)
        }
    }

    private static func startOfMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func daysInMonth(for date: Date) -> Int {
        Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 30
    }
}
