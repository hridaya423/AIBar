import Foundation

public struct ZaiSettingsReader: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.zaiSettings)

    public static let apiTokenKey = "Z_AI_API_KEY"
    public static let apiHostKey = "Z_AI_API_HOST"
    public static let quotaURLKey = "Z_AI_QUOTA_URL"

    public static func apiToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        ProviderSettingsReaderSupport.cleaned(environment[self.apiTokenKey])
    }

    public static func apiHost(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        ProviderSettingsReaderSupport.cleaned(environment[self.apiHostKey])
    }

    public static func quotaURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL?
    {
        guard let raw = ProviderSettingsReaderSupport.cleaned(environment[self.quotaURLKey]) else { return nil }
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(raw)")
    }

    static func cleaned(_ raw: String?) -> String? {
        ProviderSettingsReaderSupport.cleaned(raw)
    }
}

public enum ZaiSettingsError: LocalizedError, Sendable {
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "z.ai API token not found. Set apiKey in ~/.codexbar/config.json or Z_AI_API_KEY."
        }
    }
}
