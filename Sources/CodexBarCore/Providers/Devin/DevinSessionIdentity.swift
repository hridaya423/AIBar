#if os(macOS)
import CryptoKit
import Foundation

public enum DevinSessionIdentity {
    public static let externalIdentifierPrefix = "devin:"

    /// Org-first identity: the Devin quota API is org-scoped, so two profiles logged
    /// into the same org show identical usage and must collapse into one account.
    public static func externalIdentifier(for session: DevinSessionImporter.SessionInfo) -> String {
        if let internalOrganizationID = session.internalOrganizationID {
            return "devin:org:\(internalOrganizationID)"
        }
        if let organization = session.organization {
            return "devin:org:\(organization)"
        }
        if let userID = session.userID {
            return "devin:user:\(userID)"
        }
        let digest = SHA256.hash(data: Data(session.accessToken.utf8))
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "devin:tok:\(hex)"
    }

    /// Value stored on `ProviderTokenAccount.organizationID`; the `organizations/`
    /// form enables the `x-cog-org-id` fast path in the fetcher.
    public static func organizationID(for session: DevinSessionImporter.SessionInfo) -> String? {
        if let internalOrganizationID = session.internalOrganizationID {
            return "organizations/\(internalOrganizationID)"
        }
        return session.organization
    }

    /// Whether a session can satisfy a fetch for the given normalized organization
    /// (`org/<slug>` or `organizations/<id>`).
    public static func matches(
        session: DevinSessionImporter.SessionInfo,
        normalizedOrganization: String?) -> Bool
    {
        guard let normalizedOrganization else { return true }
        if session.organization == normalizedOrganization {
            return true
        }
        if normalizedOrganization.hasPrefix("organizations/"),
           let internalOrganizationID = session.internalOrganizationID
        {
            return internalOrganizationID == String(normalizedOrganization.dropFirst("organizations/".count))
        }
        return false
    }
}
#endif
