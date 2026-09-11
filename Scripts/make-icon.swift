// Draws AppIcon.icns from code, so the icon has no binary source of truth to
// lose and can be re-rendered crisply at any size.
//
//   swift Scripts/make-icon.swift
//
// The generated Resources/AppIcon.icns is checked in, so contributors only
// need to run this when changing the artwork.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

let topColor    = CGColor(red: 0.36, green: 0.42, blue: 0.52, alpha: 1.0)
let bottomColor = CGColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1.0)
let glyphColor  = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

// MARK: - Drawing

/// Draws the icon into `ctx` for a square canvas of `s` points.
/// All geometry is expressed as a fraction of `s` so every size is a real
/// redraw rather than a resample.
func drawIcon(into ctx: CGContext, size s: CGFloat) {
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // macOS icons leave transparent padding around a rounded-rect body.
    let inset = s * 0.09
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.2237  // Big Sur-style corner radius

    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Gradient body.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space, colors: [topColor, bottomColor] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: body.midX, y: body.maxY),
            end: CGPoint(x: body.midX, y: body.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Headphones glyph: a stroked headband arc with a capsule earcup at each end.
    let cx = s * 0.5
    let cy = s * 0.52
    let bandRadius = s * 0.205
    let bandWidth = s * 0.052

    ctx.saveGState()
    ctx.setStrokeColor(glyphColor)
    ctx.setLineWidth(bandWidth)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: bandRadius,
               startAngle: .pi, endAngle: 0, clockwise: true)
    ctx.strokePath()

    ctx.setFillColor(glyphColor)
    let cupWidth = s * 0.138
    let cupHeight = s * 0.215
    for dx in [-bandRadius, bandRadius] {
        let cup = CGRect(
            x: cx + dx - cupWidth / 2,
            y: cy - cupHeight + s * 0.022,
            width: cupWidth,
            height: cupHeight
        )
        ctx.addPath(CGPath(roundedRect: cup, cornerWidth: cupWidth / 2, cornerHeight: cupWidth / 2, transform: nil))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

// MARK: - Output

func renderPNG(size: Int, to url: URL) throws {
    let s = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "make-icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "could not create \(size)px bitmap context"])
    }

    drawIcon(into: ctx, size: s)

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw NSError(domain: "make-icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "could not encode \(size)px PNG"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "make-icon", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "could not write \(url.path)"])
    }
}

// Each .icns slot: (base point size, @2x?).
let slots: [(Int, Bool)] = [
    (16, false), (16, true),
    (32, false), (32, true),
    (128, false), (128, true),
    (256, false), (256, true),
    (512, false), (512, true),
]

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let iconset = repoRoot.appendingPathComponent(".build/AppIcon.iconset")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (base, isRetina) in slots {
    let pixels = isRetina ? base * 2 : base
    let name = isRetina ? "icon_\(base)x\(base)@2x.png" : "icon_\(base)x\(base).png"
    try renderPNG(size: pixels, to: iconset.appendingPathComponent(name))
    print("  rendered \(name) (\(pixels)px)")
}

print("==> Wrote \(iconset.path)")
