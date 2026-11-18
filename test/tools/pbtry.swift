// pbtry.swift -- tries pasteboard write styles and prints the resulting types (test helper).
import AppKit
let f = URL(fileURLWithPath: CommandLine.arguments[1])
let png = NSBitmapImageRep(data: try! Data(contentsOf: f))!.representation(using: .png, properties: [:])!
let pb = NSPasteboard.general
let mode = CommandLine.arguments[2]
pb.clearContents()
switch mode {
case "A": // separate declare + setString/setData
    pb.declareTypes([.fileURL, .png], owner: nil)
    pb.setString(f.absoluteString, forType: .fileURL)
    pb.setData(png, forType: .png)
case "B": // item with URL as NSURL + png data
    let item = NSPasteboardItem()
    item.setData(png, forType: .png)
    item.setData(Data(f.absoluteString.utf8), forType: .fileURL)
    print("writeObjects=\(pb.writeObjects([item]))")
case "C": // NSURL object alongside NSPasteboardItem png
    let item = NSPasteboardItem()
    item.setData(png, forType: .png)
    print("writeObjects=\(pb.writeObjects([item, f as NSURL]))")
default: break
}
print("types=\((pb.types ?? []).map { $0.rawValue })")
print("fileURL=\(pb.string(forType: .fileURL) ?? "none") urlObjects=\(pb.readObjects(forClasses: [NSURL.self], options: nil)?.count ?? 0)")
