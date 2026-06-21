import Foundation

public struct MoonshotSettingsReader: Sendable {
    public static let apiKeyEnvironmentKeys = [
        "MOONSHOT_API_KEY",
        "MOONSHOT_KEY",
    ]
    public static let regionEnvironmentKey = "MOONSHOT_REGION"

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        ProviderSettingsReaderSupport.firstValue(keys: self.apiKeyEnvironmentKeys, environment: environment)
    }

    public static func region(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> MoonshotRegion
    {
        guard let raw = environment[self.regionEnvironmentKey] else {
            return .international
        }
        let cleaned = ProviderSettingsReaderSupport.cleaned(raw)?.lowercased() ?? ""
        return MoonshotRegion(rawValue: cleaned) ?? .international
    }
}
