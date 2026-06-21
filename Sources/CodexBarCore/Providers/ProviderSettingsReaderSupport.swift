import Foundation

enum ProviderSettingsReaderSupport {
    static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value = String(value.dropFirst().dropLast())
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func firstValue(keys: [String], environment: [String: String]) -> String? {
        for key in keys {
            if let value = self.cleaned(environment[key]) {
                return value
            }
        }
        return nil
    }

    static func normalizedHTTPSURL(
        environmentKey: String,
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL?
    {
        guard let raw = self.cleaned(environment[environmentKey]) else { return nil }
        return ProviderEndpointOverrideValidator.normalizedHTTPSURL(from: raw)
    }

    static func hasInvalidEndpointOverride(
        environmentKey: String,
        environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool
    {
        guard let raw = self.cleaned(environment[environmentKey]) else { return false }
        return ProviderEndpointOverrideValidator.normalizedHTTPSURL(from: raw) == nil
    }
}
