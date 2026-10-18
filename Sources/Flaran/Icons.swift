import AppKit
import SwiftUI

extension Glyph {
    /// A template image (tints with the surrounding colour) at `size` points.
    func image(size: CGFloat) -> NSImage {
        let key = "\(rawValue.hashValue)-\(size)"
        if let cached = iconCache[key] { return cached }
        let image = NSImage(data: Data(rawValue.utf8)) ?? NSImage()
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        iconCache[key] = image
        return image
    }
}

private var iconCache: [String: NSImage] = [:]

/// A stroke icon that takes `foregroundStyle` like an SF Symbol.
struct Icon: View {
    let icon: Glyph
    var size: CGFloat = 16

    init(_ icon: Glyph, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Image(nsImage: icon.image(size: size))
            .renderingMode(.template)
            .frame(width: size, height: size)
    }
}
