import AppKit

/// Picks a vivid signature color from an app's icon, used to tint the selection.
enum AppColor {
    private static var cache: [String: NSColor] = [:]

    static func color(for app: NSRunningApplication) -> NSColor {
        let key = app.bundleIdentifier ?? "pid-\(app.processIdentifier)"
        if let cached = cache[key] { return cached }
        let color = app.icon.flatMap(dominant) ?? .controlAccentColor
        cache[key] = color
        return color
    }

    /// Average of the icon's pixels, weighted by how saturated each one is, so
    /// white plates and gray shadows do not wash the result out.
    private static func dominant(of icon: NSImage) -> NSColor? {
        let side = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return nil }

        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for index in 0..<(side * side) {
            let alpha = Double(data[index * 4 + 3]) / 255
            guard alpha > 0.5 else { continue }
            // Pixels are premultiplied; undo that before measuring.
            let r = Double(data[index * 4]) / 255 / alpha
            let g = Double(data[index * 4 + 1]) / 255 / alpha
            let b = Double(data[index * 4 + 2]) / 255 / alpha
            let high = max(r, g, b), low = min(r, g, b)
            let saturation = high == 0 ? 0 : (high - low) / high
            let weight = saturation * saturation * high
            red += r * weight
            green += g * weight
            blue += b * weight
            total += weight
        }
        guard total > 1.5 else { return nil } // a gray icon: keep the system accent
        let base = NSColor(deviceRed: min(1, red / total), green: min(1, green / total),
                           blue: min(1, blue / total), alpha: 1)
        // Keep the tint lively enough to read as a glow.
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(deviceHue: hue, saturation: max(0.55, saturation), brightness: max(0.8, brightness), alpha: 1)
    }
}
