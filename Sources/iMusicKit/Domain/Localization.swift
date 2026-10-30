import Foundation

/// Shared by SwiftUI, background services, errors, and the browser upload page.
/// Lookup uses the package's resource bundle, never whichever app hosts the library.
public enum L10n {
    /// Localization identifiers bundled with the app and the browser upload client.
    public static let supportedLanguages = ["en", "zh-Hans", "zh-Hant"]
    /// Language-specific package bundles cached for deterministic localized string lookup.
    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: supportedLanguages.compactMap { language in
        // SwiftPM normalizes localization directory names to lowercase.
        for name in [language, language.lowercased()] {
            if let root = Bundle.module.resourceURL, let bundle = Bundle(url: root.appendingPathComponent(name + ".lproj")) { return (language, bundle) }
        }
        return nil
    })
    /// Best bundled language matching the current preferred language list, with English as fallback.
    public static var language: String { language(for: nil) }
    /// Chooses a bundled language for an explicit locale or the user's preferred languages, falling back to
    /// English.
    public static func language(for locale: Locale?) -> String {
        let preferences = locale.map { [$0.identifier.replacingOccurrences(of: "_", with: "-")] } ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: supportedLanguages, forPreferences: preferences).first ?? "en"
    }
    /// Resolves a shared localized key and formats optional arguments using the current app language.
    public static func text(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, arguments: arguments)
    }
    /// An explicit locale supports deterministic tests and preview tools.
    public static func format(_ key: String, locale: Locale? = nil, arguments: [CVarArg] = []) -> String {
        let language = language(for: locale), bundle = bundles[language] ?? bundles["en"] ?? Bundle.module
        let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        guard !arguments.isEmpty else { return value }
        return String(format: value, locale: locale ?? Locale(identifier: language), arguments: arguments)
    }
}

/// Legacy values are data migrations, not translated UI identifiers.
enum PreferencesCompatibility {
    /// Mapping from early saved display values to language-independent preference identifiers.
    private static let legacy: [String: String] = {
        guard let url = Bundle.module.url(forResource: "LegacyPreferences", withExtension: "json"),
              let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }()
    static func canonicalID(_ value: String) -> String { legacy[value] ?? value }
}
