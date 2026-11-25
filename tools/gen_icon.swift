#!/usr/bin/env swift
// Renders CloudPlayer's app icon and writes the full macOS AppIcon.appiconset.
// Usage: swift tools/gen_icon.swift CloudPlayer/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "CloudPlayer/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Draws the icon on a 1024×1024 canvas (CG coordinates, origin bottom-left):
/// a soft cloud gently pressed into a light surface.
func drawIcon(_ ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func grad(_ colors: [CGColor], _ a: CGPoint, _ b: CGPoint) {
        let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    /// Shadow cast *inside* `path`: fill everything outside it with a shadow, clipped to it.
    func innerShadow(_ path: CGPath, offset: CGSize, blur: CGFloat, color: CGColor) {
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let outside = CGMutablePath()
        outside.addRect(CGRect(x: -2000, y: -2000, width: 5000, height: 5000))
        outside.addPath(path)
        ctx.setShadow(offset: offset, blur: blur, color: color)
        ctx.addPath(outside); ctx.setFillColor(rgb(0x000000)); ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    // macOS icon grid: 824pt body centred in 1024.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.30))
    ctx.addPath(shape); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()

    // Warm off-white surface; the cloud's floor is the same surface, so it matches.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    grad([rgb(0xFCFAF6), rgb(0xEDE9E2)], CGPoint(x: 512, y: 924), CGPoint(x: 512, y: 100))
    ctx.restoreGState()

    // Cloud: union of circles on a rounded base, flattened into one outline.
    let blobs = CGMutablePath()
    blobs.addRoundedRect(in: CGRect(x: 222, y: 322, width: 580, height: 196), cornerWidth: 98, cornerHeight: 98)
    blobs.addEllipse(in: CGRect(x: 282, y: 374, width: 228, height: 228))
    blobs.addEllipse(in: CGRect(x: 396, y: 404, width: 310, height: 310))
    blobs.addEllipse(in: CGRect(x: 588, y: 372, width: 198, height: 198))
    let cloud = blobs.union(CGPath(rect: .zero, transform: nil))

    // Thin, softly raised vertical ribs on the cloud floor. Each one stops short of the rim
    // with a rounded end, so it reads as a puffy ridge rather than a stripe.
    ctx.saveGState()
    ctx.addPath(cloud); ctx.clip()
    let ribWidth: CGFloat = 13, spacing: CGFloat = 38, margin: CGFloat = 58
    let floorTone = rgb(0xF5F2EC)
    var x: CGFloat = 512 - spacing * 7
    while x <= 512 + spacing * 7 {
        var lo: CGFloat? = nil, hi: CGFloat? = nil
        for y in stride(from: CGFloat(300), through: 740, by: 2) where cloud.contains(CGPoint(x: x, y: y)) {
            if lo == nil { lo = y }
            hi = y
        }
        if let lo, let hi, hi - lo > 2 * margin + 70 {
            let rib = CGMutablePath()
            rib.move(to: CGPoint(x: x, y: lo + margin)); rib.addLine(to: CGPoint(x: x, y: hi - margin))
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.setShadow(offset: .zero, blur: 14, color: rgb(0x5A4E40, 0.13))
            ctx.addPath(rib); ctx.setLineWidth(ribWidth); ctx.setStrokeColor(floorTone); ctx.strokePath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.setLineCap(.round)
            ctx.addPath(rib); ctx.setLineWidth(ribWidth * 0.45); ctx.setStrokeColor(rgb(0xFFFFFF, 0.30))
            ctx.strokePath()
            ctx.restoreGState()
        }
        x += spacing
    }
    ctx.restoreGState()

    // Ambient occlusion only: a soft, even falloff hugging the rim, fading to nothing inside.
    innerShadow(cloud, offset: .zero, blur: 48, color: rgb(0x5A4E40, 0.26))
}

func render(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    drawIcon(ctx)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

var images: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try render(pt * scale).write(to: outDir.appendingPathComponent(name))
        images.append("""
            { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(pt)x\(pt)" }
        """)
    }
}
let contents = "{\n  \"images\" : [\n\(images.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try contents.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
let catalog = outDir.deletingLastPathComponent().appendingPathComponent("Contents.json")
if !FileManager.default.fileExists(atPath: catalog.path) {
    try "{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
        .write(to: catalog, atomically: true, encoding: .utf8)
}
print("Wrote \(images.count) icon images to \(outDir.path)")
