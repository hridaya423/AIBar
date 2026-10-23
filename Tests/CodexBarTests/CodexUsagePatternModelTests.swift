import Foundation
import Testing
@testable import CodexBarCore

struct CodexUsagePatternModelTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let monday = Date(timeIntervalSince1970: 1_772_409_600)

    private static func weekendHeavy() -> CodexUsagePatternModel {
        var weights = [Double](repeating: 0, count: CodexUsagePatternModel.cellCount)
        for cell in 0..<weights.count {
            let weekday = cell / 24 + 1
            weights[cell] = (weekday == 1 || weekday == 7) ? 10 : 1
        }
        return CodexUsagePatternModel(weights: weights, calendar: self.calendar)!
    }

    private static func window(used: Double, resetsAt: Date) -> RateWindow {
        RateWindow(usedPercent: used, windowMinutes: 10080, resetsAt: resetsAt, resetDescription: nil)
    }

    @Test
    func `uniform grid matches linear pace`() throws {
        let uniform = try #require(CodexUsagePatternModel(
            weights: [Double](repeating: 1, count: CodexUsagePatternModel.cellCount), calendar: Self.calendar))
        let resetsAt = Self.monday.addingTimeInterval(7 * 86400)
        let now = Self.monday.addingTimeInterval(2 * 86400 + 5 * 3600)
        let window = Self.window(used: 40, resetsAt: resetsAt)

        let pattern = try #require(uniform.usagePace(window: window, now: now))
        let linear = try #require(UsagePace.weekly(window: window, now: now, calendar: Self.calendar))

        #expect(abs(pattern.expectedUsedPercent - linear.expectedUsedPercent) < 0.01)
        #expect(abs((pattern.etaSeconds ?? 0) - (linear.etaSeconds ?? 0)) < 5)
        #expect(pattern.willLastToReset == linear.willLastToReset)
    }

    @Test
    func `weekend heavy grid shifts expected use and run out time`() throws {
        let model = Self.weekendHeavy()
        let resetsAt = Self.monday.addingTimeInterval(7 * 86400)
        let now = Self.monday.addingTimeInterval(3 * 86400)
        let window = Self.window(used: 25, resetsAt: resetsAt)

        let pattern = try #require(model.usagePace(window: window, now: now))
        let linear = try #require(UsagePace.weekly(window: window, now: now, calendar: Self.calendar))

        #expect(pattern.expectedUsedPercent < linear.expectedUsedPercent)
        #expect((pattern.etaSeconds ?? .infinity) < (linear.etaSeconds ?? .infinity))
    }

    @Test
    func `window spanning a full week counts the whole grid once`() {
        let model = Self.weekendHeavy()
        let mid = Self.monday.addingTimeInterval(3 * 86400 + 1800)
        #expect(abs(model.mass(from: mid, to: mid.addingTimeInterval(7 * 86400)) - 1) < 1e-9)
    }

    @Test
    func `rejects sparse events and empty grids`() {
        let events = (0..<5).map { (timestamp: Self.monday.addingTimeInterval(Double($0) * 3600), weight: 1.0) }
        #expect(CodexUsagePatternModel(events: events, calendar: Self.calendar) == nil)
        #expect(CodexUsagePatternModel(
            weights: [Double](repeating: 0, count: CodexUsagePatternModel.cellCount), calendar: Self.calendar) == nil)
    }

    @Test
    func `lasts until reset when the remaining window is idle`() throws {
        var weights = [Double](repeating: 0, count: CodexUsagePatternModel.cellCount)
        for cell in 0..<(3 * 24) {
            weights[cell] = 1
        }
        let model = try #require(CodexUsagePatternModel(weights: weights, calendar: Self.calendar))
        let sunday = Self.monday.addingTimeInterval(-86400)
        let window = Self.window(used: 50, resetsAt: sunday.addingTimeInterval(7 * 86400))
        let pace = try #require(model.usagePace(window: window, now: sunday.addingTimeInterval(4 * 86400)))
        #expect(pace.willLastToReset)
        #expect(pace.etaSeconds == nil)
    }
}
