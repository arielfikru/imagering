// pbexit.swift -- writes the pasteboard then exits at once (test helper for flush-on-exit behaviour).
import AppKit
let f = URL(fileURLWithPath: CommandLine.arguments[1])
let png = NSBitmapImageRep(data: try! Data(contentsOf: f))!.representation(using: .png, properties: [:])!
let pb = NSPasteboard.general
pb.clearContents()
let item = NSPasteboardItem()
item.setData(png, forType: .png)
item.setData(Data(f.absoluteString.utf8), forType: .fileURL)
let ok = pb.writeObjects([item])
if CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "spin" { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5)) }
exit(ok ? 0 : 1)
