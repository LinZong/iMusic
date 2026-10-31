import Foundation

/// Foreground observer for the currently opened source, never a long-lived coordination lock.
final class LinkedFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    /// Source resource retained until this presenter has been unregistered.
    private let source: PreparedSourceAudio
    /// Lock protecting URL updates delivered by provider move callbacks.
    private let lock = NSLock()
    /// Latest URL reported by the provider until this presenter is unregistered.
    private var url: URL
    /// Current observed location; a move also invalidates the prepared decoder.
    var presentedItemURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return url
    }
    /// Serial callback queue that never blocks waiting for the UI actor.
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "org.imusic.source-presenter"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    /// Asynchronous UI-actor invalidation, followed by the provider's optional acknowledgement.
    private let invalidate: @Sendable (@escaping @Sendable () -> Void) -> Void

    init(
        source: PreparedSourceAudio,
        invalidate: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void
    ) {
        self.source = source
        url = source.url
        self.invalidate = invalidate
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }
    /// Removes provider observation before backgrounding or releasing the active decoder.
    func unregister() { NSFileCoordinator.removeFilePresenter(self) }
    /// Invalidates a decoder when its underlying content has changed.
    func presentedItemDidChange() { invalidate({}) }
    /// Stops using the old URL before playback can resume from a refreshed bookmark.
    func presentedItemDidMove(to newURL: URL) {
        lock.lock()
        url = newURL
        lock.unlock()
        invalidate({})
    }
    /// Pauses rendering before allowing a coordinated writer to modify the source.
    func relinquishPresentedItem(
        toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void
    ) {
        invalidate { writer(nil) }
    }
    /// Releases foreground observation when the provider needs to reclaim its cached source.
    @available(iOS 17.4, macOS 14.4, *)
    func accommodatePresentedItemEviction(completionHandler: @escaping @Sendable (Error?) -> Void) {
        invalidate { completionHandler(nil) }
    }
    /// Closes playback before acknowledging a coordinated source deletion.
    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        invalidate { completionHandler(nil) }
    }
}
