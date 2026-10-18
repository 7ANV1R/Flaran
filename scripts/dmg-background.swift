// Draws the DMG window background: soft wallpaper, an arrow from the app to Applications, one line of help.
//   swift scripts/dmg-background.swift out.png
// 1280x800 px = a 640x400 pt window at 2x. Icons sit at (160, 190) and (480, 190) in window points.
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "build/dmg-background.png"
let size = NSSize(width: 1280, height: 800)
let image = NSImage(size: size, flipped: true) { rect in
    NSGradient(colors: [NSColor(calibratedRed: 0.84, green: 0.91, blue: 1.00, alpha: 1),
                        NSColor(calibratedRed: 0.90, green: 0.95, blue: 1.00, alpha: 1),
                        NSColor(calibratedRed: 0.80, green: 0.90, blue: 1.00, alpha: 1)])!
        .draw(in: rect, angle: -30)
    // Soft out-of-focus blue glows.
    for (center, radius, color) in [(NSPoint(x: 1050, y: 120), 520.0, NSColor(calibratedRed: 0.55, green: 0.75, blue: 1.0, alpha: 0.45)),
                                     (NSPoint(x: 180, y: 720), 480.0, NSColor(calibratedRed: 0.45, green: 0.80, blue: 0.98, alpha: 0.35))] {
        NSGradient(starting: color, ending: color.withAlphaComponent(0))!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }

    // A curved arrow arcing from the app (x 160 pt) over to Applications (x 480 pt); icons sit at y 190 pt.
    let start = NSPoint(x: 470, y: 330), end = NSPoint(x: 800, y: 330)
    let c1 = NSPoint(x: 540, y: 190), c2 = NSPoint(x: 730, y: 190)
    let arc = NSBezierPath()
    arc.move(to: start)
    arc.curve(to: end, controlPoint1: c1, controlPoint2: c2)
    arc.lineWidth = 7
    arc.lineCapStyle = .round
    arc.setLineDash([2, 16], count: 2, phase: 0)
    let ink = NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.86, alpha: 0.75)
    ink.setStroke()
    arc.stroke()
    // Arrowhead along the curve's end tangent (c2 -> end).
    let angle = atan2(end.y - c2.y, end.x - c2.x)
    func tip(_ a: CGFloat) -> NSPoint { NSPoint(x: end.x - 30 * cos(angle + a), y: end.y - 30 * sin(angle + a)) }
    let head = NSBezierPath()
    head.move(to: tip(0.5)); head.line(to: end); head.line(to: tip(-0.5))
    head.lineWidth = 7
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    let style = NSMutableParagraphStyle()
    style.alignment = .center
    ("Drag Flaran into Applications" as NSString).draw(
        in: NSRect(x: 0, y: 640, width: size.width, height: 60),
        withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .medium),
                         .foregroundColor: NSColor(white: 0.2, alpha: 0.75), .paragraphStyle: style])
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
rep.size = NSSize(width: 640, height: 400)  // 2x
try! rep.representation(using: .png, properties: [:])!.write(to: URL(filePath: out))
print(out)
