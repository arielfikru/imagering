// make_fixtures.swift -- writes the test inputs (test helper, not app code).
// Each image has a RED block at the top-left corner so rotations can be checked by pixel.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

/// Noisy RGB image (so JPEG cannot be tiny) with a red 300x300 block at top-left.
func makeImage(w: Int, h: Int, noise: Bool) -> CGImage {
    let bpr = w * 4
    var px = [UInt8](repeating: 0, count: bpr * h)
    var rng = SystemRandomNumberGenerator()
    for y in 0..<h { for x in 0..<w {
        let i = y * bpr + x * 4
        if noise {
            px[i] = UInt8.random(in: 0...255, using: &rng); px[i + 1] = UInt8.random(in: 0...255, using: &rng); px[i + 2] = UInt8.random(in: 0...255, using: &rng)
        } else { px[i] = 90; px[i + 1] = 160; px[i + 2] = 220 }
        px[i + 3] = 255
        if x < 300 && y < 300 { px[i] = 255; px[i + 1] = 0; px[i + 2] = 0 }
    } }
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = px.withUnsafeMutableBytes { buf -> CGImage? in
        let c = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr,
                          space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        return c?.makeImage()
    }
    return ctx!
}

let exif: [CFString: Any] = [
    kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:01 10:00:00"],
    kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestCam", kCGImagePropertyTIFFModel: "T1"],
    kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 6.2, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 106.8, kCGImagePropertyGPSLongitudeRef: "E"],
]

func write(_ img: CGImage, to path: String, type: String, props: [CFString: Any]) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let d = CGImageDestinationCreateWithURL(url, type as CFString, 1, nil) else { print("cannot create \(path)"); return }
    CGImageDestinationAddImage(d, img, props as CFDictionary)
    print(CGImageDestinationFinalize(d) ? "wrote \(path)" : "FAILED \(path)")
}

write(makeImage(w: 4000, h: 3000, noise: true), to: "\(outDir)/holiday photo.jpg", type: "public.jpeg",
      props: exif.merging([kCGImageDestinationLossyCompressionQuality: 0.95]) { a, _ in a })
write(makeImage(w: 1600, h: 1000, noise: false), to: "\(outDir)/shot.png", type: "public.png",
      props: [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "private description"]])
write(makeImage(w: 200, h: 100, noise: false), to: "\(outDir)/tiny.png", type: "public.png", props: [:])
write(makeImage(w: 3000, h: 2000, noise: true), to: "\(outDir)/clip.heic", type: "public.heic",
      props: exif.merging([kCGImageDestinationLossyCompressionQuality: 0.9]) { a, _ in a })
try? "just text, not an image\n".write(toFile: "\(outDir)/notes.txt", atomically: true, encoding: .utf8)
