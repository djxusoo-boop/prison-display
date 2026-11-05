import AppKit
var failures = 0
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "png" }) {
    let bitmap = NSBitmapImageRep(data: try Data(contentsOf: file))!
    let size = bitmap.pixelsWide
    var minX = size, minY = size, maxX = 0, maxY = 0
    for y in 0..<size { for x in 0..<size {
        if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.5 && min(c.redComponent, c.greenComponent, c.blueComponent) > 0.7 {
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
        }
    } }
    let expected = Double(size-1)/2
    let offsetX = abs(Double(minX+maxX)/2-expected), offsetY = abs(Double(minY+maxY)/2-expected)
    let proportion = Double(maxX-minX+1)/Double(size)
    let ok = offsetX <= max(1, Double(size)*0.01) && offsetY <= max(1, Double(size)*0.01) && proportion >= 0.68 && proportion <= 0.85
    print(ok ? "PASS:" : "FAIL:", file.lastPathComponent, "center offsets", offsetX, offsetY, "mark fraction", proportion)
    if !ok { failures += 1 }
}
print("RESULT", failures, "failures")
exit(failures == 0 ? 0 : 1)
