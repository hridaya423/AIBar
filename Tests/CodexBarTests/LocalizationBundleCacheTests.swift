import Foundation
import Testing
@testable import CodexBar

/// The app ships an English-only catalog; any requested language resolves to `en.lproj`.
/// The cache is process-global and these tests run in a parallel suite, so identity (`===`)
/// assertions would race — these assert resolution correctness and the en fallback instead.
struct LocalizationBundleCacheTests {
    @Test
    func `every language resolves the en lproj`() {
        resetCodexBarLocalizationCacheForTesting()

        for language in ["en", "fr", "es", "uk", "zz-unknown", ""] {
            let bundle = CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                codexBarLocalizedBundleForTesting()
            }
            #expect(bundle.bundleURL.lastPathComponent == "en.lproj")
        }
    }

    @Test
    func `resolution survives an explicit cache reset`() {
        let first = CodexBarLocalizationOverride.$appLanguage.withValue("es") {
            codexBarLocalizedBundleForTesting()
        }

        resetCodexBarLocalizationCacheForTesting()

        let afterReset = CodexBarLocalizationOverride.$appLanguage.withValue("es") {
            codexBarLocalizedBundleForTesting()
        }
        #expect(first.bundleURL == afterReset.bundleURL)
    }
}
