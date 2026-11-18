// Actions.swift -- what each RingModel item does. Originals are never modified.
// Item ids: "<slice>.<subitem>" (RingModel ids) or "<slice>" for slices that run directly.
import AppKit
import ImageIO

enum ImageAction: Equatable {
    case compress(target: String)   // "500KB" | "1MB" | "2MB" | "5MB" | "ask"
    case resizePercent50
    case resizeLongEdge(Int)
    case convert(String)            // "jpg" | "png" | "heic" | "webp"
    case rotate(degrees: Int)       // value for `sips -r` (clockwise)
    case strip
    case copy

    static func parse(_ id: String) -> ImageAction? {
        switch id {
        case "compress.500kb": return .compress(target: "500KB")
        case "compress.1mb": return .compress(target: "1MB")
        case "compress.2mb": return .compress(target: "2MB")
        case "compress.5mb": return .compress(target: "5MB")
        case "compress.custom": return .compress(target: "ask")
        case "resize.50pct": return .resizePercent50
        case "resize.3840": return .resizeLongEdge(3840)
        case "resize.1920": return .resizeLongEdge(1920)
        case "resize.1280": return .resizeLongEdge(1280)
        case "resize.800": return .resizeLongEdge(800)
        case "convert.jpg": return .convert("jpg")
        case "convert.png": return .convert("png")
        case "convert.heic": return .convert("heic")
        case "convert.webp": return .convert("webp")
        case "rotate.ccw90": return .rotate(degrees: 270)   // 90 deg counter-clockwise
        case "rotate.cw90": return .rotate(degrees: 90)
        case "rotate.180": return .rotate(degrees: 180)
        case "strip": return .strip
        case "copy": return .copy
        default: return nil
        }
    }

    /// img-shrink sends its own notification, so the app must not send a second one.
    var notifiesItself: Bool { if case .compress = self { return true }; return false }

    var label: String {
        switch self {
        case .compress(let t): return t == "ask" ? "Compress Custom" : "Compress \(t)"
        case .resizePercent50: return "Resize 50%"
        case .resizeLongEdge(let n): return "Resize \(n) px"
        case .convert(let t): return "Convert \(t.uppercased())"
        case .rotate(let d): return "Rotate \(d)°"
        case .strip: return "Strip metadata"
        case .copy: return "Copy"
        }
    }
}

struct ActionOutcome {
    var outputs: [String] = []
    var ok = 0, skipped = 0, failed = 0
    var notes: [String] = []
    var summary = ""
}

enum Actions {
    static let sipsPath = "/usr/bin/sips"
    /// Homebrew cwebp (Apple Silicon or Intel prefix). WebP is unavailable without it.
    static let cwebpPath: String = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/cwebp"
    /// img-shrink ships inside the app bundle (Contents/Resources); ~/.local/bin is a dev fallback.
    static var imgShrinkPath: String {
        if let p = Bundle.main.path(forResource: "img-shrink", ofType: nil),
           FileManager.default.isExecutableFile(atPath: p) { return p }
        return NSHomeDirectory() + "/.local/bin/img-shrink"
    }

    enum FileResult { case ok(String), skip(String), fail(String) }

    /// Runs the action on every file (Copy: first file only). Blocking. Copy hops to the main thread.
    static func perform(_ action: ImageAction, files: [URL]) -> ActionOutcome {
        if case .compress(let target) = action { return compressAll(target, files) }
        if case .copy = action { return copyFirst(files) }
        var o = ActionOutcome()
        for f in files {
            switch fileAction(action, f) {
            case .ok(let p): o.ok += 1; o.outputs.append(p)
            case .skip(let m): o.skipped += 1; o.notes.append("\(f.lastPathComponent): \(m)")
            case .fail(let m): o.failed += 1; o.notes.append("\(f.lastPathComponent): \(m)")
            }
        }
        if files.isEmpty { o.failed = 1; o.notes.append("no image files") }
        o.summary = "\(action.label): \(o.ok) berhasil, \(o.skipped) dilewati, \(o.failed) gagal"
        return o
    }

    // MARK: per-file actions

