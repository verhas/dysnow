#!/usr/bin/env swift
// Draws Dysnow's app icon and writes every size the asset catalog needs:
//   swift tools/make_icon.swift Dysnow/Assets.xcassets/AppIcon.appiconset
// A page of text with sound waves coming off it -- text turned into speech --
// on a rounded square drawn to Apple's macOS icon grid.

import AppKit
import CoreGraphics

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(in context: CGContext) {
    // Apple's grid: an 824-point square in the 1024 canvas, room for the shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
    context.addPath(shape)
    context.setFillColor(color(0x0F766E))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let background = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: [color(0x5EEAD4), color(0x0D9488), color(0x134E4A)] as CFArray,
                                locations: [0, 0.55, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 220, y: 924), end: CGPoint(x: 800, y: 100), options: [])
    // A soft light from the top, as on glass.
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(sheen, startCenter: CGPoint(x: 400, y: 900), startRadius: 0,
                               endCenter: CGPoint(x: 400, y: 900), endRadius: 560, options: [])

    // The page, with a shadow of its own.
    let page = CGRect(x: 210, y: 240, width: 380, height: 520)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x042F2E, 0.45))
    context.addPath(CGPath(roundedRect: page, cornerWidth: 44, cornerHeight: 44, transform: nil))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()

    // Lines of text on it, the last one short, as a paragraph ends.
    context.setFillColor(color(0x0F766E, 0.75))
    for (index, width) in [CGFloat(280), 280, 280, 200, 280, 150].enumerated() {
        let y = page.maxY - 95 - CGFloat(index) * 66
        context.addPath(CGPath(roundedRect: CGRect(x: page.minX + 50, y: y, width: width, height: 26),
                               cornerWidth: 13, cornerHeight: 13, transform: nil))
        context.fillPath()
    }

    // Sound waves: the text read aloud.
    context.setStrokeColor(color(0xFFFFFF))
    context.setLineCap(.round)
    let waveCenter = CGPoint(x: 600, y: 500)
    for (index, radius) in [CGFloat(90), 160, 230].enumerated() {
        context.setLineWidth(34)
        context.setAlpha(1 - CGFloat(index) * 0.22)
        context.addArc(center: waveCenter, radius: radius, startAngle: -.pi / 4.5, endAngle: .pi / 4.5, clockwise: false)
        context.strokePath()
    }
    context.setAlpha(1)
    context.restoreGState()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: context)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let folder = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
var images: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(size: points * scale).write(to: folder.appending(path: name))
        images.append(#"    {"filename":"\#(name)","idiom":"mac","scale":"\#(scale)x","size":"\#(points)x\#(points)"}"#)
    }
}
let contents = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : {\"author\":\"xcode\",\"version\":1}\n}\n"
try! contents.write(to: folder.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(images.count) images to \(folder.path)")
