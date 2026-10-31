import CoreFoundation
import Foundation
import Observation

@MainActor @Observable
final class TrackEditorViewModel {
    /// Consent-gated metadata lookup service owned by the editor.
    private let online: any OnlineMetadataProviding
    /// Image validation and managed-cover storage independent of editor drafts.
    private let artworkImporter: any ArtworkImporting

    /// Observable library records and record-level actions.
    let library: LibraryViewModel
    /// Persisted preferences used by this feature.
    let preferences: PreferencesViewModel
    /// Song metadata snapshot captured when the editor opened.
    let original: Track
    /// Editable metadata copy applied to the library only when Save is chosen.
    var draft: Track
    /// Whether the artwork image file importer is presented.
    var chooseArtwork = false
    /// Online release candidates returned by an explicitly requested album search.
    var releases: [OnlineRelease] = []
    /// Whether an online release or artwork request is in progress.
    var onlineBusy = false
    /// Most recent metadata, artwork, or online lookup error shown inside the editor.
    var error: String?
    /// Selected source encoding for previewing repair of incorrectly decoded tags.
    var encodingName = "Shift-JIS"
    /// Preview title, artist, and album strings awaiting explicit application to the draft.
    var repaired: [String]?
    /// Creates an independent feature model with explicit service and state dependencies.
    init(
        library: LibraryViewModel,
        preferences: PreferencesViewModel,
        original: Track,
        online: any OnlineMetadataProviding = OnlineMetadataService(),
        artworkImporter: (any ArtworkImporting)? = nil
    ) {
        self.library = library
        self.preferences = preferences
        self.original = original
        self.draft = original
        self.online = online
        self.artworkImporter = artworkImporter ?? ManagedArtworkImporter(vault: library.vault)
    }
    /// Admits a selected cover reference into this draft without saving the song record.
    func setArtwork(_ data: Data) throws { draft.artworkName = try artworkImporter.store(data) }

    /// Previews legacy decoding without mutating the saved tags or draft fields.
    func previewDecoding() {
        repaired = TagEncodingRepair.preview(
            [draft.title, draft.artist, draft.album],
            encodingName: encodingName
        )
    }
    /// Applies the current decoding preview to the editable copy only.
    func applyPreview() {
        guard let repaired, repaired.count == 3 else { return }
        draft.title = repaired[0]
        draft.artist = repaired[1]
        draft.album = repaired[2]
        self.repaired = nil
    }
    /// Resets editable tags to their original imported values without persisting a change.
    func restoreOriginalTags() {
        draft.title = original.originalMetadata["title"] ?? original.title
        draft.artist = original.originalMetadata["artist"] ?? original.artist
        draft.album = original.originalMetadata["album"] ?? original.album
        draft.albumArtist = original.originalMetadata["albumArtist"] ?? original.albumArtist
        draft.genre = original.originalMetadata["genre"] ?? original.genre
    }
    /// Performs an explicit, consent-gated album lookup and publishes results in this editor only.
    func searchArtwork() async {
        guard preferences.onlineEnabled, !onlineBusy else { return }
        onlineBusy = true
        error = nil
        defer { onlineBusy = false }
        do {
            releases = try await online.search(album: draft.album, artist: draft.artist)
            if releases.isEmpty {
                error = L10n.text("No matching album found. Please choose artwork manually.")
            }
        } catch { self.error = error.localizedDescription }
    }
    /// Downloads and validates a chosen cover after the user explicitly selects an online result.
    func chooseRelease(_ release: OnlineRelease) async {
        guard preferences.onlineEnabled, !onlineBusy else { return }
        onlineBusy = true
        defer { onlineBusy = false }
        do { try setArtwork(try await online.artwork(for: release)) } catch {
            self.error = error.localizedDescription
        }
    }
    /// Applies a user-selected cover only to this editor's draft.
    func importArtwork(_ result: Result<URL, Error>) {
        do { draft.artworkName = try artworkImporter.importFile(result.get()) } catch {
            self.error = error.localizedDescription
        }
    }
    /// Commits the current draft through the library mutation boundary.
    func save() { library.commands.save(draft) }
}
