// probe.swift -- prints what ImageIO sees: size, type, EXIF/GPS/TIFF Make, PNG description, corner colours.
import AppKit
import ImageIO

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
guard let src = CGImageSourceCreateWithURL(url, nil) else { print("unreadable"); exit(1) }
let uti = (CGImageSourceGetType(src) as String?) ?? "none"
let props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
let w = props[kCGImagePropertyPixelWidth] as? Int ?? -1, h = props[kCGImagePropertyPixelHeight] as? Int ?? -1
let exif = props[kCGImagePropertyExifDictionary] != nil
let gps = props[kCGImagePropertyGPSDictionary] != nil
let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
let make = tiff?[kCGImagePropertyTIFFMake] != nil
let exifDict = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
let dt = exifDict?[kCGImagePropertyExifDateTimeOriginal] != nil
let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any]
let pngDesc = png?[kCGImagePropertyPNGDescription] != nil
// corner colours: draw into a 64x64 RGBA buffer, average an 8x8 patch in each corner (row 0 = top)
var buf = [UInt8](repeating: 0, count: 64 * 64 * 4)
if let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
    buf.withUnsafeMutableBytes { p in
        let c = CGContext(data: p.baseAddress, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.interpolationQuality = .high
        c.draw(img, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    }
}
func patch(_ x0: Int, _ y0: Int) -> String {
    var r = 0, g = 0, b = 0
    for y in y0..<(y0 + 8) { for x in x0..<(x0 + 8) { let i = (y * 64 + x) * 4; r += Int(buf[i]); g += Int(buf[i + 1]); b += Int(buf[i + 2]) } }
    return "\(r / 64),\(g / 64),\(b / 64)"
}
// Corners as seen on screen: TL=(0,0) top-left. Memory row 0 is the top row of the drawn image.
print("size=\(w)x\(h) uti=\(uti) exif=\(exif ? 1 : 0) dt=\(dt ? 1 : 0) gps=\(gps ? 1 : 0) make=\(make ? 1 : 0) pngdesc=\(pngDesc ? 1 : 0)")
print("TL=\(patch(0, 0)) TR=\(patch(56, 0)) BL=\(patch(0, 56)) BR=\(patch(56, 56))")
