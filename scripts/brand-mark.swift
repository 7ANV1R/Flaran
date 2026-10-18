// Flaran brand mark: a rounded F whose middle arm is a play symbol.
//   swift scripts/brand-mark.swift [out-dir]    (default build/brand)
// Writes SVG, 1024 px tile and 512 px mark per variant, plus preview.png and construction.png.
// One gap (7) everywhere; in "slant" the stem's top is cut on the play's own top-edge line (≈29°),
// so the cut and the play read as one line. The shipped mark (2-slant) → Resources/Branding/flaran-mark.svg.
import AppKit

// Geometry in a 100×100 box, y down (SVG space). A shape = polygons with per-shape corner radius.
typealias P = CGPoint
struct Poly {
    var pts: [P]; var r: CGFloat; var rs: [CGFloat]? = nil
    init(pts: [P], r: CGFloat, rs: [CGFloat]? = nil) { self.pts = pts; self.r = r; self.rs = rs }
}
struct Mark { let num: Int; let name: String; let polys: [Poly] }

func p(_ x: CGFloat, _ y: CGFloat) -> P { P(x: x, y: y) }

// Rounded polygon: each corner replaced by a quadratic through the vertex.
func corners(_ poly: Poly) -> [(a: P, c: P, b: P)] {
    let n = poly.pts.count
    return (0..<n).map { i in
        let v = poly.pts[i], prev = poly.pts[(i + n - 1) % n], next = poly.pts[(i + 1) % n]
        func toward(_ q: P) -> P {
            let dx = q.x - v.x, dy = q.y - v.y, len = (dx * dx + dy * dy).squareRoot()
            let r = min(poly.rs?[i] ?? poly.r, len / 2)
            return P(x: v.x + dx / len * r, y: v.y + dy / len * r)
        }
        return (toward(prev), v, toward(next))
    }
}

func svgPath(_ polys: [Poly]) -> String {
    polys.map { poly in
        let cs = corners(poly)
        var d = String(format: "M%.2f %.2f", cs[0].b.x, cs[0].b.y)
        for c in cs.dropFirst() + [cs[0]] {
            d += String(format: " L%.2f %.2f Q%.2f %.2f %.2f %.2f", c.a.x, c.a.y, c.c.x, c.c.y, c.b.x, c.b.y)
        }
        return d + " Z"
    }.joined(separator: " ")
}

func bezier(_ polys: [Poly], in rect: NSRect) -> NSBezierPath {
    // map 0..100 (y down) into rect (AppKit y up)
    func m(_ q: P) -> NSPoint { NSPoint(x: rect.minX + q.x / 100 * rect.width, y: rect.maxY - q.y / 100 * rect.height) }
    let path = NSBezierPath()
    for poly in polys {
        let cs = corners(poly)
        path.move(to: m(cs[0].b))
        for c in cs.dropFirst() + [cs[0]] {
            path.line(to: m(c.a))
            // quadratic → cubic
            let a = m(c.a), ctl = m(c.c), b = m(c.b)
            path.curve(to: b,
                       controlPoint1: NSPoint(x: a.x + 2 / 3 * (ctl.x - a.x), y: a.y + 2 / 3 * (ctl.y - a.y)),
                       controlPoint2: NSPoint(x: b.x + 2 / 3 * (ctl.x - b.x), y: b.y + 2 / 3 * (ctl.y - b.y)))
        }
        path.close()
    }
    path.windingRule = .nonZero
    return path
}

