import CodexBarCore
import Foundation

enum UsagePaceText {
    struct WeeklyDetail {
        let leftLabel: String
        let rightLabel: String?
        let expectedUsedPercent: Double
        let stage: UsagePace.Stage
    }

    private enum DetailContext {
        case session
        case weekly
    }

    static func weeklySummary(pace: UsagePace, now: Date = .init()) -> String {
        let detail = self.weeklyDetail(pace: pace, now: now)
        if let rightLabel = detail.rightLabel {
            return L("Pace: %@ · %@", detail.leftLabel, rightLabel)
        }
        return L("Pace: %@", detail.leftLabel)
    }

    static func weeklyDetail(pace: UsagePace, now: Date = .init()) -> WeeklyDetail {
        WeeklyDetail(
            leftLabel: self.detailLeftLabel(for: pace),
            rightLabel: self.detailRightLabel(for: pace, context: .weekly, now: now),
            expectedUsedPercent: pace.expectedUsedPercent,
            stage: pace.stage)
    }

    private static func detailLeftLabel(for pace: UsagePace) -> String {
        let deltaValue = Int(abs(pace.deltaPercent).rounded())
        switch pace.stage {
        case .onTrack:
            return L("On pace")
        case .slightlyAhead, .ahead, .farAhead:
            return L("%d%% in deficit", deltaValue)
        case .slightlyBehind, .behind, .farBehind:
            return L("%d%% in reserve", deltaValue)
        }
    }

    private static func detailRightLabel(for pace: UsagePace, context: DetailContext, now: Date) -> String? {
        let etaLabel: String?
        if pace.willLastToReset {
            etaLabel = L("Lasts until reset")
        } else if let etaSeconds = pace.etaSeconds {
            if self.isTomorrow(etaSeconds: etaSeconds, now: now) {
                etaLabel = context == .session ? L("Projected empty tomorrow") : L("Runs out tomorrow")
            } else {
                let etaText = Self.durationText(seconds: etaSeconds, now: now)
                if context == .session {
                    etaLabel = etaText == "now" ? L("Projected empty now") : L("Projected empty in %@", etaText)
                } else {
                    etaLabel = etaText == "now" ? L("Runs out now") : L("Runs out in %@", etaText)
                }
            }
        } else {
            etaLabel = nil
        }

        guard let runOutProbability = pace.runOutProbability else { return etaLabel }
        let roundedRisk = self.roundedRiskPercent(runOutProbability)
        // A rounded 0% risk does not add information and makes the reassuring outcome read as
        // contradictory ("Lasts until reset · ≈ 0% run-out risk"). Keep the pace line focused.
        guard roundedRisk > 0 else { return etaLabel }
        let riskLabel = L("≈ %d%% run-out risk", roundedRisk)
        if pace.willLastToReset {
            return riskLabel
        }
        if let etaLabel {
            return L("%@ · %@", etaLabel, riskLabel)
        }
        return riskLabel
    }

    private static func durationText(seconds: TimeInterval, now: Date) -> String {
        let date = now.addingTimeInterval(seconds)
        let countdown = UsageFormatter.resetCountdownDescription(from: date, now: now)
        if countdown == "now" { return "now" }
        if countdown.hasPrefix("in ") { return String(countdown.dropFirst(3)) }
        return countdown
    }

    private static func isTomorrow(etaSeconds: TimeInterval, now: Date) -> Bool {
        guard etaSeconds > 0,
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)
        else { return false }
        return Calendar.current.isDate(now.addingTimeInterval(etaSeconds), inSameDayAs: tomorrow)
    }

    private static func roundedRiskPercent(_ probability: Double) -> Int {
        let percent = probability.clamped(to: 0...1) * 100
        let rounded = (percent / 5).rounded() * 5
        return Int(rounded)
    }

    static func sessionPace(provider: UsageProvider, window: RateWindow, now: Date) -> UsagePace? {
        guard provider == .codex || provider == .claude || provider == .ollama else { return nil }
        if provider == .ollama, window.windowMinutes == nil { return nil }
        return UsagePace.weekly(window: window, now: now, defaultWindowMinutes: 300)
    }

    static func sessionDetail(provider: UsageProvider, window: RateWindow, now: Date = .init()) -> WeeklyDetail? {
        guard let pace = sessionPace(provider: provider, window: window, now: now) else { return nil }
        return Self.sessionDetail(pace: pace, now: now)
    }

    /// Builds the session detail from an already-resolved pace (e.g. the weekday×hour pattern pace).
    static func sessionDetail(pace: UsagePace, now: Date = .init()) -> WeeklyDetail {
        WeeklyDetail(
            leftLabel: self.detailLeftLabel(for: pace),
            rightLabel: self.detailRightLabel(for: pace, context: .session, now: now),
            expectedUsedPercent: pace.expectedUsedPercent,
            stage: pace.stage)
    }

    static func sessionSummary(provider: UsageProvider, window: RateWindow, now: Date = .init()) -> String? {
        guard let detail = sessionDetail(provider: provider, window: window, now: now) else { return nil }
        if let rightLabel = detail.rightLabel {
            return L("Pace: %@ · %@", detail.leftLabel, rightLabel)
        }
        return L("Pace: %@", detail.leftLabel)
    }
}
