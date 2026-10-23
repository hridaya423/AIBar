import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MetricPaceSummaryTests {
    @Test
    func `pace detail carries a used so far and pace summary`() throws {
        let now = Date(timeIntervalSince1970: 0)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 10080,
            resetsAt: now.addingTimeInterval(4 * 24 * 3600),
            resetDescription: nil)
        let pace = try #require(UsagePace.weekly(window: window, now: now))

        let detail = UsageMenuCardView.Model.weeklyPaceDetail(
            provider: .codex,
            window: window,
            now: now,
            pace: pace,
            showUsed: false)

        #expect(detail?.summaryText == "Used so far 50% · Pace 43%")
    }
}
