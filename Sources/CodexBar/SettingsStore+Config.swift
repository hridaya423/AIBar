import CodexBarCore
import Foundation

extension UsageProvider {
    /// Whether the `.auto` auth source needs macOS Keychain access (Chromium cookie
    /// decryption via "Chrome Safe Storage"). Devin/Windsurf read browser localStorage
    /// directly — plaintext, no Keychain — so the debug keychain kill-switch must not
    /// force them into manual-token mode.
    var autoCookieSourceRequiresKeychain: Bool {
        self != .devin && self != .windsurf
    }
}

extension SettingsStore {
    func providerConfig(for provider: UsageProvider) -> ProviderConfig? {
        self.configSnapshot.providerConfig(for: provider)
    }

    func quotaWarningConfig(for provider: UsageProvider) -> QuotaWarningConfig {
        self.configSnapshot.providerConfig(for: provider)?.quotaWarnings ?? QuotaWarningConfig()
    }

    func resolvedQuotaWarningThresholds(provider: UsageProvider, window: QuotaWarningWindow) -> [Int] {
        self.quotaWarningConfig(for: provider).thresholds(
            for: window,
            global: self.quotaWarningThresholds(window))
    }

    func quotaWarningEnabled(provider: UsageProvider, window: QuotaWarningWindow) -> Bool {
        self.quotaWarningConfig(for: provider).isEnabled(
            for: window,
            global: self.quotaWarningWindowEnabled(window))
    }

    func hasQuotaWarningOverride(provider: UsageProvider, window: QuotaWarningWindow) -> Bool {
        self.quotaWarningConfig(for: provider).hasOverride(for: window)
    }

    func setQuotaWarningThresholds(provider: UsageProvider, window: QuotaWarningWindow, thresholds: [Int]?) {
        self.updateProviderConfig(provider: provider) { entry in
            var config = entry.quotaWarnings ?? QuotaWarningConfig()
            switch window {
            case .session:
                var windowConfig = config.session ?? QuotaWarningWindowConfig()
                windowConfig.thresholds = thresholds.map(QuotaWarningThresholds.sanitized)
                config.session = windowConfig.hasOverride ? windowConfig : nil
            case .weekly:
                var windowConfig = config.weekly ?? QuotaWarningWindowConfig()
                windowConfig.thresholds = thresholds.map(QuotaWarningThresholds.sanitized)
                config.weekly = windowConfig.hasOverride ? windowConfig : nil
            }
            entry.quotaWarnings = config.isEmpty ? nil : config
        }
    }

    func setQuotaWarningOverride(
        provider: UsageProvider,
        window: QuotaWarningWindow,
        thresholds: [Int]?,
        enabled: Bool?)
    {
        self.updateProviderConfig(provider: provider) { entry in
            var config = entry.quotaWarnings ?? QuotaWarningConfig()
            switch window {
            case .session:
                var windowConfig = config.session ?? QuotaWarningWindowConfig()
                windowConfig.thresholds = thresholds.map(QuotaWarningThresholds.sanitized)
                windowConfig.enabled = enabled
                config.session = windowConfig.hasOverride ? windowConfig : nil
            case .weekly:
                var windowConfig = config.weekly ?? QuotaWarningWindowConfig()
                windowConfig.thresholds = thresholds.map(QuotaWarningThresholds.sanitized)
                windowConfig.enabled = enabled
                config.weekly = windowConfig.hasOverride ? windowConfig : nil
            }
            entry.quotaWarnings = config.isEmpty ? nil : config
        }
    }

    func setQuotaWarningWindowEnabled(provider: UsageProvider, window: QuotaWarningWindow, enabled: Bool?) {
        self.updateProviderConfig(provider: provider) { entry in
            var config = entry.quotaWarnings ?? QuotaWarningConfig()
            switch window {
            case .session:
                var windowConfig = config.session ?? QuotaWarningWindowConfig()
                windowConfig.enabled = enabled
                config.session = windowConfig.hasOverride ? windowConfig : nil
            case .weekly:
                var windowConfig = config.weekly ?? QuotaWarningWindowConfig()
                windowConfig.enabled = enabled
                config.weekly = windowConfig.hasOverride ? windowConfig : nil
            }
            entry.quotaWarnings = config.isEmpty ? nil : config
        }
    }

    var tokenAccountsByProvider: [UsageProvider: ProviderTokenAccountData] {
        get {
            Dictionary(uniqueKeysWithValues: self.configSnapshot.providers.compactMap { entry in
                guard let accounts = entry.tokenAccounts else { return nil }
                return (entry.id, accounts)
            })
        }
        set {
            self.updateProviderTokenAccounts(newValue)
        }
    }
}

extension SettingsStore {
    /// Effective "keychain blocked" state for a provider's `.auto` auth source: the debug
    /// toggle only applies when auto actually needs the Keychain.
    func keychainDisabled(for provider: UsageProvider) -> Bool {
        self.debugDisableKeychainAccess && provider.autoCookieSourceRequiresKeychain
    }

    func resolvedCookieSource(
        provider: UsageProvider,
        fallback: ProviderCookieSource) -> ProviderCookieSource
    {
        let source = self.configSnapshot.providerConfig(for: provider)?.cookieSource ?? fallback
        guard self.keychainDisabled(for: provider) else { return source }
        return source == .off ? .off : .manual
    }

    func logProviderModeChange(provider: UsageProvider, field: String, value: String) {
        CodexBarLog.logger(LogCategories.settings).info(
            "Provider mode updated",
            metadata: ["provider": provider.rawValue, "field": field, "value": value])
    }

    func logSecretUpdate(provider: UsageProvider, field: String, value: String) {
        var metadata = LogMetadata.secretSummary(value)
        metadata["provider"] = provider.rawValue
        metadata["field"] = field
        CodexBarLog.logger(LogCategories.settings).info(
            "Provider secret updated",
            metadata: metadata)
    }
}
