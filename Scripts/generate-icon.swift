#!/usr/bin/env swift
import AppKit
import Foundation

// Build-time artwork only. No screenshots, external assets or runtime dependency.
// ICNS uses standard PNG representations; all pixels are drawn from native paths
// for an original seven-blade fan. No SF Symbol artwork, personal or signing data is embedded.
@MainActor func iconPNG(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    let tile = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 205, yRadius: 205)
    NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.98, alpha: 1).setFill(); tile.fill()
    NSColor(calibratedRed: 0.77, green: 0.81, blue: 0.85, alpha: 1).setStroke(); tile.lineWidth = 8; tile.stroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 162, y: 162, width: 700, height: 700))
    NSColor(calibratedRed: 0.40, green: 0.56, blue: 0.62, alpha: 1).setStroke()
    ring.lineWidth = 24; ring.stroke()
    // Original swept blade, repeated seven times around the bearing. This is
    // deliberately a housed cooling fan rather than Apple's propeller glyph.
    for index in 0..<7 {
        let blade = NSBezierPath()
        blade.move(to: NSPoint(x: 58, y: 30))
        blade.curve(to: NSPoint(x: 280, y: 80), controlPoint1: NSPoint(x: 135, y: 90), controlPoint2: NSPoint(x: 200, y: 120))
        blade.curve(to: NSPoint(x: 225, y: 215), controlPoint1: NSPoint(x: 320, y: 95), controlPoint2: NSPoint(x: 292, y: 195))
        blade.curve(to: NSPoint(x: 42, y: 70), controlPoint1: NSPoint(x: 112, y: 236), controlPoint2: NSPoint(x: 92, y: 155))
        blade.close()
        let angle = Double(index) * 2 * .pi / 7
        let transform = AffineTransform(m11: cos(angle), m12: sin(angle), m21: -sin(angle), m22: cos(angle), tX: 512, tY: 512)
        blade.transform(using: transform)
        NSColor(calibratedRed: 0.18, green: 0.26, blue: 0.33, alpha: 1).setFill(); blade.fill()
    }
    let bearing = NSBezierPath(ovalIn: NSRect(x: 432, y: 432, width: 160, height: 160))
    NSColor(calibratedRed: 0.40, green: 0.56, blue: 0.62, alpha: 1).setFill(); bearing.fill()
    let center = NSBezierPath(ovalIn: NSRect(x: 476, y: 476, width: 72, height: 72))
    NSColor(calibratedWhite: 0.95, alpha: 1).setFill(); center.fill()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    return png
}
func length(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
try MainActor.assumeIsolated {
guard CommandLine.arguments.count == 2 else { fatalError("Expected output ICNS path") }
var payload = Data()
for (size, type) in [(16,"icp4"),(32,"icp5"),(64,"icp6"),(128,"ic07"),(256,"ic08"),(512,"ic09"),(1024,"ic10")] {
    let png = try iconPNG(size: size)
    payload.append(Data(type.utf8)); payload.append(length(png.count + 8)); payload.append(png)
}
var result = Data("icns".utf8); result.append(length(payload.count + 8)); result.append(payload)
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try result.write(to: output, options: .atomic)

}
