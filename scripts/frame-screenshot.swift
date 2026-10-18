// Turns a raw capture into a floating "screen": rounded corners, hairline border, soft drop shadow,
// on a transparent canvas.   swift scripts/frame-screenshot.swift in.png out.png
import AppKit

let args = CommandLine.arguments
let src = NSImage(contentsOfFile: args[1])!
let rep = src.representations.first!
let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
let pad: CGFloat = 80, radius: CGFloat = 28
let canvas = NSSize(width: w + pad * 2, height: h + pad * 2)

let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
let screen = NSRect(x: pad, y: pad, width: w, height: h)
let shape = NSBezierPath(roundedRect: screen, xRadius: radius, yRadius: radius)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 50
shadow.shadowOffset = NSSize(width: 0, height: -22)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.white.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.addClip()
src.draw(in: screen, from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

NSColor.black.withAlphaComponent(0.12).setStroke()
shape.lineWidth = 2
shape.stroke()
NSGraphicsContext.restoreGraphicsState()

try! out.representation(using: .png, properties: [:])!.write(to: URL(filePath: args[2]))
