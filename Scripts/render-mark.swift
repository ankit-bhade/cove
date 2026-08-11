#!/usr/bin/env swift
//
//  render-mark.swift
//
//  Regenerates every PNG derived from the Cove mark, straight into the asset
//  catalog. CoreGraphics only — no dependencies, no Xcode target.
//
//      swift Scripts/render-mark.swift          # run from the repo root
//
//  The mark is one disc cut once: a circle of radius 36 in a 0…100 design
//  space, split by a 6-wide vertical kerf centred at x = 60, both pieces on
//  the centreline. It is symmetric about the horizontal axis, so CoreGraphics'
//  bottom-left origin needs no compensation.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

func srgb(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1)
}

struct Colorway {
    let ground: CGColor
    let major: CGColor
    let minor: CGColor
}

/// The app icon keeps an ink ground in both appearances — a dark tile holds
/// its edge against any wallpaper. Its ember runs brighter than the app's
/// accent, which has room to sit lighter on ink than it does on paper.
let iconLight = Colorway(ground: srgb(0x24211D), major: srgb(0xF2EEE7), minor: srgb(0xD9812F))
let iconDark = Colorway(ground: srgb(0x161513), major: srgb(0xF2EEE7), minor: srgb(0xE0A264))
/// Tinted icons are graded by the system from greyscale artwork.
let iconTinted = Colorway(ground: srgb(0x000000), major: srgb(0xFFFFFF), minor: srgb(0x9E9E9E))

/// The launch tile is the in-app mark, so it follows the app's own appearance.
let markLight = Colorway(ground: srgb(0xF6F3EE), major: srgb(0x24211D), minor: srgb(0x9E5827))
let markDark = Colorway(ground: srgb(0x171310), major: srgb(0xEDE6DA), minor: srgb(0xE0A264))

// MARK: - Drawing

let cornerRatio: CGFloat = 0.2237
/// Apple's macOS icon grid: the tile is 824 of a 1024 canvas, centred.
let macTileRatio: CGFloat = 824.0 / 1024.0

func makeContext(_ side: Int) -> CGContext {
    let context = CGContext(
        data: nil, width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    return context
}

func drawTile(_ context: CGContext, in tile: CGRect, corner: CGFloat, _ colors: Colorway) {
    context.saveGState()
    if corner > 0 {
        context.addPath(
            CGPath(roundedRect: tile, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.clip()
    } else {
        context.clip(to: tile)
    }

    context.setFillColor(colors.ground)
    context.fill(tile)

    let unit = tile.width / 100
    let disc = CGRect(
        x: tile.minX + 14 * unit, y: tile.minY + 14 * unit,
        width: 72 * unit, height: 72 * unit)

    context.saveGState()
    context.clip(to: CGRect(x: tile.minX, y: tile.minY, width: 57 * unit, height: tile.height))
    context.setFillColor(colors.major)
    context.fillEllipse(in: disc)
    context.restoreGState()

    context.saveGState()
    context.clip(
        to: CGRect(x: tile.minX + 63 * unit, y: tile.minY, width: 37 * unit, height: tile.height))
    context.setFillColor(colors.minor)
    context.fillEllipse(in: disc)
    context.restoreGState()

    context.restoreGState()
}

func write(_ context: CGContext, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        FileHandle.standardError.write(Data("failed to encode \(path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(path)")
}

/// Full-bleed square, no rounding — the system masks iOS icons itself.
func renderFullBleed(_ side: Int, _ colors: Colorway, to path: String) {
    let context = makeContext(side)
    let box = CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))
    drawTile(context, in: box, corner: 0, colors)
    write(context, to: path)
}

/// Rounded tile inset in a transparent canvas, on Apple's macOS grid.
func renderMac(_ side: Int, _ colors: Colorway, to path: String) {
    let context = makeContext(side)
    let canvas = CGFloat(side)
    let tileSide = (canvas * macTileRatio).rounded()
    let origin = ((canvas - tileSide) / 2).rounded()
    let tile = CGRect(x: origin, y: origin, width: tileSide, height: tileSide)
    drawTile(context, in: tile, corner: tileSide * cornerRatio, colors)
    write(context, to: path)
}

/// The in-app tile: rounded square filling the canvas, no hairline edge (that
/// is a SwiftUI overlay on CoveMark, not part of the artwork).
func renderMarkTile(_ side: Int, _ colors: Colorway, to path: String) {
    let context = makeContext(side)
    let canvas = CGFloat(side)
    let tile = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    drawTile(context, in: tile, corner: canvas * cornerRatio, colors)
    write(context, to: path)
}

// MARK: - Output

let appIcon = "Cove/Assets.xcassets/AppIcon.appiconset"
let dockDark = "Cove/Assets.xcassets/DockIconDark.imageset"
let launch = "Cove/Assets.xcassets/LaunchIcon.imageset"

guard FileManager.default.fileExists(atPath: appIcon) else {
    FileHandle.standardError.write(
        Data("run this from the repo root — \(appIcon) not found\n".utf8))
    exit(1)
}

renderFullBleed(1024, iconLight, to: "\(appIcon)/icon-ios-1024.png")
renderFullBleed(1024, iconDark, to: "\(appIcon)/icon-ios-dark-1024.png")
renderFullBleed(1024, iconTinted, to: "\(appIcon)/icon-ios-tinted-1024.png")

for side in [16, 32, 64, 128, 256, 512, 1024] {
    renderMac(side, iconLight, to: "\(appIcon)/icon-mac-\(side).png")
}

renderMac(512, iconDark, to: "\(dockDark)/dock-icon-dark-512.png")
renderMac(1024, iconDark, to: "\(dockDark)/dock-icon-dark-1024.png")

for side in [128, 256, 384] {
    renderMarkTile(side, markLight, to: "\(launch)/launch-\(side).png")
    renderMarkTile(side, markDark, to: "\(launch)/launch-\(side)-dark.png")
}

print("done — 18 files")
