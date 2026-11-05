import AppKit
let directory = CommandLine.arguments[1]
let logo = NSImage(contentsOfFile: directory + "/PrisonLogo.jpg")!
let iconset = directory + "/PrisonDisplay.iconset"
// Find the exact mark bounds within the original O; centre the mark, not its old crop.
let pixels = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: directory + "/PrisonLogo.jpg")))!
var minX = 745, minY = 291, maxX = 577, maxY = 90
for y in 90..<271 { for x in 577..<745 {
    if let c = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), min(c.redComponent, c.greenComponent, c.blueComponent) > 0.7 {
        minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
    }
} }
let symbol = NSRect(x: minX-2, y: pixels.pixelsHigh-maxY-3, width: maxX-minX+5, height: maxY-minY+5)
print("Symbol bounds:", symbol)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16,32,128,256,512] {
    for scale in [1,2] {
        let size = base*scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size*4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let n = CGFloat(size)
        let rect = NSRect(x: n*0.04, y: n*0.04, width: n*0.92, height: n*0.92)
        NSColor(calibratedWhite: 0, alpha: 1).setFill()
        let shape = NSBezierPath(roundedRect: rect, xRadius: n*0.20, yRadius: n*0.20); shape.fill()
        
        // Exact symbol from the supplied logo, with its original black background.
        let factor = n*0.80/max(symbol.width, symbol.height)
        let mark = NSRect(x: (n-symbol.width*factor)/2, y: (n-symbol.height*factor)/2, width: symbol.width*factor, height: symbol.height*factor)
        logo.draw(in: mark, from: symbol, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: iconset + "/icon_\(base)x\(base)\(suffix).png"))
    }
}
