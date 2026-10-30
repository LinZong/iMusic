import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Repository-owned asset catalog, resolved independently of the shell's working directory.
let base = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Apps/Resources/Assets.xcassets")
/// Shared icon catalog containing platform-specific Mac images and iOS appearance variants.
let icons = base.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
/// Explicit sRGB color space used by the colored icon artwork.
let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// Asset-catalog appearances, automatically selected by the iOS or iPadOS Home Screen.
enum IconAppearance: String, CaseIterable {
    /// Opaque default artwork, also used by systems predating appearance variants.
    case standard
    /// Colored foreground on transparency for the system-provided dark background.
    case dark
    /// Grayscale artwork that the system can recolor with the user's chosen tint.
    case tinted
}

/// Draws the original purple music artwork on its unmasked 1024-point design canvas.
func drawArtwork(in context: CGContext) {
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 0.22, green: 0.17, blue: 0.54, alpha: 1),
            CGColor(red: 0.51, green: 0.34, blue: 0.9, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 1024, y: 1024),
        options: []
    )
    context.setFillColor(CGColor(gray: 1, alpha: 0.06))
    context.fillEllipse(in: CGRect(x: 35, y: 35, width: 954, height: 954))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    drawMusicNote(in: context)
}

/// Draws the shared music silhouette without a background or platform-specific mask.
func drawMusicNote(in context: CGContext) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 402, y: 325))
    path.addLine(to: CGPoint(x: 402, y: 698))
    path.addQuadCurve(to: CGPoint(x: 424, y: 723), control: CGPoint(x: 402, y: 720))
    path.addLine(to: CGPoint(x: 740, y: 780))
    path.addQuadCurve(to: CGPoint(x: 766, y: 758), control: CGPoint(x: 766, y: 785))
    path.addLine(to: CGPoint(x: 766, y: 386))
    path.addLine(to: CGPoint(x: 712, y: 386))
    path.addLine(to: CGPoint(x: 712, y: 636))
    path.addLine(to: CGPoint(x: 456, y: 591))
    path.addLine(to: CGPoint(x: 456, y: 325))
    path.closeSubpath()
    context.addPath(path)
    context.fillPath()
    context.saveGState()
    context.translateBy(x: 351, y: 318)
    context.rotate(by: 0.28)
    context.fillEllipse(in: CGRect(x: -108, y: -77, width: 216, height: 154))
    context.restoreGState()
    context.saveGState()
    context.translateBy(x: 661, y: 381)
    context.rotate(by: 0.28)
    context.fillEllipse(in: CGRect(x: -108, y: -77, width: 216, height: 154))
    context.restoreGState()
}

/// Draws iOS artwork without baked-in corner masks, outer margins, or drop shadows.
func drawIOSArtwork(in context: CGContext, appearance: IconAppearance) {
    switch appearance {
    case .standard:
        drawArtwork(in: context)
    case .dark:
        // Leave the background transparent so iOS can supply its dark appearance.
        context.setFillColor(CGColor(red: 0.69, green: 0.53, blue: 0.96, alpha: 1))
        drawMusicNote(in: context)
    case .tinted:
        // Neutral values preserve silhouette contrast under any system-selected tint.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        drawMusicNote(in: context)
    }
}

/// Renders a native Mac silhouette or an iOS appearance at the requested pixel size.
func render(
    _ pixels: Int,
    filename: String,
    macOS: Bool = false,
    appearance: IconAppearance = .standard
) throws {
    let grayscale = !macOS && appearance == .tinted
    let renderSpace = grayscale ? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)! : space
    let alpha: CGImageAlphaInfo =
        grayscale ? .none : (macOS || appearance == .dark ? .premultipliedLast : .noneSkipLast)
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: pixels * (grayscale ? 1 : 4),
        space: renderSpace,
        bitmapInfo: alpha.rawValue
    )!
    let pixelScale = CGFloat(pixels) / 1024
    context.scaleBy(x: pixelScale, y: pixelScale)
    if macOS {
        // Match Sequoia's inset icon face; transparency and the silhouette are part of the PNG.
        let face = CGRect(x: 100, y: 100, width: 824, height: 824)
        let outline = RoundedRectangle(cornerRadius: 185, style: .continuous).path(in: face)
        context.saveGState()
        // Quartz shadow metrics use device pixels, so small icons need scaled shadow values.
        context.setShadow(
            offset: CGSize(width: 0, height: -12 * pixelScale),
            blur: 20 * pixelScale,
            color: CGColor(gray: 0, alpha: 0.22)
        )
        context.setFillColor(CGColor(red: 0.22, green: 0.17, blue: 0.54, alpha: 1))
        context.addPath(outline.cgPath)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(outline.cgPath)
        context.clip()
        context.translateBy(x: face.minX, y: face.minY)
        context.scaleBy(x: face.width / 1024, y: face.height / 1024)
        drawArtwork(in: context)
        context.restoreGState()
    } else {
        drawIOSArtwork(in: context, appearance: appearance)
    }
    let output = CGImageDestinationCreateWithURL(
        icons.appendingPathComponent(filename) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )!
    CGImageDestinationAddImage(output, context.makeImage()!, nil)
    CGImageDestinationFinalize(output)
}
/// Asset catalog entries for Mac representations and universal iPhone/iPad appearances.
var images: [[String: Any]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "mac-\(size)@\(scale)x.png"
        try render(size * scale, filename: filename, macOS: true)
        images.append([
            "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename,
        ])
    }
}
for appearance in IconAppearance.allCases {
    let filename =
        appearance == .standard ? "ios-1024.png" : "ios-1024-\(appearance.rawValue).png"
    try render(1024, filename: filename, appearance: appearance)
    var entry: [String: Any] = [
        "idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": filename,
    ]
    if appearance != .standard {
        entry["appearances"] = [["appearance": "luminosity", "value": appearance.rawValue]]
    }
    images.append(entry)
}
try JSONSerialization.data(
    withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]],
    options: [.prettyPrinted, .sortedKeys]
)
.write(to: icons.appendingPathComponent("Contents.json"))
try JSONSerialization.data(
    withJSONObject: ["info": ["author": "xcode", "version": 1]],
    options: [.prettyPrinted, .sortedKeys]
)
.write(to: base.appendingPathComponent("Contents.json"))
