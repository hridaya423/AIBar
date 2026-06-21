import Foundation

public struct DeepSeekSettingsReader: Sendable {
    public static let apiKeyEnvironmentKey = "DEEPSEEK_API_KEY"
    public static let apiKeyEnvironmentKeys = [Self.apiKeyEnvironmentKey, "DEEPSEEK_KEY"]

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        ProviderSettingsReaderSupport.firstValue(keys: self.apiKeyEnvironmentKeys, environment: environment)
    }
}
