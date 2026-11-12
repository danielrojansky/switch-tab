import AppKit

enum Icons {
    /// Menu bar glyph: two stacked windows, the front one carrying a Tab arrow.
    /// Template image, so macOS tints it for light and dark menu bars.
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            func path(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
                CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            }
            let back = CGRect(x: 6.6, y: 7.6, width: 10.2, height: 7.8)
            let front = CGRect(x: 1.2, y: 2.6, width: 12, height: 9)

            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.3)
            ctx.addPath(path(back, 2))
            ctx.strokePath()

            // Clear a small gap around the front window so the two shapes stay separate.
            ctx.setBlendMode(.clear)
            ctx.addPath(path(front.insetBy(dx: -1.3, dy: -1.3), 3.4))
            ctx.fillPath()
            ctx.setBlendMode(.normal)
            ctx.addPath(path(front, 2.3))
            ctx.fillPath()

            // Tab arrow, knocked out of the front window.
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(1.4)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let y = front.midY
            ctx.move(to: CGPoint(x: 3.6, y: y))
            ctx.addLine(to: CGPoint(x: 8.6, y: y))
            ctx.move(to: CGPoint(x: 6.7, y: y + 2))
            ctx.addLine(to: CGPoint(x: 8.7, y: y))
            ctx.addLine(to: CGPoint(x: 6.7, y: y - 2))
            ctx.move(to: CGPoint(x: 10.8, y: y + 2.3))
            ctx.addLine(to: CGPoint(x: 10.8, y: y - 2.3))
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Switch Tab"
        return image
    }()

    /// Writes the menu bar glyph, enlarged, to a PNG. Used by `--snapshot-menu-icon`.
    static func writeMenuBarPreview(to path: String) -> Bool {
        let scale = 8
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 18 * scale, pixelsHigh: 18 * scale,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 18, height: 18).fill()
        menuBar.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
