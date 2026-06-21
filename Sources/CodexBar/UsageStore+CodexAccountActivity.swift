import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    private static let codexActiveAccountWindow: TimeInterval = 2 * 60 * 60

    func updateCodexAccountActivity(now: Date = Date()) {
        let samples = self.codexAccountSnapshots.map { entry in
            CodexAccountActivityState.Sample(
                id: entry.id,
                sessionUsedPercent: entry.snapshot?.primary?.usedPercent)
        }
        self.codexAccountActivity.update(samples: samples, now: now)
    }

    func smartActiveCodexSnapshot(now: Date = Date()) -> UsageSnapshot? {
        guard self.codexAccountSnapshots.count > 1 else { return nil }

        if let activeID = self.codexAccountActivity.mostActiveAccountID(
            now: now,
            within: Self.codexActiveAccountWindow),
            let snapshot = self.codexAccountSnapshots.first(where: { $0.id == activeID })?.snapshot
        {
            return snapshot
        }

        let sessions = self.codexAccountSnapshots.compactMap { entry -> (id: String, window: RateWindow)? in
            guard let session = entry.snapshot?.primary else { return nil }
            return (id: entry.id, window: session)
        }
        if let nearestID = CodexAccountActivityState.nearestResetAccountIDWhenAllExhausted(sessions: sessions) {
            return self.codexAccountSnapshots.first { $0.id == nearestID }?.snapshot
        }

        return nil
    }

    func menuBarIconSnapshot(for provider: UsageProvider, now: Date = Date()) -> UsageSnapshot? {
        if provider == .codex, let active = self.smartActiveCodexSnapshot(now: now) {
            return active
        }
        return self.snapshot(for: provider)
    }
}