// Clip a polygon to the half-plane where (q - o)·n >= 0 (Sutherland–Hodgman).
func clip(_ pts: [P], o: P, n: P) -> [P] {
    func side(_ q: P) -> CGFloat { (q.x - o.x) * n.x + (q.y - o.y) * n.y }
    var out: [P] = []
    for i in pts.indices {
        let a = pts[i], b = pts[(i + 1) % pts.count]
        let sa = side(a), sb = side(b)
        if sa >= 0 { out.append(a) }
        if (sa >= 0) != (sb >= 0) {
            let t = sa / (sa - sb)
            out.append(P(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }
    }
    return out
}
func shift(_ pts: [P], _ dx: CGFloat, _ dy: CGFloat) -> [P] { pts.map { P(x: $0.x + dx, y: $0.y + dy) } }

func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> [P] { [p(x0,y0), p(x1,y0), p(x1,y1), p(x0,y1)] }



// Visual extremes of a rounded polygon (corners are quadratics through the vertex).
func extent(_ poly: Poly) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
    var r = (minX: CGFloat.infinity, maxX: -CGFloat.infinity, minY: CGFloat.infinity, maxY: -CGFloat.infinity)
    for c in corners(poly) {
        for i in 0...24 {
            let t = CGFloat(i) / 24, u = 1 - t
            let x = u * u * c.a.x + 2 * u * t * c.c.x + t * t * c.b.x
            let y = u * u * c.a.y + 2 * u * t * c.c.y + t * t * c.b.y
            r = (min(r.minX, x), max(r.maxX, x), min(r.minY, y), max(r.maxY, y))
        }
    }
    return r
}

/// Optical centering: move halfway from the box centre toward the ink's centre of mass, so the
/// open lower-right of the F doesn't make the mark look pushed left.
func opticallyCentered(_ polys: [Poly]) -> [Poly] {
    let path = bezier(polys, in: NSRect(x: 0, y: 0, width: 100, height: 100))  // y up
    var sx: CGFloat = 0, sy: CGFloat = 0, n: CGFloat = 0
    for i in 0..<400 { for j in 0..<400 {
        let q = NSPoint(x: (CGFloat(i) + 0.5) / 4, y: (CGFloat(j) + 0.5) / 4)
        if path.contains(q) { sx += q.x; sy += 100 - q.y; n += 1 }
    } }
    let dx = (50 - sx / n) / 2, dy = (50 - sy / n) / 2
    print(String(format: "centroid %.1f, %.1f → shift %.1f, %.1f", sx / n, sy / n, dx, dy))
    return polys.map { Poly(pts: shift($0.pts, dx, dy), r: $0.r, rs: $0.rs) }
}


// ───── Soft family: rounded L (stem + top arm) with a detached rounded play. Equal gaps (7). ─────
let m: CGFloat = 20.0 / 36.0                       // play top-edge slope (≈29°)
func L(rsTL: CGFloat = 22) -> Poly {
    Poly(pts: [p(16, 12), p(86, 12), p(86, 34), p(38, 34), p(38, 88), p(16, 88)], r: 0, rs: [rsTL, 11, 11, 7, 11, 11])
}
func play(dy: CGFloat = 0) -> Poly { Poly(pts: [p(45, 41 + dy), p(81, 61 + dy), p(45, 81 + dy)], r: 9) }

// A: pure soft, equal gaps.
let A: [Poly] = [L(), play()]

// B: the stem's top is cut along the play's top-edge line (one continuous ≈29° line), gap 7 across.
func slant(dy: CGFloat) -> [Poly] {
    func y(_ x: CGFloat) -> CGFloat { 41 + dy + m * (x - 45) }       // play top-edge line
    let dv = 7 * (1 + m * m).squareRoot()                          // vertical size of a 7-wide band
    func yUp(_ x: CGFloat) -> CGFloat { y(x) - dv }
    let xMeet = 38 + (34 - yUp(38)) / m                             // where the band's top meets the arm bottom
    let top = Poly(pts: [p(16, 12), p(86, 12), p(86, 34), p(xMeet, 34), p(16, yUp(16))], r: 0, rs: [14, 11, 11, 3, 3])
    let stem = Poly(pts: [p(16, y(16)), p(38, y(38)), p(38, 88), p(16, 88)], r: 0, rs: [3, 3, 11, 11])
    return [top, stem, play(dy: dy)]
}

let marks: [Mark] = [
    Mark(num: 1, name: "soft-pure", polys: opticallyCentered(A)),
    Mark(num: 2, name: "slant", polys: opticallyCentered(slant(dy: 0))),
    Mark(num: 3, name: "slant-low", polys: opticallyCentered(slant(dy: 4))),
]
// MARK: rendering

let outDir = URL(filePath: CommandLine.arguments.dropFirst().first ?? "build/brand")
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func png(_ image: NSImage, px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func tile(_ mark: Mark, size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
        let inset = r.insetBy(dx: size * 0.1, dy: size * 0.1)  // macOS icon grid: 824/1024 body
        let radius = inset.width * 0.225
        let body = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = size * 0.03
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
        shadow.set()
        NSColor(white: 0.07, alpha: 1).setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(white: 0.17, alpha: 1), ending: NSColor(white: 0.065, alpha: 1))!
            .draw(in: body, angle: -90)
        // hairline top highlight
        NSColor.white.withAlphaComponent(0.10).setStroke()
        let rim = NSBezierPath(roundedRect: inset.insetBy(dx: size * 0.002, dy: size * 0.002), xRadius: radius, yRadius: radius)
        rim.lineWidth = size * 0.003
        rim.stroke()
        let markRect = inset.insetBy(dx: inset.width * 0.2, dy: inset.width * 0.2)
        NSGradient(starting: .white, ending: NSColor(white: 0.86, alpha: 1))!
            .draw(in: bezier(mark.polys, in: markRect), angle: -90)
        return true
    }
}

