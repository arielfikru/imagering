// Prints WCAG contrast of white text vs the composited pixel at given (x,y) points (in points, y-down from image top-left)
// usage: contrast <png> x,y [x,y ...]
import AppKit
func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
let a = CommandLine.arguments
let rep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[1])))!
for s in a.dropFirst(2) {
    let xy = s.split(separator: ",").map { Int($0)! }
    let c = rep.colorAt(x: xy[0] * 2, y: xy[1] * 2)!.usingColorSpace(.sRGB)!
    let L = 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    print(String(format: "%@ rgb=(%.0f,%.0f,%.0f) contrast vs white = %.2f", s, c.redComponent*255, c.greenComponent*255, c.blueComponent*255, 1.05 / (L + 0.05)))
}
