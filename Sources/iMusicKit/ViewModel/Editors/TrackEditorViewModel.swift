import CoreFoundation
import Foundation
import ImageIO
import Observation

@MainActor @Observable
final class TrackEditorViewModel {
  /// Consent-gated metadata lookup service owned by the editor.
  let online: OnlineMetadataService = OnlineMetadataService()

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
  init(library: LibraryViewModel, preferences: PreferencesViewModel, original: Track) {
    self.library = library
    self.preferences = preferences
    self.original = original
    self.draft = original
  }
  /// Validates and stores a draft cover without changing the persisted track until Save.
  func setArtwork(_ data: Data) throws {
    guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
      throw MusicError.unavailable(L10n.text("Unable to read this image."))
    }
    let name = UUID().uuidString + ".image"
    try data.write(to: library.vault.artwork.appendingPathComponent(name), options: .atomic)
    draft.artworkName = name
  }

  /// Previews a different decoding of legacy tag bytes without saving the draft.
  func previewDecoding() {
    let encoding: String.Encoding =
      encodingName == "Shift-JIS"
      ? .shiftJIS
      : encodingName == "UTF-8"
        ? .utf8
        : String.Encoding(
          rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    repaired = [draft.title, draft.artist, draft.album].map { value in
      guard let bytes = value.data(using: .isoLatin1) ?? value.data(using: .windowsCP1252),
        let text = String(data: bytes, encoding: encoding), !text.contains("\u{fffd}")
      else { return value }
      return text
    }
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
  /// Reads a size-limited cover selected through the native security-scoped file picker.
  func importArtwork(_ result: Result<URL, Error>) {
    do {
      let url = try result.get()
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 20_000_000 else {
        throw MusicError.unavailable(L10n.text("Choose an image smaller than 20 MB."))
      }
      try setArtwork(Data(contentsOf: url))
    } catch { self.error = error.localizedDescription }
  }
  /// Commits the current draft through the library mutation boundary.
  func save() { library.save(draft) }
}
