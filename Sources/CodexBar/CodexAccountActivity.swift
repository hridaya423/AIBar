import CodexBarCore
import Foundation

struct CodexAccountActivityState {
    private static let activityThreshold: Double = 0.5

    private var lastUsedPercent: [String: Double] = [:]
    private(set) var lastActivityAt: [String: Date] = [:]

    struct Sample {
        let id: String
        let sessionUsedPercent: Double?
    }

    mutating func update(samples: [Sample], now: Date) {
        let liveIDs = Set(samples.map(\.id))
        self.lastUsedPercent = self.lastUsedPercent.filter { liveIDs.contains($0.key) }
        self.lastActivityAt = self.lastActivityAt.filter { liveIDs.contains($0.key) }

        for sample in samples {
            guard let used = sample.sessionUsedPercent else { continue }
            if let previous = self.lastUsedPercent[sample.id], used > previous + Self.activityThreshold {
                self.lastActivityAt[sample.id] = now
            }
            self.lastUsedPercent[sample.id] = used
        }
    }

    func mostActiveAccountID(now: Date, within window: TimeInterval) -> String? {
        self.lastActivityAt
            .filter { now.timeIntervalSince($0.value) <= window && now.timeIntervalSince($0.value) >= 0 }
            .max { $0.value < $1.value }?
            .key
    }

    static func nearestResetAccountIDWhenAllExhausted(
        sessions: [(id: String, window: RateWindow)]) -> String?
    {
        guard sessions.count > 1 else { return nil }
        guard sessions.allSatisfy({ $0.window.remainingPercent <= 0 }) else { return nil }
        return sessions
            .compactMap { session in session.window.resetsAt.map { (session.id, $0) } }
            .min { $0.1 < $1.1 }?
            .0
    }
}
