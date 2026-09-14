import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("Pass an output .iconset directory.") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func drawIcon(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw NSError(domain: "Icon", code: 1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 192, yRadius: 192)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.18, blue: 0.20, alpha: 1),
               ending: NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.16, alpha: 1))?.draw(in: background, angle: -45)
    NSShadow().set()
    func tile(_ rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 36, yRadius: 36).fill()
        NSColor.white.withAlphaComponent(0.13).setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 35, yRadius: 35)
        border.lineWidth = 2
        border.stroke()
    }
    tile(NSRect(x: 224, y: 236, width: 236, height: 552), color: NSColor(calibratedRed: 0.28, green: 0.77, blue: 0.66, alpha: 1))
    tile(NSRect(x: 490, y: 528, width: 310, height: 260), color: NSColor(calibratedRed: 0.57, green: 0.52, blue: 0.91, alpha: 1))
    tile(NSRect(x: 490, y: 236, width: 310, height: 260), color: NSColor(calibratedRed: 0.20, green: 0.34, blue: 0.38, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Icon", code: 2) }
    return data
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try drawIcon(size: points * scale).write(to: url, options: .atomic)
    }
}
