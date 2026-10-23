import CodexBarCore
import Foundation

extension UsageStore {
    func codexSubscriptionValue(now: Date = Date()) -> SubscriptionValueEstimate? {
        // Provider-specific by design: the monthly value estimate scales Codex's local spend by its weekly quota.
        guard let snapshot = self.tokenSnapshot(for: .codex),
              let usage = self.snapshots[.codex],
              let weekly = ProviderDescriptorRegistry.descriptor(for: .codex)
                  .presentation.semanticWindows(snapshot: usage).weekly
        else { return nil }
        let calendar = self.settings.costUsageBucketCalendar
        let key = [
            "\(self.tokenSnapshotPublicationRevision(for: .codex))",
            "\(weekly.usedPercent)",
            "\(weekly.resetsAt?.timeIntervalSince1970 ?? 0)",
            "\(weekly.windowMinutes ?? 0)",
            "\(calendar.startOfDay(for: now).timeIntervalSince1970)",
        ].joined(separator: "|")
        if let memo = self.codexSubscriptionValueMemo, memo.key == key { return memo.value }
        let value = SubscriptionValueEstimate.make(
            snapshot: snapshot,
            weekly: weekly,
            now: now,
            calendar: calendar)
        self.codexSubscriptionValueMemo = (key, value)
        return value
    }
}