func glyph(_ mark: Mark, size: CGFloat, color: NSColor) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
        color.setFill()
        bezier(mark.polys, in: r).fill()
        return true
    }
}

for m in marks {
    let base = "\(m.num)-\(m.name)"
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><path fill="#000" d="\(svgPath(m.polys))"/></svg>

    """
    try! svg.write(to: outDir.appending(path: "\(base).svg"), atomically: true, encoding: .utf8)
    try! png(tile(m, size: 1024), px: 1024).write(to: outDir.appending(path: "\(base)-1024.png"))
    try! png(glyph(m, size: 512, color: .black), px: 512).write(to: outDir.appending(path: "\(base)-mark.png"))
}

// Preview sheet
let colW: CGFloat = 300, sheetW = colW * CGFloat(marks.count), sheetH: CGFloat = 560
let sheet = NSImage(size: NSSize(width: sheetW, height: sheetH), flipped: true) { _ in
    NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: sheetW, height: sheetH).fill()
    let wifi = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))!
    let search = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))!
    func tinted(_ img: NSImage, _ c: NSColor) -> NSImage {
        NSImage(size: img.size, flipped: false) { r in img.draw(in: r); c.set(); r.fill(using: .sourceAtop); return true }
    }
    for (i, m) in marks.enumerated() {
        let x = CGFloat(i) * colW
        ("\(m.num) · \(m.name)" as NSString).draw(at: NSPoint(x: x + 20, y: 14),
            withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .semibold)])
        tile(m, size: 256).draw(in: NSRect(x: x + 22, y: 40, width: 256, height: 256))
        NSColor.white.setFill(); NSRect(x: x + 40, y: 310, width: 100, height: 100).fill()
        glyph(m, size: 64, color: .black).draw(in: NSRect(x: x + 58, y: 328, width: 64, height: 64))
        NSColor.black.setFill(); NSRect(x: x + 160, y: 310, width: 100, height: 100).fill()
        glyph(m, size: 64, color: .white).draw(in: NSRect(x: x + 178, y: 328, width: 64, height: 64))
        for (j, dark) in [false, true].enumerated() {
            let y = 430 + CGFloat(j) * 50
            let fg: NSColor = dark ? .white : .black
            NSColor(white: dark ? 0.16 : 0.97, alpha: 1).setFill()
            NSRect(x: x + 20, y: y, width: 260, height: 26).fill()
            var cx = x + 40
            for img in [tinted(wifi, fg), tinted(search, fg)] {
                img.draw(in: NSRect(x: cx, y: y + 13 - img.size.height / 2, width: img.size.width, height: img.size.height))
                cx += 34
            }
            glyph(m, size: 18, color: fg).draw(in: NSRect(x: cx, y: y + 4, width: 18, height: 18))
            cx += 34
            glyph(m, size: 16, color: fg).draw(in: NSRect(x: cx, y: y + 5, width: 16, height: 16))
            ("18 / 16 px" as NSString).draw(at: NSPoint(x: cx + 30, y: y + 5),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: dark ? NSColor.lightGray : NSColor.darkGray])
        }
    }
    return true
}
let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appending(path: "preview.png"))
print("ok")


// Construction: the slant variant big, with the play's top-edge line carried through the cut.
do {
    let size: CGFloat = 640
    let sheet = NSImage(size: NSSize(width: size + 60, height: size + 60), flipped: false) { _ in
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 4000, height: 4000).fill()
        let rect = NSRect(x: 30, y: 30, width: size, height: size)
        func pt(_ q: P) -> NSPoint { NSPoint(x: rect.minX + q.x / 100 * size, y: rect.maxY - q.y / 100 * size) }
        NSColor(white: 0.1, alpha: 1).setFill(); bezier(slant(dy: 0), in: rect).fill()
        NSColor.systemPink.setStroke()
        let dv = 7 * (1 + m * m).squareRoot()
        for off in [0, -dv] {
            let l = NSBezierPath()
            l.move(to: pt(p(4, 41 + off + m * (4 - 45)))); l.line(to: pt(p(96, 41 + off + m * (96 - 45))))
            l.lineWidth = 1.5; l.stroke()
        }
        ("one angle: the stem cut and the play's top edge share a ≈29° line; one 7-unit gap" as NSString)
            .draw(at: NSPoint(x: 30, y: 8), withAttributes: [.font: NSFont.systemFont(ofSize: 15)])
        return true
    }
    let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: outDir.appending(path: "construction.png"))
}
