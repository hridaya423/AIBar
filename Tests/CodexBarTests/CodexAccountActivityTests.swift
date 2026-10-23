import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexAccountActivityTests {
    private static let now = Date(timeIntervalSince1970: 1_772_798_400)

    private static func window(used: Double, resetsIn: TimeInterval? = nil) -> RateWindow {
        RateWindow(
            usedPercent: used,
            windowMinutes: 300,
            resetsAt: resetsIn.map { self.now.addingTimeInterval($0) },
            resetDescription: nil)
    }

    @Test
    func `rising session percent marks the account active`() {
        var activity = CodexAccountActivity()
        activity.update(sessionUsedPercents: ["a": 10, "b": 40], now: Self.now)
        #expect(activity.mostRecentlyActiveID(now: Self.now) == nil)

        activity.update(sessionUsedPercents: ["a": 10, "b": 45], now: Self.now.addingTimeInterval(60))

        #expect(activity.mostRecentlyActiveID(now: Self.now.addingTimeInterval(60)) == "b")
    }

    @Test
    func `sub threshold drift and resets do not count as activity`() {
        var activity = CodexAccountActivity()
        activity.update(sessionUsedPercents: ["a": 10], now: Self.now)
        activity.update(sessionUsedPercents: ["a": 10.4], now: Self.now.addingTimeInterval(60))
        activity.update(sessionUsedPercents: ["a": 0], now: Self.now.addingTimeInterval(120))
        #expect(activity.mostRecentlyActiveID(now: Self.now.addingTimeInterval(120)) == nil)
    }

    @Test
    func `most recent activity wins and expires after two hours`() {
        var activity = CodexAccountActivity()
        activity.update(sessionUsedPercents: ["a": 10, "b": 10], now: Self.now)
        activity.update(sessionUsedPercents: ["a": 20, "b": 10], now: Self.now.addingTimeInterval(60))
        activity.update(sessionUsedPercents: ["a": 20, "b": 30], now: Self.now.addingTimeInterval(120))

        #expect(activity.mostRecentlyActiveID(now: Self.now.addingTimeInterval(180)) == "b")
        #expect(activity.mostRecentlyActiveID(now: Self.now.addingTimeInterval(120 + 2 * 3600 + 1)) == nil)
    }

    @Test
    func `removed accounts are forgotten`() {
        var activity = CodexAccountActivity()
        activity.update(sessionUsedPercents: ["a": 10], now: Self.now)
        activity.update(sessionUsedPercents: ["a": 30], now: Self.now.addingTimeInterval(60))
        activity.update(sessionUsedPercents: ["b": 5], now: Self.now.addingTimeInterval(120))
        #expect(activity.mostRecentlyActiveID(now: Self.now.addingTimeInterval(120)) == nil)
    }

    @Test
    func `all exhausted accounts pick the soonest reset`() {
        let sessions = [
            "a": Self.window(used: 100, resetsIn: 3600),
            "b": Self.window(used: 100, resetsIn: 600),
        ]
        #expect(CodexAccountActivity.soonestResetWhenAllExhausted(sessions: sessions) == "b")
    }

    @Test
    func `no exhausted pick unless every account is exhausted`() {
        let mixed = [
            "a": Self.window(used: 100, resetsIn: 3600),
            "b": Self.window(used: 40, resetsIn: 600),
        ]
        #expect(CodexAccountActivity.soonestResetWhenAllExhausted(sessions: mixed) == nil)
        #expect(CodexAccountActivity.soonestResetWhenAllExhausted(
            sessions: ["a": Self.window(used: 100, resetsIn: 60)]) == nil)
    }
}
