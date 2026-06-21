import Foundation

public struct DoubaoSettingsReader: Sendable {
    public static let apiKeyEnvironmentKeys = [
        "ARK_API_KEY",
        "VOLCENGINE_API_KEY",
        "DOUBAO_API_KEY",
    ]

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        ProviderSettingsReaderSupport.firstValue(keys: self.apiKeyEnvironmentKeys, environment: environment)
    }
}
