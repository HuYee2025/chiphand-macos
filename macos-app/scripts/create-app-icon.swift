import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: create-app-icon.swift <source.png> <output.png>\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = NSImage(contentsOf: inputURL) else {
    fputs("Unable to load source icon.\n", stderr)
    exit(1)
}

let canvasSize = NSSize(width: 1024, height: 1024)
let icon = NSImage(size: canvasSize)
icon.lockFocus()

NSColor.clear.setFill()
NSRect(origin: .zero, size: canvasSize).fill()

guard let context = NSGraphicsContext.current else {
    fputs("Unable to create graphics context.\n", stderr)
    exit(1)
}

context.imageInterpolation = .high
let tileRect = NSRect(x: 40, y: 40, width: 944, height: 944)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 210, yRadius: 210)
tilePath.addClip()
source.draw(
    in: tileRect,
    from: NSRect(origin: .zero, size: source.size),
    operation: .sourceOver,
    fraction: 1
)

icon.unlockFocus()

guard
    let tiff = icon.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Unable to encode icon PNG.\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
