// pngdiff.swift -- counts differing pixels between two PNGs (test helper).
import AppKit
let a = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
let b = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))!
print("size a=\(a.pixelsWide)x\(a.pixelsHigh) b=\(b.pixelsWide)x\(b.pixelsHigh)")
var n = 0, maxd = 0, minx = Int.max, maxx = -1, miny = Int.max, maxy = -1
for y in 0..<min(a.pixelsHigh, b.pixelsHigh) { for x in 0..<min(a.pixelsWide, b.pixelsWide) {
    let p = a.colorAt(x: x, y: y)!, q = b.colorAt(x: x, y: y)!
    let d = max(abs(p.redComponent-q.redComponent), abs(p.greenComponent-q.greenComponent), abs(p.blueComponent-q.blueComponent), abs(p.alphaComponent-q.alphaComponent))
    if d > 0.0001 { n += 1; maxd = max(maxd, Int(d*255)); minx = min(minx,x); maxx = max(maxx,x); miny = min(miny,y); maxy = max(maxy,y) }
} }
print("differing pixels=\(n) maxChannelDiff=\(maxd)/255 bbox x=\(minx)...\(maxx) y=\(miny)...\(maxy)")
