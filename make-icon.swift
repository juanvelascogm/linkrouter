import Cocoa

// Renders AppIcon.icns: the menu bar symbol in white on a rounded gradient tile.
let px = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let tile = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.36, green: 0.55, blue: 1.0, alpha: 1),
                    NSColor(red: 0.33, green: 0.24, blue: 0.86, alpha: 1)])!
    .draw(in: tile, angle: -90)

let cfg = NSImage.SymbolConfiguration(pointSize: 460, weight: .semibold)
let sym = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)!
    .withSymbolConfiguration(cfg)!
let white = NSImage(size: sym.size)
white.lockFocus()
sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
NSColor.white.set()
NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop)
white.unlockFocus()
white.draw(at: NSPoint(x: 512 - sym.size.width / 2, y: 512 - sym.size.height / 2),
           from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon-1024.png"))
