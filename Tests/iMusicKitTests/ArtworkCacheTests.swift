import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import iMusicKit

final class ArtworkCacheTests: XCTestCase {
    func testEmbeddedCoverColorFormatsRenderAsNonblackRGBAAtBothPlayerSizes() throws {
        let formats: [(CFString, Int, CGImageAlphaInfo)] = [
            (CGColorSpace.genericGrayGamma2_2, 8, .none),
            (CGColorSpace.sRGB, 16, .premultipliedLast),
            (CGColorSpace.displayP3, 8, .premultipliedLast),
        ]
        for (space, depth, alpha) in formats {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("embedded.image")
            let context = try XCTUnwrap(
                CGContext(
                    data: nil,
                    width: 1200,
                    height: 1200,
                    bitsPerComponent: depth,
                    bytesPerRow: 0,
                    space: try XCTUnwrap(CGColorSpace(name: space)),
                    bitmapInfo: alpha.rawValue
                )
            )
            context.setFillColor(gray: 0.75, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1200))
            try write(try XCTUnwrap(context.makeImage()), to: url)

            let cache = ArtworkCache()
            for size in [84, 630] {
                let image = try XCTUnwrap(cache.image(at: url, size: size))
                XCTAssertEqual(image.width, size)
                XCTAssertEqual(image.height, size)
                XCTAssertEqual(image.bitsPerComponent, 8)
                XCTAssertEqual(image.bitsPerPixel, 32)
                XCTAssertEqual(image.colorSpace?.name, CGColorSpace.sRGB)
                let data = try XCTUnwrap(image.dataProvider?.data)
                let pixels = try XCTUnwrap(CFDataGetBytePtr(data))
                let center = image.bytesPerRow * (size / 2) + (size / 2) * 4
                for channel in 0..<3 {
                    XCTAssertGreaterThan(pixels[center + channel], 100)
                }
                XCTAssertEqual(pixels[center + 3], 255)
                XCTAssertTrue(image === cache.image(at: url, size: size))
            }
        }
    }

    func testOrientedTransparentCoverPreservesAspectRatioAndAlpha() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("embedded.image")
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 1200,
                height: 600,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
        try write(try XCTUnwrap(context.makeImage()), to: url, orientation: 6)
        let cache = ArtworkCache()
        for size in [84, 630] {
            let image = try XCTUnwrap(cache.image(at: url, size: size))
            XCTAssertEqual(image.width, size / 2)
            XCTAssertEqual(image.height, size)
            let data = try XCTUnwrap(image.dataProvider?.data)
            let pixels = try XCTUnwrap(CFDataGetBytePtr(data))
            XCTAssertEqual(Int(pixels[0]), 128, accuracy: 1)
            XCTAssertEqual(pixels[1], 0)
            XCTAssertEqual(pixels[2], 0)
            XCTAssertEqual(Int(pixels[3]), 128, accuracy: 1)
        }
    }

    func testMissingAndInvalidCoverReturnNil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = ArtworkCache()
        XCTAssertNil(cache.image(at: url, size: 630))
        try Data([1, 2, 3]).write(to: url)
        XCTAssertNil(cache.image(at: url, size: 630))
    }

    /// Writes an original generated cover with optional EXIF orientation and no filename type hint.
    private func write(_ image: CGImage, to url: URL, orientation: Int = 1) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
