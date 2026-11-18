// Log.swift -- stdout + optional file log (`--log <path>`). Never writes next to the bundle.
import Foundation

enum Log {
    static var path: String?

    static func write(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let line = "\(f.string(from: Date())) \(s)"
        print(line)
        fflush(stdout)
        guard let p = path else { return }
        let data = Data((line + "\n").utf8)
        if let h = FileHandle(forWritingAtPath: p) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: p))
        }
    }
}
