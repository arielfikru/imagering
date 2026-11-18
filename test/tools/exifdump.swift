// exifdump.swift -- prints the top-level metadata dictionaries and their keys (test helper).
import Foundation
import ImageIO
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [String: Any]
for (k, v) in p.sorted(by: { $0.key < $1.key }) {
    if let d = v as? [String: Any] { print("\(k): \(d.keys.sorted().joined(separator: ", "))") } else { print("\(k) = \(v)") }
}
