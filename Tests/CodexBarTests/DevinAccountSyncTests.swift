import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

#if os(macOS)
@Suite(.serialized)
@MainActor
struct DevinAccountSyncTests {
    private static func session(
        token: String,
        organization: String? = nil,
        internalOrganizationID: String? = nil,
        userID: String? = nil,
        sourceLabel: String = "Chrome Default") -> DevinSessionImporter.SessionInfo
    {
        DevinSessionImporter.SessionInfo(
            accessToken: token,
            organization: organization,
            internalOrganizationID: internalOrganizationID,
            userID: userID,
            sourceLabel: sourceLabel)
    }

    private static func account(
        label: String = "account",
        token: String,
        externalIdentifier: String? = nil,
        organizationID: String? = nil) -> ProviderTokenAccount
    {
        ProviderTokenAccount(
            id: UUID(),
            label: label,
            token: token,
            addedAt: 1000,
            lastUsed: nil,
            externalIdentifier: externalIdentifier,
            organizationID: organizationID)
    }

    @Test
    func `new browser sessions become imported accounts`() {
        let sessions = [
            Self.session(
                token: "token-a",
                organization: "org/alpha",
                internalOrganizationID: "org_alpha123",
                sourceLabel: "Google Chrome Default"),
            Self.session(
                token: "token-b",
                organization: "org/beta",
                internalOrganizationID: "org_beta4567",
                sourceLabel: "Google Chrome Profile 1"),
        ]

        let data = DevinAccountSync.reconciledAccountData(
            sessions: sessions,
            existing: nil,
            hiddenExternalIdentifiers: [])

        #expect(data?.accounts.count == 2)
        #expect(data?.accounts[0].token == "token-a")
        #expect(data?.accounts[0].label == "Google Chrome Default")
        #expect(data?.accounts[0].externalIdentifier == "devin:org:org_alpha123")
        #expect(data?.accounts[0].organizationID == "organizations/org_alpha123")
        #expect(data?.accounts[1].token == "token-b")
        #expect(data?.activeIndex == 0)
    }

    @Test
    func `rotated token refreshes the matched account in place`() {
        let existing = ProviderTokenAccountData(
            version: 1,
            accounts: [
                Self.account(
                    label: "Google Chrome Default",
                    token: "old-token",
                    externalIdentifier: "devin:org:org_alpha123",
                    organizationID: "organizations/org_alpha123"),
            ],
            activeIndex: 0)
        let existingID = existing.accounts[0].id
        let sessions = [
            Self.session(
                token: "fresh-token",
                organization: "org/alpha",
                internalOrganizationID: "org_alpha123",
                sourceLabel: "Google Chrome Default"),
        ]

        let data = DevinAccountSync.reconciledAccountData(
            sessions: sessions,
            existing: existing,
            hiddenExternalIdentifiers: [])

        #expect(data?.accounts.count == 1)
        #expect(data?.accounts[0].id == existingID)
        #expect(data?.accounts[0].token == "fresh-token")
        #expect(data?.accounts[0].addedAt == 1000)
    }

    @Test
    func `vanished session drops its imported account but keeps manual ones`() throws {
        let imported = Self.account(
            label: "Google Chrome Default",
            token: "gone-token",
            externalIdentifier: "devin:org:org_gone0000",
            organizationID: "organizations/org_gone0000")
        let manual = Self.account(label: "Pasted", token: "manual-token")
        let existing = ProviderTokenAccountData(
            version: 1,
            accounts: [imported, manual],
            activeIndex: 0)
        let sessions = [
            Self.session(
                token: "token-b",
                organization: "org/beta",
                internalOrganizationID: "org_beta4567",
                sourceLabel: "Google Chrome Profile 1"),
        ]

        let data = DevinAccountSync.reconciledAccountData(
            sessions: sessions,
            existing: existing,
            hiddenExternalIdentifiers: [])

        let accounts = try #require(data?.accounts)
        #expect(accounts.count == 2)
        #expect(accounts.map(\.token) == ["token-b", "manual-token"])
        #expect(!accounts.contains(where: { $0.id == imported.id }))
        #expect(accounts[1].id == manual.id)
    }

    @Test
    func `manual account matching a session token is absorbed and keeps its label`() {
        let manual = Self.account(label: "My account", token: "shared-token")
        let existing = ProviderTokenAccountData(
            version: 1,
            accounts: [manual],
            activeIndex: 0)
        let sessions = [
            Self.session(
                token: "shared-token",
                organization: "org/alpha",
                internalOrganizationID: "org_alpha123",
                sourceLabel: "Google Chrome Default"),
        ]

        let data = DevinAccountSync.reconciledAccountData(
            sessions: sessions,
            existing: existing,
            hiddenExternalIdentifiers: [])

        #expect(data?.accounts.count == 1)
        #expect(data?.accounts[0].id == manual.id)
        #expect(data?.accounts[0].label == "My account")
        #expect(data?.accounts[0].externalIdentifier == "devin:org:org_alpha123")
    }

    @Test
    func `hidden external identifiers are not re-added`() {
        let sessions = [
            Self.session(
                token: "token-a",
                organization: "org/alpha",
                internalOrganizationID: "org_alpha123",
                sourceLabel: "Google Chrome Default"),
            Self.session(
                token: "token-b",
                organization: "org/beta",
                internalOrganizationID: "org_beta4567",
                sourceLabel: "Google Chrome Profile 1"),
        ]

        let data = DevinAccountSync.reconciledAccountData(
            sessions: sessions,
            existing: nil,
            hiddenExternalIdentifiers: ["devin:org:org_alpha123"])

        #expect(data?.accounts.count == 1)
        #expect(data?.accounts[0].token == "token-b")
    }

