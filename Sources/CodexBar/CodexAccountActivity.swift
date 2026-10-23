import CodexBarCore
import Foundation

struct CodexAccountActivity: Equatable {
    static let activeWindow: TimeInterval = 2 * 60 * 60
    private static let risingThreshold = 0.5

    private var lastUsedPercent: [String: Double] = [:]
    private(set) var lastActivityAt: [String: Date] = [:]

    mutating func update(sessionUsedPercents: [String: Double], now: Date) {
        self.lastUsedPercent = self.lastUsedPercent.filter { sessionUsedPercents[$0.key] != nil }
        self.lastActivityAt = self.lastActivityAt.filter { sessionUsedPercents[$0.key] != nil }
        for (id, used) in sessionUsedPercents {
            if let previous = self.lastUsedPercent[id], used > previous + Self.risingThreshold {
                self.lastActivityAt[id] = now
            }
            self.lastUsedPercent[id] = used
        }
    }

    func mostRecentlyActiveID(now: Date) -> String? {
        self.lastActivityAt
            .filter { (0...Self.activeWindow).contains(now.timeIntervalSince($0.value)) }
            .max { $0.value < $1.value }?
            .key
    }

    static func soonestResetWhenAllExhausted(sessions: [String: RateWindow]) -> String? {
        guard sessions.count > 1, sessions.values.allSatisfy({ $0.remainingPercent <= 0 }) else { return nil }
        return sessions
            .compactMap { id, window in window.resetsAt.map { (id, $0) } }
            .min { $0.1 < $1.1 }?
            .0
    }
}
