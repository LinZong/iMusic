import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import iMusicKit

@MainActor final class ArtworkViewTests: XCTestCase {
    /// Recreating an accessory can resolve a warm cover before any lifecycle task starts.
    func testRecreatedStateUsesMemoryCacheOnItsFirstFrame() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, try makeImage(), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let cache = ArtworkCache()
        let request = ArtworkView.Request(url: url, pixels: 68)
        let cold = ArtworkView.LoadingState()
        XCTAssertNil(cold.image(for: request, cache: cache))
        let image = try XCTUnwrap(cache.image(at: url, size: request.pixels))
        let recreated = ArtworkView.LoadingState()
        XCTAssertTrue(recreated.image(for: request, cache: cache) === image)
    }

    /// Reappearance keeps an existing cover even if the shared cache no longer has that image.
    func testRestartingTheSameRequestRetainsItsLoadedImage() throws {
        let cache = ArtworkCache()
        let request = ArtworkView.Request(url: URL(fileURLWithPath: "/cover.image"), pixels: 68)
        let image = try makeImage()
        var state = ArtworkView.LoadingState()
        let generation = state.begin(request)
        state.finish(image, for: request, generation: generation)
        _ = state.begin(request)
        XCTAssertTrue(state.image(for: request, cache: cache) === image)
    }

    /// Changing covers, removing artwork, and resizing cannot display a previous request's image.
    func testResultsAreMatchedToCoverURLAndResolution() throws {
        let cache = ArtworkCache()
        let request = ArtworkView.Request(url: URL(fileURLWithPath: "/cover.image"), pixels: 68)
        var state = ArtworkView.LoadingState()
        let generation = state.begin(request)
        state.finish(try makeImage(), for: request, generation: generation)
        for changed in [
            ArtworkView.Request(url: URL(fileURLWithPath: "/other.image"), pixels: 68),
            ArtworkView.Request(url: request.url, pixels: 76),
            ArtworkView.Request(url: nil, pixels: 68),
        ] {
            XCTAssertNil(state.image(for: changed, cache: cache))
        }
        let missing = ArtworkView.Request(url: nil, pixels: 68)
        let missingGeneration = state.begin(missing)
        state.finish(nil, for: missing, generation: missingGeneration)
        XCTAssertNil(state.image(for: request, cache: cache))
    }

    /// Late results cannot overwrite a different cover that has already finished loading.
    func testSupersededRequestCannotReplaceTheCurrentResult() throws {
        let cache = ArtworkCache()
        let first = ArtworkView.Request(url: URL(fileURLWithPath: "/first.image"), pixels: 68)
        let second = ArtworkView.Request(url: URL(fileURLWithPath: "/second.image"), pixels: 68)
        let currentImage = try makeImage()
        var state = ArtworkView.LoadingState()
        let oldGeneration = state.begin(first)
        let currentGeneration = state.begin(second)
        state.finish(currentImage, for: second, generation: currentGeneration)
        state.finish(try makeImage(), for: first, generation: oldGeneration)
        XCTAssertTrue(state.image(for: second, cache: cache) === currentImage)
        XCTAssertNil(state.image(for: first, cache: cache))
    }

    /// Returning to the same URL cannot admit a result from its earlier load generation.
    func testReturningToTheSameCoverRejectsItsEarlierGeneration() throws {
        let cache = ArtworkCache()
        let first = ArtworkView.Request(url: URL(fileURLWithPath: "/first.image"), pixels: 68)
        let second = ArtworkView.Request(url: URL(fileURLWithPath: "/second.image"), pixels: 68)
        var state = ArtworkView.LoadingState()
        let stale = state.begin(first)
        _ = state.begin(second)
        let current = state.begin(first)
        state.finish(try makeImage(), for: first, generation: stale)
        XCTAssertNil(state.image(for: first, cache: cache))
        let image = try makeImage()
        state.finish(image, for: first, generation: current)
        XCTAssertTrue(state.image(for: first, cache: cache) === image)
    }

    /// An actually cancelled task cannot publish even when its request and generation still match.
    func testCancelledTaskCannotPublishItsResult() async throws {
        let cache = ArtworkCache()
        let request = ArtworkView.Request(url: URL(fileURLWithPath: "/cover.image"), pixels: 68)
        var state = ArtworkView.LoadingState()
        let generation = state.begin(request)
        let image = try makeImage()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            state.finish(image, for: request, generation: generation)
        }
        await task.value
        XCTAssertNil(state.image(for: request, cache: cache))
    }

    /// Builds a generated cover without UI hosts or filesystem dependencies.
    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 128,
                height: 128,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        return try XCTUnwrap(context.makeImage())
    }
}
