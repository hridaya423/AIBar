import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MenuBarPercentAndResetTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func window(remaining: Double, resetInSeconds: TimeInterval?) -> RateWindow {
        RateWindow(
            usedPercent: 100 - remaining,
            windowMinutes: nil,
            resetsAt: resetInSeconds.map { self.now.addingTimeInterval($0) },
            resetDescription: nil)
    }

    @Test func shortResetUsesLargestUnit() {
        #expect(MenuBarDisplayText.shortResetText(
            window: Self.window(remaining: 0, resetInSeconds: 4 * 3600),
            now: Self.now) == "4h")
        #expect(MenuBarDisplayText.shortResetText(
            window: Self.window(remaining: 0, resetInSeconds: 3 * 86400),
            now: Self.now) == "3d")
        #expect(MenuBarDisplayText.shortResetText(
            window: Self.window(remaining: 0, resetInSeconds: 12 * 60),
            now: Self.now) == "12m")
        #expect(MenuBarDisplayText.shortResetText(
            window: Self.window(remaining: 0, resetInSeconds: nil),
            now: Self.now) == nil)
    }

    @Test func shortResetRoundsToNearestUnit() {
        #expect(MenuBarDisplayText.shortResetText(
            window: Self.window(remaining: 0, resetInSeconds: 2 * 3600 + 57 * 60),
            now: Self.now) == "3h")
        #expect(MenuBarDisplayText.shortResetText(
            window: Self.window(remaining: 0, resetInSeconds: 2 * 3600 + 20 * 60),
            now: Self.now) == "2h")
        #expect(MenuBarDisplayText.shortResetText(
            window: Self.window(remaining: 0, resetInSeconds: 23 * 3600 + 40 * 60),
            now: Self.now) == "1d")
        #expect(MenuBarDisplayText.shortResetText(
            window: Self.window(remaining: 0, resetInSeconds: 59 * 60 + 40),
            now: Self.now) == "1h")
    }

    @Test func codexCombinedShowsBothWindowsWithoutSessionLabel() {
        let session = Self.window(remaining: 42, resetInSeconds: 4 * 3600)
        let weekly = Self.window(remaining: 78, resetInSeconds: 3 * 86400)
        let text = MenuBarDisplayText.codexCombinedPercentAndResetText(
            sessionWindow: session,
            weeklyWindow: weekly,
            showUsed: false,
            now: Self.now)
        #expect(text == "42% 4h · W 78% 3d")
    }

    @Test func singleWindowModeShowsPercentAndCountdown() {
        let session = Self.window(remaining: 42, resetInSeconds: 4 * 3600)
        let text = MenuBarDisplayText.displayText(
            mode: .percentAndReset,
            percentWindow: session,
            showUsed: false,
            now: Self.now)
        #expect(text == "42% 4h")
    }

    @Test func percentOnlyWhenNoResetTime() {
        let session = Self.window(remaining: 42, resetInSeconds: nil)
        let text = MenuBarDisplayText.displayText(
            mode: .percentAndReset,
            percentWindow: session,
            showUsed: false,
            now: Self.now)
        #expect(text == "42%")
    }
}
