import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
@MainActor
struct KeychainAutoImportExemptionTests {
    @Test(arguments: [UsageProvider.devin, .windsurf])
    func `exempt providers keep automatic cookie source when keychain access is disabled`(provider: UsageProvider) {
        let settings = Self.makeSettingsStore(suite: "KeychainAutoImportExemptionTests-\(provider.rawValue)")

        #expect(settings.resolvedCookieSource(provider: provider, fallback: .auto) == .auto)
        #expect(!settings.keychainBlocksAutoImport(for: provider))
    }

    @Test
    func `other providers are forced to manual when keychain access is disabled`() {
        let settings = Self.makeSettingsStore(suite: "KeychainAutoImportExemptionTests-cursor")

        #expect(settings.resolvedCookieSource(provider: .cursor, fallback: .auto) == .manual)
        #expect(settings.resolvedCookieSource(provider: .cursor, fallback: .off) == .off)
        #expect(settings.keychainBlocksAutoImport(for: .cursor))
    }

    private static func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "debugDisableKeychainAccess")
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
    }
}
