import Foundation

public struct CodexUsagePatternModel: Sendable, Equatable {
    public static let cellCount = 7 * 24
    public static let minimumEvents = 20
    private static let week: TimeInterval = 7 * 24 * 3600
    private static let dstTolerance: TimeInterval = 2 * 3600
    private static let epsilon = 1e-9

    private let prefix: [Double]
    private let calendar: Calendar

    public init?(weights: [Double], calendar: Calendar = .current) {
        guard weights.count == Self.cellCount else { return nil }
        let total = weights.reduce(0, +)
        guard total > Self.epsilon else { return nil }
        var prefix = [0.0]
        prefix.reserveCapacity(Self.cellCount + 1)
        for weight in weights {
            prefix.append(prefix[prefix.count - 1] + weight / total)
        }
        self.prefix = prefix
        self.calendar = calendar
    }

    public init?(events: [(timestamp: Date, weight: Double)], calendar: Calendar = .current) {
        var weights = [Double](repeating: 0, count: Self.cellCount)
        var count = 0
        for event in events where event.weight > 0 {
            let parts = calendar.dateComponents([.weekday, .hour], from: event.timestamp)
            guard let weekday = parts.weekday, let hour = parts.hour else { continue }
            weights[(weekday - 1) * 24 + hour] += event.weight
            count += 1
        }
        guard count >= Self.minimumEvents else { return nil }
        self.init(weights: weights, calendar: calendar)
    }

    func mass(from start: Date, to end: Date) -> Double {
        let seconds = end.timeIntervalSince(start)
        guard seconds > 0 else { return 0 }
        if seconds >= Self.week - Self.dstTolerance { return 1 }
        let delta = self.position(of: end) - self.position(of: start)
        return delta < 0 ? delta + 1 : delta
    }

    public func usagePace(window: RateWindow, now: Date) -> UsagePace? {
        guard let resetsAt = window.resetsAt, let minutes = window.windowMinutes, minutes > 0 else { return nil }
        let duration = TimeInterval(minutes) * 60
        let untilReset = resetsAt.timeIntervalSince(now)
        guard duration <= Self.week + Self.dstTolerance, untilReset > 0, untilReset <= duration else { return nil }

        let start = resetsAt.addingTimeInterval(-duration)
        let elapsedMass = self.mass(from: start, to: now)
        let totalMass = self.mass(from: start, to: resetsAt)
        guard elapsedMass > Self.epsilon, totalMass > Self.epsilon else { return nil }

        let actual = window.usedPercent.clamped(to: 0...100)
        let expected = (100 * elapsedMass / totalMass).clamped(to: 0...100)
        let remainingMass = max(0, totalMass - elapsedMass)
        var eta: TimeInterval?
        var willLastToReset = false
        if actual >= 100 {
            eta = 0
        } else if actual <= 0 {
            willLastToReset = true
        } else {
            let neededMass = (100 - actual) / (actual / elapsedMass)
            if neededMass >= remainingMass {
                willLastToReset = true
            } else {
                eta = self.timeToAccumulate(mass: neededMass, from: now, until: resetsAt)
            }
        }
        return UsagePace.historical(
            expectedUsedPercent: expected,
            actualUsedPercent: actual,
            etaSeconds: eta,
            willLastToReset: willLastToReset,
            runOutProbability: nil,
            projectedRemainingUsage: actual * remainingMass / elapsedMass)
    }

    private func timeToAccumulate(mass target: Double, from start: Date, until end: Date) -> TimeInterval {
        var low: TimeInterval = 0
        var high = end.timeIntervalSince(start)
        while high - low > 1 {
            let mid = (low + high) / 2
            if self.mass(from: start, to: start.addingTimeInterval(mid)) >= target {
                high = mid
            } else {
                low = mid
            }
        }
        return high
    }

    private func position(of date: Date) -> Double {
        let parts = self.calendar.dateComponents([.weekday, .hour, .minute, .second], from: date)
        let cell = ((parts.weekday ?? 1) - 1) * 24 + (parts.hour ?? 0)
        let intoHour = Double((parts.minute ?? 0) * 60 + (parts.second ?? 0)) / 3600
        return self.prefix[cell] + (self.prefix[cell + 1] - self.prefix[cell]) * intoHour
    }
}
