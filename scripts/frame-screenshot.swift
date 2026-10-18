// Places a capture in the top-right corner of a laptop: light studio background, aluminium lid edge,
// black bezel, then the screen. The screen runs off the left and bottom edges, like a cropped product
// shot.   swift scripts/frame-screenshot.swift in.png out.png
import AppKit

let args = CommandLine.arguments
let src = NSImage(contentsOfFile: args[1])!
let rep = src.representations.first!
let sw = CGFloat(rep.pixelsWide), sh = CGFloat(rep.pixelsHigh)

let studio: CGFloat = 110      // background visible above and right of the lid
let rim: CGFloat = 14          // aluminium edge
let bezel: CGFloat = 40        // black glass around the screen
let canvas = NSSize(width: sw + bezel + rim + studio, height: sh + bezel + rim + studio)

let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
let all = NSRect(origin: .zero, size: canvas)

// Studio background.
NSGradient(colors: [NSColor(white: 0.97, alpha: 1), NSColor(white: 0.90, alpha: 1)])!.draw(in: all, angle: -60)

// Shapes extend past the left and bottom edges so only the top-right corner shows.
func corner(inset: CGFloat, radius: CGFloat) -> NSBezierPath {
    let r = NSRect(x: -400, y: -400, width: canvas.width - studio - inset + 400, height: canvas.height - studio - inset + 400)
    return NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

// Lid with a soft shadow, a light aluminium edge and a thin highlight.
let lid = corner(inset: 0, radius: 86)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
shadow.shadowBlurRadius = 60
shadow.shadowOffset = NSSize(width: 0, height: -24)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor(white: 0.80, alpha: 1).setFill()
lid.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [NSColor(white: 0.93, alpha: 1), NSColor(white: 0.74, alpha: 1)])!.draw(in: lid, angle: -45)

// Bezel.
let glass = corner(inset: rim, radius: 74)
NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.06, alpha: 1).setFill()
glass.fill()

// Screen.
let screenRect = NSRect(x: canvas.width - studio - rim - bezel - sw, y: canvas.height - studio - rim - bezel - sh,
                        width: sw, height: sh)
let screenShape = NSBezierPath(roundedRect: NSRect(x: screenRect.minX - 400, y: screenRect.minY - 400,
                                                   width: sw + 400, height: sh + 400), xRadius: 36, yRadius: 36)
NSGraphicsContext.saveGraphicsState()
screenShape.addClip()
src.draw(in: screenRect, from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

try! out.representation(using: .png, properties: [:])!.write(to: URL(filePath: args[2]))
