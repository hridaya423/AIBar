import CodexBarCore
import Foundation

enum MenuBarDisplayText {
    static func percentText(window: RateWindow?, showUsed: Bool) -> String? {
        guard let window else { return nil }
        let percent = showUsed ? window.usedPercent : window.remainingPercent
        return UsageFormatter.percentString(percent)
    }

    static func paceText(pace: UsagePace?) -> String? {
        guard let pace else { return nil }
        let deltaValue = Int(abs(pace.deltaPercent).rounded())
        let sign = pace.deltaPercent >= 0 ? "+" : "-"
        return "\(sign)\(deltaValue)%"
    }

    static func codexCombinedPercentText(
        sessionWindow: RateWindow?,
        weeklyWindow: RateWindow?,
        showUsed: Bool)
        -> String?
    {
        var parts: [String] = []
        if let sessionWindow,
           let session = self.percentText(window: sessionWindow, showUsed: showUsed)
        {
            parts.append("\(self.codexSessionLabel(window: sessionWindow)) \(session)")
        }
        if let weekly = self.percentText(window: weeklyWindow, showUsed: showUsed) {
            parts.append("W \(weekly)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Compact reset countdown showing just the largest unit, *rounded* to the nearest of that unit
    /// (so 2h57m shows "3h", not "2h"), carrying at boundaries (23h40m → "1d"). Returns nil when the
    /// window has no future reset time.
    static func shortResetText(window: RateWindow?, now: Date) -> String? {
        guard let resetsAt = window?.resetsAt else { return nil }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        if seconds >= 23.5 * 3600 {
            return "\(max(1, Int((seconds / 86400).rounded())))d"
        }
        if seconds >= 59.5 * 60 {
            return "\(max(1, Int((seconds / 3600).rounded())))h"
        }
        return "\(max(1, Int((seconds / 60).rounded())))m"
    }

    /// Codex menu bar text combining both windows as remaining % + short reset countdown, e.g.
    /// "42% 4h · W 78% 3d". The session window has no label; the weekly window is prefixed "W".
    static func codexCombinedPercentAndResetText(
        sessionWindow: RateWindow?,
        weeklyWindow: RateWindow?,
        showUsed: Bool,
        now: Date)
        -> String?
    {
        var parts: [String] = []
        if let sessionWindow, let percent = self.percentText(window: sessionWindow, showUsed: showUsed) {
            if let reset = self.shortResetText(window: sessionWindow, now: now) {
                parts.append("\(percent) \(reset)")
            } else {
                parts.append(percent)
            }
        }
        if let weeklyWindow, let percent = self.percentText(window: weeklyWindow, showUsed: showUsed) {
            if let reset = self.shortResetText(window: weeklyWindow, now: now) {
                parts.append("W \(percent) \(reset)")
            } else {
                parts.append("W \(percent)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func codexSessionLabel(window: RateWindow) -> String {
        guard let minutes = window.windowMinutes, minutes > 0 else { return "S" }
        guard minutes.isMultiple(of: 60) else { return "\(minutes)m" }
        return "\(minutes / 60)h"
    }

    static func displayText(
        mode: MenuBarDisplayMode,
        percentWindow: RateWindow?,
        pace: UsagePace? = nil,
        showUsed: Bool,
        resetTimeDisplayStyle: ResetTimeDisplayStyle = .countdown,
        now: Date = .init()) -> String?
    {
        switch mode {
        case .percent:
            return self.percentText(window: percentWindow, showUsed: showUsed)
        case .percentAndReset:
            guard let percent = self.percentText(window: percentWindow, showUsed: showUsed) else { return nil }
            if let reset = self.shortResetText(window: percentWindow, now: now) {
                return "\(percent) \(reset)"
            }
            return percent
        case .pace:
            // Pace can be temporarily unavailable near a reset or when a provider omits window metadata.
            // Keep the selected quota visible instead of collapsing the status item to an icon-only state.
            return self.paceText(pace: pace)
                ?? self.percentText(window: percentWindow, showUsed: showUsed)
        case .both:
            guard let percent = percentText(window: percentWindow, showUsed: showUsed) else { return nil }
            // Fall back to percent-only when pace is unavailable (e.g. Copilot)
            guard let paceText = Self.paceText(pace: pace) else { return percent }
            return "\(percent) · \(paceText)"
        case .resetTime:
            guard let percentWindow else { return nil }
            if let resetsAt = percentWindow.resetsAt {
                let description = switch resetTimeDisplayStyle {
                case .countdown:
                    UsageFormatter.resetCountdownDescription(from: resetsAt, now: now)
                case .absolute:
                    UsageFormatter.resetDescription(from: resetsAt, now: now)
                }
                return "↻ \(description)"
            }
            if let resetDescription = self.resetMetadataText(percentWindow.resetDescription) {
                return "↻ \(resetDescription)"
            }
            return self.percentText(window: percentWindow, showUsed: showUsed)
        }
    }

    private static func resetMetadataText(_ description: String?) -> String? {
        guard let description else { return nil }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // RateWindow.resetDescription predates provider-specific detail fields and is also used for
        // request/token summaries. Only trust phrases that explicitly describe reset timing.
        let normalized = trimmed.lowercased()
        let resetPrefixes = [
            "reset ", "resets ", "in ", "today ", "today,", "tomorrow ", "tomorrow,", "next ",
            "expire ", "expires ", "refill ", "refills ",
        ]
        let exactResetDescriptions = ["today", "tomorrow", "expired", "now", "soon"]
        return exactResetDescriptions.contains(normalized) || resetPrefixes.contains(where: normalized.hasPrefix)
            ? trimmed
            : nil
    }
}
