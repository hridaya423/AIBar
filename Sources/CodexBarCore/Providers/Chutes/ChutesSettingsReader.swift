import Foundation

public struct ChutesSettingsReader: Sendable {
    public static let apiKeyEnvironmentKey = "CHUTES_API_KEY"
    public static let apiURLEnvironmentKey = "CHUTES_API_URL"

    public static func apiKey(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        ProviderSettingsReaderSupport.cleaned(environment[self.apiKeyEnvironmentKey])
    }

    public static func apiURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL
    {
        if let override = self.validAPIURL(environment: environment) {
            return override
        }
        return URL(string: "https://api.chutes.ai")!
    }

    public static func validateEndpointOverrides(
        environment: [String: String] = ProcessInfo.processInfo.environment) throws
    {
        guard ProviderSettingsReaderSupport.hasInvalidEndpointOverride(
            environmentKey: self.apiURLEnvironmentKey,
            environment: environment)
        else { return }
        throw ChutesSettingsError.invalidEndpointOverride(self.apiURLEnvironmentKey)
    }

    static func cleaned(_ raw: String?) -> String? {
        ProviderSettingsReaderSupport.cleaned(raw)
    }

    private static func validAPIURL(environment: [String: String]) -> URL? {
        ProviderSettingsReaderSupport.normalizedHTTPSURL(
            environmentKey: self.apiURLEnvironmentKey,
            environment: environment)
    }
}

public enum ChutesSettingsError: LocalizedError, Sendable, Equatable {
    case missingToken
    case invalidEndpointOverride(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "Chutes API key not found. Set apiKey in ~/.codexbar/config.json or CHUTES_API_KEY."
        case let .invalidEndpointOverride(key):
            "Chutes endpoint override \(key) must use HTTPS or a bare host."
        }
    }
}