    private static func fileAction(_ a: ImageAction, _ src: URL) -> FileResult {
        switch a {
        case .resizePercent50: return resizePercent50(src)
        case .resizeLongEdge(let n): return resizeLongEdge(src, n)
        case .convert(let t): return convert(src, to: t)
        case .rotate(let d): return rotate(src, d)
        case .strip: return strip(src)
        case .compress, .copy: return .fail("internal: not a per-file action")
        }
    }

    private static func resizePercent50(_ src: URL) -> FileResult {
        guard let info = imageInfo(src) else { return .fail("bukan gambar yang bisa dibaca") }
        let w = max(1, info.w / 2), h = max(1, info.h / 2)
        let out = destURL(for: src, suffix: "-50pct", ext: src.pathExtension)
        return sipsWrite(["-z", "\(h)", "\(w)", src.path, "--out", out.path], out)   // sips -z takes height first
    }

    private static func resizeLongEdge(_ src: URL, _ n: Int) -> FileResult {
        guard let info = imageInfo(src) else { return .fail("bukan gambar yang bisa dibaca") }
        let long = max(info.w, info.h)
        if long <= n { return .skip("sisi terpanjang \(long) px, sudah ≤ \(n)") }
        let out = destURL(for: src, suffix: "-\(n)px", ext: src.pathExtension)
        return sipsWrite(["-Z", "\(n)", src.path, "--out", out.path], out)
    }

    private static func rotate(_ src: URL, _ degrees: Int) -> FileResult {
        guard imageInfo(src) != nil else { return .fail("bukan gambar yang bisa dibaca") }
        let out = destURL(for: src, suffix: "-rot\(degrees)", ext: src.pathExtension)
        return sipsWrite(["-r", "\(degrees)", src.path, "--out", out.path], out)
    }

