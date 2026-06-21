import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    private static let codexUsagePatternRebuildInterval: TimeInterval = 60 * 60

    func refreshCodexUsagePatternIfNeeded(now: Date = Date()) {
        if let built = self.codexUsagePatternBuiltAt,
           now.timeIntervalSince(built) < Self.codexUsagePatternRebuildInterval
        {
            return
        }
        self.codexUsagePatternBuiltAt = now
        let source = CodexUsagePatternSource()
        Task { [weak self] in
            let model = await Task.detached(priority: .utility) { source.buildModel(now: now) }.value
            self?.codexUsagePattern = model.isUsable ? model : nil
        }
    }

    func codexUsagePatternPace(window: RateWindow, now: Date) -> UsagePace? {
        self.codexUsagePattern?.usagePace(window: window, now: now)
    }

    func codexSessionPace(provider: UsageProvider, window: RateWindow, now: Date = Date()) -> UsagePace? {
        if provider == .codex, let pace = self.codexUsagePatternPace(window: window, now: now) {
            return pace
        }
        return UsagePaceText.sessionPace(provider: provider, window: window, now: now)
    }
}
