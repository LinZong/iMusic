import Foundation

/// Composition root that creates services and connects independently observable feature models.
@MainActor
public final class AppModel {
  /// Persistent library used by platform integrations.
  public let store: LibraryStore
  /// Playback session shared by all scenes and remote commands.
  public let playback: PlaybackCoordinator
  /// Optional CloudKit synchronization service.
  public let cloud: CloudSyncCoordinator
  /// Observable library records and mutations, independent of page state.
  public let library: LibraryViewModel
  /// Persistent user preferences.
  public let preferences: PreferencesViewModel
  /// File, folder, Wi-Fi, backup, and diagnostics workflows.
  public let imports: ImportViewModel
  /// Cross-feature presentation requests.
  public let presentation: PresentationViewModel
  /// Player actions and player-specific presentation state.
  public let player: PlayerViewModel
  /// Retained system media integration, omitted by isolated model tests.
  private let mediaBridge: SystemMediaBridge?
  /// Prevents duplicate startup recovery across app scenes.
  private var launchComplete: Bool = false

  /// Opens the library and wires feature dependencies; an injected engine avoids hardware in tests.
  public init(
    root: URL = MediaVault.defaultRoot, cloudIdentifier: String? = nil,
    engine: (any PlaybackEngine)? = nil, integrateWithSystem: Bool = true
  ) throws {
    let vault = try MediaVault(root: root)
    store = try LibraryStore(url: root.appendingPathComponent("Library.sqlite"))
    let importer = ImportCoordinator(store: store, vault: vault)
    playback = PlaybackCoordinator(store: store, vault: vault, engine: engine)
    cloud = CloudSyncCoordinator(store: store, vault: vault, containerIdentifier: cloudIdentifier)
    let activity = LibraryActivity()
    preferences = PreferencesViewModel(store: store)
    presentation = PresentationViewModel()
    library = LibraryViewModel(
      store: store, vault: vault, importer: importer, playback: playback, cloud: cloud,
      activity: activity, preferences: preferences)
    imports = ImportViewModel(
      library: library, backup: BackupService(store: store, vault: vault), wifi: WiFiUploadServer(),
      activity: activity, preferences: preferences)
    player = PlayerViewModel(
      library: library, playback: playback, preferences: preferences, presentation: presentation)
    mediaBridge = integrateWithSystem ? SystemMediaBridge(playback: playback, vault: vault) : nil
    cloud.onChange = { [weak library] in Task { await library?.refresh() } }
    playback.resolveMissing = { [weak cloud, weak playback] track, token in
      Task { @MainActor in
        guard let cloud, let playback else { return }
        do {
          try await cloud.downloadForPlayback(track)
          playback.completedDownload(token: token, error: nil)
        } catch { playback.completedDownload(token: token, error: error) }
      }
    }
    #if os(iOS)
      if integrateWithSystem { CarPlaySceneDelegate.model = self }
    #endif
  }
  /// Runs startup recovery once and restores explicitly enabled cloud synchronization.
  public func launch() async {
    guard !launchComplete else { return }
    launchComplete = true
    await imports.launch()
    if cloud.available, (try? store.setting("cloudEnabled", as: Bool.self)) == true {
      await cloud.enable(allowAccountChange: false)
    }
  }
  /// Creates scene-local navigation state while retaining shared library and playback sessions.
  func makeRootViewModel() -> RootViewModel {
    let root = RootViewModel(
      library: library, player: player, preferences: preferences, imports: imports)
    root.launch = { [weak self] in await self?.launch() }
    return root
  }
}
