import Foundation

public struct WarpSettingsReader: Sendable {
    public static let apiKeyEnvironmentKeys = [
        "WARP_API_KEY",
        "WARP_TOKEN",
    ]

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        ProviderSettingsReaderSupport.firstValue(keys: self.apiKeyEnvironmentKeys, environment: environment)
    }
}
