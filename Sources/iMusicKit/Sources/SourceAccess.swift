import Foundation

/// Owns balanced root and file security scopes for the complete decoder lifetime.
final class SourceLease: @unchecked Sendable {
    /// Resolved source URL; only accessed while this lease is retained.
    let url: URL
    /// Parent authorization whose revision must still match when preparation finishes.
    let folderID: UUID
    /// Authorization revision captured before provider waiting.
    let generation: UUID?
    /// Last parsed source modification date, used to reject stale timeline metadata.
    let modified: Date?
    /// Source creation date used to reject a replacement during provider hydration.
    let created: Date?
    /// Successfully acquired security scopes that must be balanced exactly once.
    private let scopes: [URL]

    init(url: URL, scopes: [URL], binding: LinkedFileBinding) {
        self.url = url
        self.scopes = scopes
        created = binding.created
        modified = binding.modified
        folderID = binding.folderID
        generation = binding.folderGeneration
    }
    /// Rejects a late decoder after its root was unlinked or explicitly rebound to another
    /// directory.
    func checkAuthorization(_ store: LibraryStore) throws {
        guard
            try store.setting("folders", as: [FolderSource].self)?
                .contains(where: {
                    $0.id == folderID && $0.bindingGeneration == generation
                        && $0.usesOriginalFiles == true
                }) == true
        else { throw MusicError.permissionDenied }
    }
    deinit { for scope in scopes.reversed() { scope.stopAccessingSecurityScopedResource() } }
}

/// File-provider operations run on a bounded Foundation queue, never on the UI actor.
enum SourceAccess {
    /// Bounded workers for potentially blocking provider coordination and metadata reads.
    private static let workers: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "org.imusic.source-access"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        return queue
    }()

    /// Playback has a separate lane so a large folder scan cannot occupy all source workers.
    private static let playbackWorkers: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "org.imusic.source-playback"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// Executes blocking source work with cancellation propagated into NSFileCoordinator.
    static func perform<T: Sendable>(
        playback: Bool = false,
        _ body: @escaping @Sendable (SourceOperation) throws -> T
    ) async throws -> T {
        let operation = SourceOperation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                (playback ? playbackWorkers : workers)
                    .addOperation {
                        continuation.resume(
                            with: Result {
                                try operation.check()
                                let result = try body(operation)
                                try operation.check()
                                return result
                            }
                        )
                    }
            }
        } onCancel: {
            operation.cancel()
        }
    }

    /// Creates a platform-appropriate persistent read grant under an active parent grant.
    static func bookmark(_ url: URL) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    /// Resolves a bookmark without prompting; callers explicitly offer a picker when
    /// authorization fails.
    static func resolve(_ data: Data) throws -> URL {
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [
            .withSecurityScope, .withoutUI, .withoutMounting,
        ]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
        #endif
        var resolved = try URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        resolved.removeAllCachedResourceValues()
        return resolved
    }

    /// Opens a folder grant and resolves the file bookmark, rejecting replacements at the old path.
    static func lease(store: LibraryStore, track: Track) throws -> SourceLease {
        guard let reference = track.linkedSource,
            let folder = try store.setting("folders", as: [FolderSource].self)?
                .first(where: { $0.id == reference.folderID && $0.usesOriginalFiles == true }),
            let binding = try store.linkedBinding(id: track.id, folderID: reference.folderID),
            binding.folderGeneration == folder.bindingGeneration
        else { throw MusicError.unavailable(L10n.text("Authorize the linked folder in Settings.")) }
        let root = try resolve(folder.bookmark)
        var scopes: [URL] = []
        if root.startAccessingSecurityScopedResource() { scopes.append(root) }
        do {
            let url = try resolve(binding.bookmark)
            if url.startAccessingSecurityScopedResource() { scopes.append(url) }
            let values = try url.resourceValues(forKeys: [.creationDateKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true,
                binding.created == nil || values.creationDate == nil
                    || values.creationDate == binding.created
            else { throw MusicError.missingFile }
            return SourceLease(url: url, scopes: scopes, binding: binding)
        } catch {
            for scope in scopes.reversed() { scope.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
}

/// Cancellation token shared with blocking provider callbacks; no actor is blocked while waiting.
final class SourceOperation: @unchecked Sendable {
    /// Lock protecting cancellation and the active coordinator.
    private let lock = NSLock()
    /// Whether the owning Swift task has requested cancellation.
    private var cancelled = false
    /// Whether the current provider reservation exceeded its finite wait budget.
    private var deadlineExpired = false
    /// Coordinator that can interrupt a pending provider download or read reservation.
    private var coordinator: NSFileCoordinator?

    /// Cancels a pending reservation; completed provider downloads remain owned by the provider.
    func cancel() {
        lock.lock()
        cancelled = true
        let current = coordinator
        lock.unlock()
        current?.cancel()
    }
    /// Throws before and after work so late callbacks cannot commit cancelled admissions.
    func check() throws {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw CancellationError() }
    }
    /// Requests system hydration and reads the coordinated original, without creating an
    /// audio copy.
    func read<T>(_ url: URL, body: (URL) throws -> T) throws -> T {
        try check()
        try SourceHydrationRegistry.shared.acquire(url)
        defer { SourceHydrationRegistry.shared.release(url) }
        let current = NSFileCoordinator()
        lock.lock()
        coordinator = current
        deadlineExpired = false
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled {
            current.cancel()
            throw CancellationError()
        }
        let deadline = DispatchWorkItem { [weak self, weak current] in
            guard let self, let current else { return }
            self.lock.lock()
            let active = self.coordinator === current
            if active { self.deadlineExpired = true }
            self.lock.unlock()
            if active { current.cancel() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 120, execute: deadline)
        defer {
            deadline.cancel()
            lock.lock()
            coordinator = nil
            lock.unlock()
        }
        var coordinationError: NSError?
        var result: Result<T, Error>?
        // A coordinated read waits for iCloud and third-party document providers to hydrate data.
        current.coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            result = Result {
                try self.check()
                var fresh = readable
                fresh.removeAllCachedResourceValues()
                return try body(fresh)
            }
        }
        try check()
        lock.lock()
        let expired = deadlineExpired
        lock.unlock()
        if expired {
            throw MusicError.unavailable(
                L10n.text("Timed out waiting for the source file. Retry when it is available.")
            )
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw MusicError.missingFile }
        return try result.get()
    }
}
