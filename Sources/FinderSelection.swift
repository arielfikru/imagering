// FinderSelection.swift -- reads Finder's selection (AppleScript, blocking) and keeps only image files.
import AppKit
import UniformTypeIdentifiers

enum FinderSelection {
    static var isFinderFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    /// Blocking: NSAppleScript spins the run loop while it waits. Call on the main thread.
    static func selectedPaths() -> (paths: [String], errorNumber: Int?) {
        let src = """
        tell application "Finder"
          set out to ""
          repeat with a in (selection as alias list)
            set out to out & POSIX path of a & linefeed
          end repeat
          return out
        end tell
        """
        guard let script = NSAppleScript(source: src) else { return ([], -1) }
        var err: NSDictionary?
        let desc = script.executeAndReturnError(&err)
        if let e = err { return ([], e[NSAppleScript.errorNumber] as? Int) }
        let s = desc.stringValue ?? ""
        return (s.split(separator: "\n").map(String.init), nil)
    }

    static func imageFiles(_ paths: [String]) -> [URL] {
        paths.map { URL(fileURLWithPath: $0) }.filter(isImage)
    }

    static func isImage(_ url: URL) -> Bool {
        guard let t = UTType(filenameExtension: url.pathExtension) else { return false }
        return t.conforms(to: .image)
    }
}
