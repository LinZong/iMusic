import XCTest

@testable import iMusicKit

final class LocalizationTests: XCTestCase {
    func testEnglishSimplifiedTraditionalAndFallback() {
        XCTAssertEqual(
            L10n.format("Import Music", locale: Locale(identifier: "en")),
            "Import Music"
        )
        XCTAssertEqual(L10n.format("Import Music", locale: Locale(identifier: "zh-Hans")), "导入音乐")
        XCTAssertEqual(L10n.format("Import Music", locale: Locale(identifier: "zh-Hant")), "導入音樂")
        XCTAssertEqual(
            L10n.format("Import Music", locale: Locale(identifier: "fr_FR")),
            "Import Music"
        )
        XCTAssertEqual(L10n.language(for: Locale(identifier: "zh_TW")), "zh-Hant")
        XCTAssertEqual(L10n.language(for: Locale(identifier: "zh_CN")), "zh-Hans")
    }
    func testPluralRulesAndMultipleArguments() {
        let english = Locale(identifier: "en")
        XCTAssertEqual(L10n.format("format.song_count", locale: english, arguments: [0]), "0 songs")
        XCTAssertEqual(L10n.format("format.song_count", locale: english, arguments: [1]), "1 song")
        XCTAssertEqual(L10n.format("format.song_count", locale: english, arguments: [2]), "2 songs")
        XCTAssertEqual(
            L10n.format("format.song_count.duration", locale: english, arguments: [1, "3:40"]),
            "1 song · 3:40"
        )
        XCTAssertEqual(
            L10n.format("format.song_count.duration", locale: english, arguments: [2, "6:10"]),
            "2 songs · 6:10"
        )
        XCTAssertEqual(
            L10n.format("format.song_count", locale: Locale(identifier: "zh-Hans"), arguments: [2]),
            "2 首歌曲"
        )
    }
    func testErrorsAndUserProvidedNamesRemainReadable() {
        let name = "音楽 🎵.mp3"
        let message = L10n.format(
            "format.import.copy_incomplete",
            locale: Locale(identifier: "en"),
            arguments: [name]
        )
        XCTAssertTrue(message.hasPrefix(name))
        XCTAssertTrue(message.contains("import it again"))
        XCTAssertFalse(message.contains("%1$@"))
    }
    func testBrowserConfigurationUsesAppLanguageAndSharedLimits() throws {
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let data = try WiFiUploadResources.configuration(locale: Locale(identifier: language))
            let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(value["language"] as? String, language)
            XCTAssertEqual(value["extensions"] as? [String], ImportCoordinator.extensions.sorted())
            XCTAssertEqual(value["maxFileSize"] as? Int, WiFiUploadResources.maxFileSize)
        }
        let fallback = try WiFiUploadResources.configuration(locale: Locale(identifier: "fr_FR"))
        XCTAssertTrue(String(decoding: fallback, as: UTF8.self).contains("\"en\""))
    }
    func testSavedPreferenceIdentifiersRemainStableAcrossLanguages() {
        XCTAssertEqual(PreferencesCompatibility.canonicalID("深色"), "dark")
        let option = HomeSectionOption(id: "继续聆听", enabled: false).canonicalized()
        XCTAssertEqual(option.id, "continue")
        XCTAssertFalse(option.enabled)
        XCTAssertEqual(
            HomeSectionOption.defaults.map(\.id),
            ["continue", "categories", "playlists", "recent", "statistics"]
        )
    }
}
