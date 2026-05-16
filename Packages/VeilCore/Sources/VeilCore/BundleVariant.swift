import Foundation

/// Identifies which build variant of Veil owns a bundle.
///
/// Two variants ship from the same codebase, distinguished only by
/// `CFBundleDocumentTypes[0].LSHandlerRank` in the bundle's Info.plist.
/// "Alternate" marks the polite variant (Veil offers itself but does not
/// claim default-editor status); "Default" marks the takeover variant
/// (Veil registers as the default handler for its document types).
///
/// The variant is read from the bundle's own Info.plist rather than
/// stamped at compile time, so the App and the bundled CLI agree on
/// what they are without sharing build-time state.
public enum VeilBundleVariant {
    /// Suffix appended to user-visible version strings (with a leading
    /// space, ready to concatenate). Empty for the polite variant so
    /// the version line stays unchanged in the common case.
    public static func versionSuffix(from infoDictionary: [String: Any]?) -> String {
        guard isDefaultEditor(infoDictionary: infoDictionary) else { return "" }
        return " (default-editor)"
    }

    /// True when the bundle's first registered document type carries
    /// `LSHandlerRank = Default`. Missing or malformed plist entries are
    /// treated as the polite variant.
    private static func isDefaultEditor(infoDictionary: [String: Any]?) -> Bool {
        guard let documentTypes = infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]],
            let firstType = documentTypes.first,
            let rank = firstType["LSHandlerRank"] as? String
        else { return false }
        return rank == "Default"
    }
}
