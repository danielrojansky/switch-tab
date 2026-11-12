// Draws the Switch Tab app icon and writes Resources/AppIcon.icns.
// Run from the project root: swift scripts/make-icon.swift [preview.png]
// Needs only Command Line Tools (CoreGraphics, iconutil).
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Draws the icon into a 1024 x 1024 context (origin bottom-left).
func drawIcon(_ ctx: CGContext) {
    let space = CGColorSpaceCreateDeviceRGB()
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = rounded(plate, 186)

    // Plate with a soft drop shadow, like other macOS icons.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.32))
    ctx.addPath(platePath)
    ctx.setFillColor(color(0x4F46E5))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let background = CGGradient(colorsSpace: space,
                                colors: [color(0x38BDF8), color(0x4F6BF5), color(0x7C3AED)] as CFArray,
                                locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: plate.minX, y: plate.maxY),
                           end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
    // Gentle top sheen.
    let sheen = CGGradient(colorsSpace: space,
                           colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: plate.maxY),
                           end: CGPoint(x: 512, y: plate.midY), options: [])
    ctx.restoreGState()

    // Back window: translucent, up and to the right.
    let back = CGRect(x: 400, y: 470, width: 400, height: 300)
    ctx.addPath(rounded(back, 46))
    ctx.setFillColor(color(0xFFFFFF, 0.34))
    ctx.fillPath()
    ctx.addPath(rounded(back.insetBy(dx: 5, dy: 5), 41))
    ctx.setStrokeColor(color(0xFFFFFF, 0.6))
    ctx.setLineWidth(10)
    ctx.strokePath()

    // Front window: solid white, down and to the left.
    let front = CGRect(x: 224, y: 254, width: 470, height: 360)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x1E1B4B, 0.45))
    ctx.addPath(rounded(front, 52))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // Title bar dots.
    for (index, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
        ctx.setFillColor(color(hex))
        ctx.fillEllipse(in: CGRect(x: front.minX + 40 + CGFloat(index) * 50, y: front.maxY - 72, width: 32, height: 32))
    }

    // Tab arrow (arrow running into a bar) in the window body.
    let arrowColors = CGGradient(colorsSpace: space, colors: [color(0x3B82F6), color(0x7C3AED)] as CFArray,
                                 locations: [0, 1])!
    let midY = front.minY + 138
    let left = front.minX + 92, right = front.maxX - 92
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: left, y: midY))
    arrow.addLine(to: CGPoint(x: right - 62, y: midY))
    arrow.move(to: CGPoint(x: right - 136, y: midY + 74))
    arrow.addLine(to: CGPoint(x: right - 62, y: midY))
    arrow.addLine(to: CGPoint(x: right - 136, y: midY - 74))
    arrow.move(to: CGPoint(x: right, y: midY + 84))
    arrow.addLine(to: CGPoint(x: right, y: midY - 84))
    // Stroke the shape, then paint the gradient only where the stroke landed.
    ctx.saveGState()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(arrow)
    ctx.setStrokeColor(color(0x3B82F6))
    ctx.setLineWidth(44)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.setBlendMode(.sourceIn)
    ctx.drawLinearGradient(arrowColors, start: CGPoint(x: left, y: midY + 84),
                           end: CGPoint(x: right, y: midY - 84),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = graphics.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let arguments = CommandLine.arguments
if arguments.count > 1 {
    try render(pixels: 1024).write(to: URL(fileURLWithPath: arguments[1]))
    print("Wrote \(arguments[1])")
    exit(0)
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("SwitchTab-\(getpid()).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try tool.run()
tool.waitUntilExit()
try? fm.removeItem(at: iconset)
guard tool.terminationStatus == 0 else { exit(1) }
print("Wrote Resources/AppIcon.icns")
