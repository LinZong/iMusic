import XCTest

/// Additional library workflows beyond the original search and playback smoke scenarios.
@MainActor final class LibraryWorkflowUITests: UITestCase {
    /// Home category cards must keep equal sizes despite different text and song counts.
    func testHomeCategoryCardsHaveEqualDimensions() {
        launch()
        let frames = ["home.artists", "home.albums", "home.favorites"]
            .map { identifier in
                let tile = app.element(identifier)
                XCTAssertTrue(tile.waitForExistence(timeout: 5))
                return tile.frame
            }
        for frame in frames.dropFirst() {
            XCTAssertEqual(frame.width, frames[0].width, accuracy: 1)
            XCTAssertEqual(frame.height, frames[0].height, accuracy: 1)
        }
        capture("Equal Home category cards")
    }

    /// Favorite mutations must filter correctly and survive restarting the host process.
    func testFavoriteFilteringAndPersistence() {
        launch()
        navigate("All Songs")
        library.showTrackActions("UI Alpha")
        library.favoriteAction.interact()
        app.terminate()
        launch(relaunch: true)
        navigate("Favorites")
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        XCTAssertFalse(library.track("UI Beta").exists)
        library.showTrackActions("UI Alpha")
        library.favoriteAction.interact()
        XCTAssertTrue(app.text(containing: "No Music Here Yet").waitForExistence(timeout: 5))
        capture("Favorites empty after removing the generated song")
    }

    /// Native import cancellation must leave the existing generated library unchanged.
    func testImportMusicPickerCanBeCancelled() {
        launch()
        app.element("library.add").interact()
        app.element("library.import").interact()
        library.cancelPicker()
        navigate("All Songs")
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        XCTAssertTrue(library.track("UI Beta").exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    /// Artist navigation must preserve generated metadata and open the corresponding songs.
    func testArtistCollectionOpensItsSongs() {
        launch()
        navigate("Artists")
        let artist = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Test Artist'"))
            .firstMatch
        XCTAssertTrue(artist.waitForExistence(timeout: 5), app.debugDescription)
        artist.interact()
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        XCTAssertTrue(library.track("UI Beta").exists)
        capture("Artist collection songs")
    }
}
