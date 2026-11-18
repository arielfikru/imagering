// clipcheck.swift -- lists pasteboard types and the file URL on the general pasteboard (test helper).
import AppKit
let pb = NSPasteboard.general
print("types: \((pb.types ?? []).map { $0.rawValue }.joined(separator: ", "))")
print("fileURL: \(pb.string(forType: .fileURL) ?? "none")")
print("png bytes: \(pb.data(forType: .png)?.count ?? 0)")