    @Test
    func `two sessions sharing an org collapse into one account`() {
        let sessions = [
            Self.session(
                token: "token-a",
                organization: "org/alpha",
                internalOrganizationID: "org_alpha123",
                sourceLabel: "Google Chrome Default"),
            Self.session(
                token: "token-b",
                organization: "org/alpha",
                internalOrganizationID: "org_alpha123",
                sourceLabel: "Google Chrome Profile 1"),
        ]

        let data = DevinAccountSync.reconciledAccountData(
            sessions: sessions,
            existing: nil,
            hiddenExternalIdentifiers: [])

        #expect(data?.accounts.count == 1)
    }

    @Test
    func `active selection survives reordering by account id`() throws {
        let importedA = Self.account(
            label: "A",
            token: "token-a",
            externalIdentifier: "devin:org:org_alpha123")
        let manual = Self.account(label: "Manual", token: "manual-token")
        let existing = ProviderTokenAccountData(
            version: 1,
            accounts: [importedA, manual],
            activeIndex: 1)
        let sessions = [
            Self.session(
                token: "token-b",
                organization: "org/beta",
                internalOrganizationID: "org_beta4567",
                sourceLabel: "Google Chrome Profile 1"),
            Self.session(
                token: "token-a",
                organization: "org/alpha",
                internalOrganizationID: "org_alpha123",
                sourceLabel: "Google Chrome Default"),
        ]

        let data = try #require(DevinAccountSync.reconciledAccountData(
            sessions: sessions,
            existing: existing,
            hiddenExternalIdentifiers: []))

        // Active account was `manual`; it must still be active after reconcile.
        #expect(data.accounts.count == 3)
        #expect(data.accounts[data.activeIndex].id == manual.id)
    }

    @Test
    func `devin settings snapshot prefers the selected account organization`() {
        let settings = testSettingsStore(suiteName: "DevinAccountSyncTests-snapshot-org")
        settings.devinOrganization = "org/global-org"
        settings.addTokenAccount(
            provider: .devin,
            label: "Account 1",
            token: "account-token",
            externalIdentifier: "devin:org:org_alpha123",
            organizationID: "organizations/org_alpha123")

        let snapshot = settings.devinSettingsSnapshot(tokenOverride: nil)

        #expect(snapshot.organization == "organizations/org_alpha123")
    }

    @Test
    func `devin settings snapshot falls back to global organization`() {
        let settings = testSettingsStore(suiteName: "DevinAccountSyncTests-snapshot-fallback")
        settings.devinOrganization = "org/global-org"
        settings.addTokenAccount(
            provider: .devin,
            label: "Account 1",
            token: "account-token")

        let snapshot = settings.devinSettingsSnapshot(tokenOverride: nil)

        #expect(snapshot.organization == "org/global-org")
    }

    @Test
    func `removing an imported account writes a tombstone`() throws {
        let settings = testSettingsStore(suiteName: "DevinAccountSyncTests-tombstone")
        settings.addTokenAccount(
            provider: .devin,
            label: "Account 1",
            token: "account-token",
            externalIdentifier: "devin:org:org_alpha123")
        let accountID = try #require(settings.tokenAccounts(for: .devin).first).id

        settings.removeTokenAccount(provider: .devin, accountID: accountID)

        let hidden = settings.providerConfig(for: .devin)?.hiddenTokenAccountExternalIdentifiers
        #expect(hidden == ["devin:org:org_alpha123"])
        #expect(settings.tokenAccounts(for: .devin).isEmpty)
    }

    @Test
    func `devin registers token account support`() {
        #expect(TokenAccountSupportCatalog.support(for: .devin) != nil)
    }

    @Test
    func `devin token account injects bearer token and scrubs related env in CLI`() throws {
        let config = CodexBarConfig(providers: [ProviderConfig(id: .devin)])
        let tokenContext = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: config,
            verbose: false)
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "Account 1",
            token: "account-token",
            addedAt: 0,
            lastUsed: nil,
            organizationID: "organizations/org_alpha123")

        let env = tokenContext.environment(
            base: [
                "DEVIN_BEARER_TOKEN": "ambient-token",
                "DEVIN_AUTHORIZATION": "ambient-authorization",
                "DEVIN_ORGANIZATION": "org/ambient",
                "DEVIN_ORG": "org/ambient",
            ],
            provider: .devin,
            account: account)

        #expect(env["DEVIN_BEARER_TOKEN"] == "account-token")
        #expect(env["DEVIN_AUTHORIZATION"] == nil)
        #expect(env["DEVIN_ORGANIZATION"] == nil)
        #expect(env["DEVIN_ORG"] == nil)
    }

    @Test
    func `devin CLI settings snapshot carries the selected account organization`() throws {
        let accounts = ProviderTokenAccountData(
            version: 1,
            accounts: [
                ProviderTokenAccount(
                    id: UUID(),
                    label: "Profile 1",
                    token: "account-token",
                    addedAt: 0,
                    lastUsed: nil,
                    externalIdentifier: "devin:org:org_alpha123",
                    organizationID: "organizations/org_alpha123"),
            ],
            activeIndex: 0)
        let config = CodexBarConfig(
            providers: [
                ProviderConfig(
                    id: .devin,
                    workspaceID: "org/global-org",
                    tokenAccounts: accounts),
            ])
        let tokenContext = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: config,
            verbose: false)
        let account = try #require(tokenContext.resolvedAccounts(for: .devin).first)

        let snapshot = try #require(tokenContext.settingsSnapshot(for: .devin, account: account))
        let devinSettings = try #require(snapshot.devin)

        #expect(devinSettings.organization == "organizations/org_alpha123")
        #expect(devinSettings.cookieSource == .auto)
    }
}
#endif
