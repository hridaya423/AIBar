import CodexBarCore
import Foundation

/// Keeps Devin token accounts in sync with the Devin sessions discovered in
/// Chrome profile local storage. Runs before each Devin refresh: matched
/// sessions refresh the stored token in place, new sessions append accounts,
/// vanished sessions drop their imported accounts, and manually pasted
/// accounts are never touched.
enum DevinAccountSync {
    @MainActor
    static func syncFromBrowserSessions(
        settings: SettingsStore,
        browserDetection: BrowserDetection) async
    {
        // LevelDB reads stay off-main.
        let sessions = await withTaskGroup(
            of: [DevinSessionImporter.SessionInfo].self,
            returning: [DevinSessionImporter.SessionInfo].self)
        { group in
            group.addTask {
                DevinSessionImporter.importSessions(browserDetection: browserDetection)
            }
            return await group.next() ?? []
        }
        // An empty scan can mean a transient read failure; never drop accounts on it.
        guard !sessions.isEmpty else { return }
        self.applyReconciliation(sessions: sessions, settings: settings)
    }

    @MainActor
    static func applyReconciliation(
        sessions: [DevinSessionImporter.SessionInfo],
        settings: SettingsStore)
    {
        let existing = settings.tokenAccountsData(for: .devin)
        let hidden = Set(settings.providerConfig(for: .devin)?.hiddenTokenAccountExternalIdentifiers ?? [])
        let updated = self.reconciledAccountData(
            sessions: sessions,
            existing: existing,
            hiddenExternalIdentifiers: hidden)
        guard updated != existing else { return }
        settings.updateProviderConfig(provider: .devin) { entry in
            entry.tokenAccounts = updated
        }
        CodexBarLog.logger(LogCategories.tokenAccounts).info(
            "Devin browser sessions reconciled",
            metadata: ["count": "\(updated?.accounts.count ?? 0)"])
    }

    static func reconciledAccountData(
        sessions: [DevinSessionImporter.SessionInfo],
        existing: ProviderTokenAccountData?,
        hiddenExternalIdentifiers: Set<String>,
        now: Date = Date()) -> ProviderTokenAccountData?
    {
        let existingAccounts = existing?.accounts ?? []
        var matchedAccountIDs: Set<UUID> = []
        var seenExternalIdentifiers: Set<String> = []
        var reconciled: [ProviderTokenAccount] = []

        for session in sessions {
            let externalIdentifier = DevinSessionIdentity.externalIdentifier(for: session)
            guard !hiddenExternalIdentifiers.contains(externalIdentifier),
                  !seenExternalIdentifiers.contains(externalIdentifier)
            else { continue }
            seenExternalIdentifiers.insert(externalIdentifier)
            let organizationID = DevinSessionIdentity.organizationID(for: session)

            let match = existingAccounts.first {
                $0.externalIdentifier == externalIdentifier && !matchedAccountIDs.contains($0.id)
            } ?? existingAccounts.first {
                $0.token == session.accessToken && !matchedAccountIDs.contains($0.id)
            }
            if let match {
                matchedAccountIDs.insert(match.id)
                let imported = self.isImportedAccount(match)
                reconciled.append(ProviderTokenAccount(
                    id: match.id,
                    label: imported ? session.sourceLabel : match.label,
                    token: session.accessToken,
                    addedAt: match.addedAt,
                    lastUsed: match.lastUsed,
                    externalIdentifier: externalIdentifier,
                    organizationID: organizationID))
            } else {
                reconciled.append(ProviderTokenAccount(
                    id: UUID(),
                    label: session.sourceLabel,
                    token: session.accessToken,
                    addedAt: now.timeIntervalSince1970,
                    lastUsed: nil,
                    externalIdentifier: externalIdentifier,
                    organizationID: organizationID))
            }
        }

        for account in existingAccounts where !matchedAccountIDs.contains(account.id) {
            guard !self.isImportedAccount(account) else { continue }
            reconciled.append(account)
        }

        guard !reconciled.isEmpty else { return nil }
        let activeID: UUID? = existing.flatMap { data in
            data.accounts.isEmpty ? nil : data.accounts[data.clampedActiveIndex()].id
        }
        let activeIndex = activeID
            .flatMap { id in reconciled.firstIndex(where: { $0.id == id }) }
            ?? min(existing?.clampedActiveIndex() ?? 0, reconciled.count - 1)
        return ProviderTokenAccountData(
            version: existing?.version ?? 1,
            accounts: reconciled,
            activeIndex: activeIndex)
    }

    private static func isImportedAccount(_ account: ProviderTokenAccount) -> Bool {
        account.externalIdentifier?.hasPrefix(DevinSessionIdentity.externalIdentifierPrefix) == true
    }
}
