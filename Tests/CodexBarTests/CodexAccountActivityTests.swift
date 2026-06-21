import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CodexAccountActivityTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let window: TimeInterval = 2 * 60 * 60

    private static func sample(_ id: String, _ used: Double?) -> CodexAccountActivityState.Sample {
        CodexAccountActivityState.Sample(id: id, sessionUsedPercent: used)
    }

    @Test func usageIncreaseMarksAccountActive() {
        var state = CodexAccountActivityState()
        state.update(samples: [Self.sample("a", 10), Self.sample("b", 20)], now: Self.t0)
        #expect(state.mostActiveAccountID(now: Self.t0, within: Self.window) == nil)

        state.update(samples: [Self.sample("a", 10), Self.sample("b", 25)], now: Self.t0.addingTimeInterval(60))
        #expect(state.mostActiveAccountID(now: Self.t0.addingTimeInterval(60), within: Self.window) == "b")
    }

    @Test func mostRecentActivityWins() {
        var state = CodexAccountActivityState()
        state.update(samples: [Self.sample("a", 10), Self.sample("b", 20)], now: Self.t0)
        state.update(samples: [Self.sample("a", 15), Self.sample("b", 20)], now: Self.t0.addingTimeInterval(60))
        state.update(samples: [Self.sample("a", 15), Self.sample("b", 26)], now: Self.t0.addingTimeInterval(120))
        #expect(state.mostActiveAccountID(now: Self.t0.addingTimeInterval(120), within: Self.window) == "b")
    }

    @Test func usageDecreaseIsNotActivity() {
        var state = CodexAccountActivityState()
        state.update(samples: [Self.sample("a", 80)], now: Self.t0)
        state.update(samples: [Self.sample("a", 2)], now: Self.t0.addingTimeInterval(60))
        #expect(state.mostActiveAccountID(now: Self.t0.addingTimeInterval(60), within: Self.window) == nil)
    }

    @Test func subThresholdJitterIgnored() {
        var state = CodexAccountActivityState()
        state.update(samples: [Self.sample("a", 10)], now: Self.t0)
        state.update(samples: [Self.sample("a", 10.3)], now: Self.t0.addingTimeInterval(60))
        #expect(state.mostActiveAccountID(now: Self.t0.addingTimeInterval(60), within: Self.window) == nil)
    }

    @Test func activityExpiresOutsideWindow() {
        var state = CodexAccountActivityState()
        state.update(samples: [Self.sample("a", 10)], now: Self.t0)
        state.update(samples: [Self.sample("a", 15)], now: Self.t0.addingTimeInterval(60))
        let later = Self.t0.addingTimeInterval(Self.window + 120)
        #expect(state.mostActiveAccountID(now: later, within: Self.window) == nil)
    }

    @Test func removedAccountsArePruned() {
        var state = CodexAccountActivityState()
        state.update(samples: [Self.sample("a", 10), Self.sample("b", 20)], now: Self.t0)
        state.update(samples: [Self.sample("b", 25)], now: Self.t0.addingTimeInterval(60))
        #expect(state.lastActivityAt["a"] == nil)
        #expect(state.mostActiveAccountID(now: Self.t0.addingTimeInterval(60), within: Self.window) == "b")
    }


    private static func session(used: Double, resetsInSeconds: TimeInterval?) -> RateWindow {
        RateWindow(
            usedPercent: used,
            windowMinutes: 300,
            resetsAt: resetsInSeconds.map { self.t0.addingTimeInterval($0) },
            resetDescription: nil)
    }

    @Test func allExhaustedPicksNearestReset() {
        let sessions: [(id: String, window: RateWindow)] = [
            ("a", Self.session(used: 100, resetsInSeconds: 3 * 3600)),
            ("b", Self.session(used: 100, resetsInSeconds: 1 * 3600)),
            ("c", Self.session(used: 100, resetsInSeconds: 2 * 3600)),
        ]
        #expect(CodexAccountActivityState.nearestResetAccountIDWhenAllExhausted(sessions: sessions) == "b")
    }

    @Test func notAllExhaustedReturnsNil() {
        let sessions: [(id: String, window: RateWindow)] = [
            ("a", Self.session(used: 100, resetsInSeconds: 3 * 3600)),
            ("b", Self.session(used: 40, resetsInSeconds: 1 * 3600)), // still has headroom
        ]
        #expect(CodexAccountActivityState.nearestResetAccountIDWhenAllExhausted(sessions: sessions) == nil)
    }

    @Test func singleAccountReturnsNil() {
        let sessions: [(id: String, window: RateWindow)] = [
            ("a", Self.session(used: 100, resetsInSeconds: 3600)),
        ]
        #expect(CodexAccountActivityState.nearestResetAccountIDWhenAllExhausted(sessions: sessions) == nil)
    }
}
