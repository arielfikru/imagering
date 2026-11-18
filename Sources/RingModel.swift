// RingModel.swift -- the menu model (SPEC "Menu" table). Foundation/CoreGraphics only.
import CoreGraphics
import Foundation

public struct RingColor: Equatable {
    public let hex: UInt32
    public init(_ hex: UInt32) { self.hex = hex }
    public var r: CGFloat { CGFloat((hex >> 16) & 0xFF) / 255 }
    public var g: CGFloat { CGFloat((hex >> 8) & 0xFF) / 255 }
    public var b: CGFloat { CGFloat(hex & 0xFF) / 255 }
    public func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
    /// Linear blend towards `other` by t (0 = self, 1 = other).
    public func mixed(with other: RingColor, _ t: CGFloat) -> RingColor {
        func c(_ a: CGFloat, _ b: CGFloat) -> UInt32 { UInt32(((a + (b - a) * t) * 255).rounded()) }
        return RingColor(c(r, other.r) << 16 | c(g, other.g) << 8 | c(b, other.b))
    }
}

public struct RingSubItem: Equatable {
    public let id: String       // stable id for the backend
    public let label: String    // shown in the outer arc
}

public struct RingSlice: Equatable {
    public let id: String
    public let label: String
    public let symbol: String       // SF Symbol name
    public let accent: RingColor    // icon-circle colour AND hovered sub-item colour
    public let subItems: [RingSubItem]   // empty = runs directly
}

public enum RingModel {
    /// webpAvailable: caller checks FileManager for /opt/homebrew/bin/cwebp (this file never touches disk).
    public static func slices(webpAvailable: Bool = true) -> [RingSlice] {
        var convert = [RingSubItem(id: "jpg", label: "JPG"), RingSubItem(id: "png", label: "PNG"),
                       RingSubItem(id: "heic", label: "HEIC")]
        if webpAvailable { convert.append(RingSubItem(id: "webp", label: "WebP")) }
        return [
            RingSlice(id: "compress", label: "Compress", symbol: "arrow.down.right.and.arrow.up.left",
                      accent: RingColor(0x34C759),
                      subItems: [("500kb", "500 KB"), ("1mb", "1 MB"), ("2mb", "2 MB"), ("5mb", "5 MB"),
                                 ("custom", "Custom…")].map { RingSubItem(id: $0.0, label: $0.1) }),
            RingSlice(id: "resize", label: "Resize", symbol: "aspectratio",
                      accent: RingColor(0x0A84FF),
                      subItems: [("50pct", "50%"), ("3840", "3840 px"), ("1920", "1920 px"),
                                 ("1280", "1280 px"), ("800", "800 px")].map { RingSubItem(id: $0.0, label: $0.1) }),
            RingSlice(id: "convert", label: "Convert", symbol: "arrow.triangle.2.circlepath",
                      accent: RingColor(0xBF5AF2), subItems: convert),
            RingSlice(id: "rotate", label: "Rotate", symbol: "rotate.right",
                      accent: RingColor(0xFF9F0A),
                      subItems: [("ccw90", "90° ↺"), ("cw90", "90° ↻"), ("180", "180°")]
                        .map { RingSubItem(id: $0.0, label: $0.1) }),
            RingSlice(id: "strip", label: "Strip metadata", symbol: "eye.slash",
                      accent: RingColor(0xFF453A), subItems: []),
            RingSlice(id: "copy", label: "Copy", symbol: "doc.on.doc",
                      accent: RingColor(0x40C8E0), subItems: []),
        ]
    }
    /// Feed this to RingGeometry.hitTest(subItemCounts:).
    public static func subItemCounts(webpAvailable: Bool = true) -> [Int] {
        slices(webpAvailable: webpAvailable).map { $0.subItems.count }
    }
}
