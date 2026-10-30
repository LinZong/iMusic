import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let base = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Apps/Resources/Assets.xcassets")
let icons = base.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func render(_ pixels: Int, filename: String) throws {
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: pixels * 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
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
    let output = CGImageDestinationCreateWithURL(
        icons.appendingPathComponent(filename) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )!
    CGImageDestinationAddImage(output, context.makeImage()!, nil)
    CGImageDestinationFinalize(output)
}
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "mac-\(size)@\(scale)x.png"
        try render(size * scale, filename: filename)
        images.append([
            "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename,
        ])
    }
}
try render(1024, filename: "ios-1024.png")
images.append([
    "idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "ios-1024.png",
])
try JSONSerialization.data(
    withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]],
    options: [.prettyPrinted, .sortedKeys]
)
.write(to: icons.appendingPathComponent("Contents.json"))
try JSONSerialization.data(
    withJSONObject: ["info": ["author": "xcode", "version": 1]],
    options: [.prettyPrinted]
)
.write(to: base.appendingPathComponent("Contents.json"))
