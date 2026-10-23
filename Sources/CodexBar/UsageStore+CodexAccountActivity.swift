import CodexBarCore
import Foundation

extension UsageStore {
    func updateCodexAccountActivity(now: Date = Date()) {
        var next = self.codexAccountActivity
        next.update(
            sessionUsedPercents: self.codexAccountSessionWindows().mapValues(\.usedPercent),
            now: now)
        if next != self.codexAccountActivity { self.codexAccountActivity = next }
    }

    func codexActiveAccountMenuBarSnapshotOverride(
        for instanceID: ProviderInstanceID,
        now: Date = Date()) -> UsageSnapshot?
    {
        // Provider-specific by design: the icon follows whichever Codex account was used last.
        guard instanceID == UsageProvider.codex.instanceID, self.codexAccountSnapshots.count > 1 else { return nil }
        let focusedID = self.codexAccountActivity.mostRecentlyActiveID(now: now)
            ?? CodexAccountActivity.soonestResetWhenAllExhausted(sessions: self.codexAccountSessionWindows())
        return self.codexAccountSnapshots.first { $0.id == focusedID }?.snapshot
    }

    private func codexAccountSessionWindows() -> [String: RateWindow] {
        // Provider-specific by design: Codex account rows are classified by Codex's own session lane.
        let presentation = ProviderDescriptorRegistry.descriptor(for: .codex).presentation
        return self.codexAccountSnapshots.reduce(into: [:]) { windows, entry in
            if let snapshot = entry.snapshot, let session = presentation.semanticWindows(snapshot: snapshot).session {
                windows[entry.id] = session
            }
        }
    }
}
