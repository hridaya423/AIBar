import Foundation

public struct CodexUsagePatternModel: Sendable, Equatable {
    public static let weekdayCount = 7
    public static let hourCount = 24
    public static let minimumEvents = 20
    private static let epsilon = 1e-9

    public struct Event: Sendable, Equatable {
        public let timestamp: Date
        public let weight: Double
        public init(timestamp: Date, weight: Double) {
            self.timestamp = timestamp
            self.weight = weight
        }
    }

    public let intensity: [[Double]]
    public let eventCount: Int

    public var isUsable: Bool {
        self.eventCount >= Self.minimumEvents
    }

    public init(intensity: [[Double]], eventCount: Int) {
        self.intensity = intensity
        self.eventCount = eventCount
    }

    public static func build(events: [Event], calendar: Calendar = .current) -> CodexUsagePatternModel {
        var grid = Array(repeating: Array(repeating: 0.0, count: Self.hourCount), count: Self.weekdayCount)
        var count = 0
        for event in events {
            let weight = max(0, event.weight)
            guard weight > 0 else { continue }
            let comps = calendar.dateComponents([.weekday, .hour], from: event.timestamp)
            guard let weekday = comps.weekday, let hour = comps.hour else { continue }
            grid[weekday - 1][hour] += weight
            count += 1
        }
        let total = grid.reduce(0) { $0 + $1.reduce(0, +) }
        if total > Self.epsilon {
            for i in 0..<Self.weekdayCount {
                for j in 0..<Self.hourCount {
                    grid[i][j] /= total
                }
            }
        }
        return CodexUsagePatternModel(intensity: grid, eventCount: count)
    }

    public func mass(from start: Date, to end: Date, calendar: Calendar = .current) -> Double {
        guard end > start else { return 0 }
        var total = 0.0
        var cursor = start
        var guardCounter = 0
        while cursor < end, guardCounter < 24 * 366 {
            guardCounter += 1
            let comps = calendar.dateComponents([.weekday, .hour], from: cursor)
            guard let weekday = comps.weekday, let hour = comps.hour else { break }
            let nextHour = Self.startOfNextHour(after: cursor, calendar: calendar)
            let sliceEnd = min(nextHour, end)
            let fraction = sliceEnd.timeIntervalSince(cursor) / 3600
            total += self.intensity[weekday - 1][hour] * fraction
            guard sliceEnd > cursor else { break }
            cursor = sliceEnd
        }
        return total
    }

    public func usagePace(window: RateWindow, now: Date = Date(), calendar: Calendar = .current) -> UsagePace? {
        guard self.isUsable else { return nil }
        guard let resetsAt = window.resetsAt, let minutes = window.windowMinutes, minutes > 0 else { return nil }

        let duration = TimeInterval(minutes) * 60
        let timeUntilReset = resetsAt.timeIntervalSince(now)
        guard timeUntilReset > 0, timeUntilReset <= duration else { return nil }

        let windowStart = resetsAt.addingTimeInterval(-duration)
        let elapsedMass = self.mass(from: windowStart, to: now, calendar: calendar)
        let totalMass = self.mass(from: windowStart, to: resetsAt, calendar: calendar)
        guard elapsedMass > Self.epsilon, totalMass > Self.epsilon else { return nil }

        let actual = window.usedPercent.clamped(to: 0...100)
        let expected = (100 * elapsedMass / totalMass).clamped(to: 0...100)

        var etaSeconds: TimeInterval?
        var willLastToReset = false

        if actual >= 100 {
            etaSeconds = 0
        } else if actual <= 0 {
            willLastToReset = true
        } else {
            let usagePerMass = actual / elapsedMass
            let targetMass = (100 - actual) / usagePerMass
            if let eta = self.timeToAccumulate(
                mass: targetMass,
                from: now,
                until: resetsAt,
                calendar: calendar)
            {
                etaSeconds = eta
            } else {
                willLastToReset = true
            }
        }

        return UsagePace.historical(
            expectedUsedPercent: expected,
            actualUsedPercent: actual,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset,
            runOutProbability: nil)
    }

    func timeToAccumulate(
        mass target: Double,
        from start: Date,
        until: Date,
        calendar: Calendar = .current) -> TimeInterval?
    {
        guard target > Self.epsilon else { return 0 }
        var accumulated = 0.0
        var cursor = start
        var guardCounter = 0
        while cursor < until, guardCounter < 24 * 366 {
            guardCounter += 1
            let comps = calendar.dateComponents([.weekday, .hour], from: cursor)
            guard let weekday = comps.weekday, let hour = comps.hour else { return nil }
            let nextHour = Self.startOfNextHour(after: cursor, calendar: calendar)
            let sliceEnd = min(nextHour, until)
            let sliceSeconds = sliceEnd.timeIntervalSince(cursor)
            let sliceMass = self.intensity[weekday - 1][hour] * (sliceSeconds / 3600)
            if accumulated + sliceMass >= target {
                let needed = target - accumulated
                let fraction = sliceMass > Self.epsilon ? needed / sliceMass : 0
                return cursor.timeIntervalSince(start) + (sliceSeconds * fraction)
            }
            accumulated += sliceMass
            guard sliceEnd > cursor else { return nil }
            cursor = sliceEnd
        }
        return nil
    }

    private static func startOfNextHour(after date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let hourStart = calendar.date(from: comps) ?? date
        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? date.addingTimeInterval(3600)
    }
}
