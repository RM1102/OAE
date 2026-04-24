#!/usr/bin/env swift
// Renders a 1024x1024 OAE app icon into AppIcon.appiconset using Core Graphics,
// then writes every macOS icon size (16..1024 at 1x/2x). No external deps.

import Foundation
import AppKit
import CoreGraphics
import CoreText

let repoRoot: URL = {
    // Script sits in <repo>/scripts/generate-icon.swift.
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    return scriptURL.deletingLastPathComponent().deletingLastPathComponent()
}()

let iconsetDir = repoRoot
    .appendingPathComponent("apps/oae-mac/OAE/Resources/Assets.xcassets/AppIcon.appiconset")
let workDir = repoRoot.appendingPathComponent("build/icon-work")
try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

// Render a mask-to-rounded-square 1024 canvas with a pink→violet gradient,
// a soft inner highlight, and the "OAE" monogram in a rounded, heavy weight.
func renderBase(size: Int) -> CGImage {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Rounded-square mask (matches macOS app icon radius ~22.5% of edge).
    let radius = s * 0.2237
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Primary gradient: hot pink → violet.
    let colors: [CGColor] = [
        CGColor(red: 0.98, green: 0.34, blue: 0.64, alpha: 1.0),
        CGColor(red: 0.55, green: 0.21, blue: 0.88, alpha: 1.0),
    ]
    let gradient = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: s),
        end: CGPoint(x: s, y: 0),
        options: []
    )

    // Inner top-highlight for dimensionality.
    let hl: [CGColor] = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ]
    let hlGrad = CGGradient(colorsSpace: cs, colors: hl as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(
        hlGrad,
        startCenter: CGPoint(x: s * 0.3, y: s * 0.85),
        startRadius: 0,
        endCenter: CGPoint(x: s * 0.3, y: s * 0.85),
        endRadius: s * 0.7,
        options: []
    )

    // Waveform accent behind the wordmark.
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    let barCount = 11
    let barSpacing = s * 0.062
    let barWidth = s * 0.025
    let baseY = s * 0.23
    let totalWidth = CGFloat(barCount - 1) * barSpacing + barWidth
    let startX = (s - totalWidth) / 2
    for i in 0..<barCount {
        let factor = 0.4 + 0.6 * sin(Double(i) / Double(barCount - 1) * .pi)
        let h = CGFloat(factor) * s * 0.22
        let x = startX + CGFloat(i) * barSpacing
        ctx.setLineCap(.round)
        ctx.setLineWidth(barWidth)
        ctx.move(to: CGPoint(x: x + barWidth / 2, y: baseY))
        ctx.addLine(to: CGPoint(x: x + barWidth / 2, y: baseY + h))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // "OAE" wordmark.
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s * 0.42, weight: .heavy),
        .foregroundColor: NSColor.white,
        .kern: -s * 0.008,
    ]
    let str = NSAttributedString(string: "OAE", attributes: attrs)
    let line = CTLineCreateWithAttributedString(str)
    let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                  blur: s * 0.02,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    let textX = (s - bounds.width) / 2 - bounds.origin.x
    let textY = (s - bounds.height) / 2 - bounds.origin.y - s * 0.03
    ctx.textPosition = CGPoint(x: textX, y: textY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1)
    }
    try data.write(to: url)
}

// Generate master at 1024, then downsample — avoids CoreText aliasing at tiny sizes.
let master = renderBase(size: 1024)
let masterURL = workDir.appendingPathComponent("oae_1024.png")
try writePNG(master, to: masterURL)

// Sizes required by AppIcon.appiconset (macOS).
struct IconSpec {
    let pt: Int
    let scale: Int
    var px: Int { pt * scale }
    var filename: String { "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png" }
}
let specs: [IconSpec] = [
    .init(pt: 16,  scale: 1), .init(pt: 16,  scale: 2),
    .init(pt: 32,  scale: 1), .init(pt: 32,  scale: 2),
    .init(pt: 128, scale: 1), .init(pt: 128, scale: 2),
    .init(pt: 256, scale: 1), .init(pt: 256, scale: 2),
    .init(pt: 512, scale: 1), .init(pt: 512, scale: 2),
]

func resize(_ cg: CGImage, to size: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

// Emit per-spec PNG either by downscaling the master or rendering fresh at small sizes
// (CoreText looks nicer re-rendered below 64).
for spec in specs {
    let img: CGImage
    if spec.px < 64 {
        img = renderBase(size: spec.px)
    } else {
        img = resize(master, to: spec.px)
    }
    let dest = iconsetDir.appendingPathComponent(spec.filename)
    try writePNG(img, to: dest)
    print("wrote \(dest.lastPathComponent) (\(spec.px)x\(spec.px))")
}

// Rewrite Contents.json with explicit filenames so Xcode picks them up.
let contents: [String: Any] = [
    "info": ["author": "xcode", "version": 1],
    "images": specs.map { spec in
        [
            "idiom": "mac",
            "scale": "\(spec.scale)x",
            "size": "\(spec.pt)x\(spec.pt)",
            "filename": spec.filename,
        ]
    },
]
let contentsURL = iconsetDir.appendingPathComponent("Contents.json")
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: contentsURL)
print("wrote \(contentsURL.lastPathComponent)")
print("✓ AppIcon assets regenerated.")