    private static func convert(_ src: URL, to target: String) -> FileResult {
        guard let info = imageInfo(src) else { return .fail("bukan gambar yang bisa dibaca") }
        if kind(ofUTI: info.uti) == target { return .skip("sudah \(target)") }
        if target == "webp" {
            guard FileManager.default.fileExists(atPath: cwebpPath) else { return .fail("WebP tidak tersedia (cwebp tidak ada)") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("imagering-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: tmp) }
            let s = runTool(sipsPath, ["-s", "format", "png", src.path, "--out", tmp.path])
            guard s.status == 0 else { return .fail("sips (ke PNG): \(s.err.trimmed)") }
            let out = destURL(for: src, suffix: "", ext: "webp")
            let c = runTool(cwebpPath, ["-q", "85", tmp.path, "-o", out.path])
            guard c.status == 0, FileManager.default.fileExists(atPath: out.path) else { return .fail("cwebp: \((c.err + c.out).trimmed)") }
            return .ok(out.path)
        }
        let out = destURL(for: src, suffix: "", ext: target)
        let fmt = target == "jpg" ? "jpeg" : target
        return sipsWrite(["-s", "format", fmt, src.path, "--out", out.path], out)
    }

    /// Re-encodes from the decoded pixels. The thumbnail API gives no metadata, and no property dictionary is copied.
    private static func strip(_ src: URL) -> FileResult {
        guard let info = imageInfo(src), let s = CGImageSourceCreateWithURL(src as CFURL, nil) else {
            return .fail("bukan gambar yang bisa dibaca")
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // bakes EXIF orientation into the pixels
            kCGImageSourceThumbnailMaxPixelSize: max(info.w, info.h),
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(s, 0, opts as CFDictionary) else {
            return .fail("gagal decode gambar")
        }
        let out = destURL(for: src, suffix: "-clean", ext: src.pathExtension)
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, info.uti as CFString, 1, nil) else {
            return .fail("tipe \(info.uti) tidak bisa ditulis")
        }
        let lossy = ["public.jpeg", "public.heic", "public.heif", "org.webmproject.webp"].contains(info.uti)
        let props: CFDictionary? = lossy ? ([kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary) : nil
        CGImageDestinationAddImage(d, img, props)
        guard CGImageDestinationFinalize(d) else { return .fail("gagal menulis file") }
        return .ok(out.path)
    }

    // MARK: compress (img-shrink does the work and sends its own notification)

    private static func compressAll(_ target: String, _ files: [URL]) -> ActionOutcome {
        var o = ActionOutcome()
        let r = runTool(imgShrinkPath, [target] + files.map { $0.path })
        for line in r.out.split(separator: "\n").map(String.init) {
            if line.hasPrefix("ok: ") {
                let body = String(line.dropFirst(4))
                o.outputs.append(body.components(separatedBy: "  ").first ?? body)
                o.ok += 1
            } else if line.hasPrefix("skip: ") {
                o.skipped += 1; o.notes.append(line)
            }
        }
        for line in r.err.split(separator: "\n").map(String.init) where line.hasPrefix("fail: ") || line.hasPrefix("invalid") {
            o.failed += 1; o.notes.append(line)
        }
        if r.status != 0 && o.failed == 0 { o.failed = 1; o.notes.append(r.err.trimmed) }
        if o.ok + o.skipped + o.failed == 0 { o.notes.append("dibatalkan"); }
        o.summary = "Compress \(target == "ask" ? "Custom" : target): \(o.ok) berhasil, \(o.skipped) dilewati, \(o.failed) gagal"
        return o
    }

    // MARK: copy

    private static func copyFirst(_ files: [URL]) -> ActionOutcome {
        var o = ActionOutcome()
        guard let f = files.first else {
            o.failed = 1; o.notes.append("no image files"); o.summary = "Copy: tidak ada gambar"; return o
        }
        let ok = onMain { copyToPasteboard(f) }
        if ok { o.ok = 1; o.summary = "Disalin ke clipboard: \(f.lastPathComponent)" }
        else { o.failed = 1; o.notes.append("\(f.lastPathComponent): gagal menyalin"); o.summary = "Copy gagal" }
        return o
    }

    /// One pasteboard item holding PNG bytes and the file URL together.
    private static func copyToPasteboard(_ f: URL) -> Bool {
        guard let img = NSImage(contentsOf: f), let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()                     // must come before creating the item (item created first lost public.file-url)
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(Data(f.absoluteString.utf8), forType: .fileURL)   // setString did not register public.file-url
        guard pb.writeObjects([item]) else { return false }
        // The pasteboard server receives the write asynchronously. A process that exits right after
        // writeObjects can lose the file URL (measured: public.file-url missing in 2 of 2 runs). Keep the
        // run loop going briefly so the write is delivered before the process exits.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        return (pb.types ?? []).contains(.fileURL)
    }

    private static func onMain<T>(_ work: @escaping () -> T) -> T {
        if Thread.isMainThread { return work() }
        return DispatchQueue.main.sync(execute: work)
    }

    // MARK: helpers

    private static func sipsWrite(_ args: [String], _ out: URL) -> FileResult {
        let r = runTool(sipsPath, args)
        guard r.status == 0, FileManager.default.fileExists(atPath: out.path) else {
            return .fail("sips: \((r.err + r.out).trimmed)")
        }
        return .ok(out.path)
    }

    /// `<name><suffix>.<ext>`, then `-2`, `-3`... on collision.
    static func destURL(for src: URL, suffix: String, ext: String) -> URL {
        let dir = src.deletingLastPathComponent()
        let base = src.deletingPathExtension().lastPathComponent
        var n = 1
        while true {
            let tag = n == 1 ? "" : "-\(n)"
            let candidate = dir.appendingPathComponent("\(base)\(suffix)\(tag).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    static func imageInfo(_ url: URL) -> (w: Int, h: Int, uti: String)? {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil),
              let uti = CGImageSourceGetType(s) as String?,
              let props = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h, uti)
    }

    static func kind(ofUTI uti: String) -> String? {
        switch uti {
        case "public.jpeg": return "jpg"
        case "public.png": return "png"
        case "public.heic", "public.heif": return "heic"
        case "org.webmproject.webp": return "webp"
        default: return nil
        }
    }

    static func runTool(_ path: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch { return (-1, "", "\(error)") }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: od, as: UTF8.self), String(decoding: ed, as: UTF8.self))
    }
}

enum Notify {
    static func send(_ message: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)",
                       "-e", "end run", "ImageRing", message]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { Log.write("notify failed: \(error)") }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
