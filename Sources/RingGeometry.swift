// RingGeometry.swift -- PURE geometry + hit-testing for the ImageRing radial menu.
// Depends only on CoreGraphics/Foundation. No AppKit.
//
// COORDINATE CONVENTION (read this before touching anything)
//   * Origin = ring centre. dx grows to the RIGHT, dy grows UP (y-UP, AppKit non-flipped,
//     same as NSEvent.mouseLocation deltas and a non-flipped NSView).
//     In a flipped (y-down) view, pass dy = -(point.y - centre.y).
//   * "Ring angle" (theta) = radians measured CLOCKWISE from 12 o'clock (straight up).
//       theta = atan2(dx, dy)   (note the argument order), normalised to [0, 2*pi).
//     12 o'clock = 0, 3 o'clock = pi/2, 6 o'clock = pi, 9 o'clock = 3*pi/2.
//   * Converting to a CoreGraphics angle (counter-clockwise from +x in a y-up context):
//       cgAngle = pi/2 - theta.     Use `cgAngle(_:)`.
//   * Point on the ring: x = r*sin(theta), y = r*cos(theta). Use `point(theta:radius:)`.
import CoreGraphics
import Foundation

public enum Selection: Equatable {
    /// Centre dead zone (cancel) OR outside the rings. Releasing the hotkey here cancels.
    case none
    case slice(Int)
    case subItem(slice: Int, item: Int)
}

public enum RingGeometry {
    // MARK: Radii (points)
    public static let holeRadius: CGFloat = 54          // centre dead zone / cancel
    public static let innerOuterRadius: CGFloat = 152   // outer edge of the 6-slice ring
    public static let gap: CGFloat = 8                  // radial gap between the two rings
    public static let subInnerRadius: CGFloat = innerOuterRadius + gap   // 160
    public static let subOuterRadius: CGFloat = 226                      // outer edge of submenu arc
    public static var sliceMidRadius: CGFloat { (holeRadius + innerOuterRadius) / 2 }   // 103
    public static var subMidRadius: CGFloat { (subInnerRadius + subOuterRadius) / 2 }   // 193

    /// Visual gap between neighbouring shapes (constant width, parallel edges) and corner radius.
    public static let shapeGap: CGFloat = 2.5
    public static let cornerRadius: CGFloat = 5

    /// Square canvas (points) the view/panel must be: outer radius + shadow margin, both sides.
    public static let shadowMargin: CGFloat = 30
    public static let canvasSize: CGFloat = 2 * (subOuterRadius + shadowMargin)   // 512

    // MARK: Angles
    public static let sliceCount = 6
    public static let sliceAngle: CGFloat = 2 * .pi / CGFloat(sliceCount)   // 60 deg
    /// Ring angle of the CENTRE of slice 0 (Compress). 0 = Compress is centred at 12 o'clock,
    /// so slice i is centred at i*60 deg clockwise (Resize 60, Convert 120, Rotate 180,
    /// Strip 240, Copy 300) and the dividers sit at +-30, 90, 150, ...
    public static let sliceZeroCentre: CGFloat = 0
    /// Angular width of ONE submenu item (28 deg => Compress's 5 items span 140 deg).
    public static let subItemAngle: CGFloat = 28 * .pi / 180

    /// Number of submenu items per slice (Compress, Resize, Convert, Rotate, Strip, Copy).
    /// Convert has 3 (JPG/PNG/HEIC) when cwebp is missing; pass RingModel.subItemCounts(...) then.
    public static let defaultSubItemCounts: [Int] = [5, 5, 4, 3, 0, 0]

    // MARK: Angle helpers
    @inline(__always) public static func normalize(_ a: CGFloat) -> CGFloat {
        var t = a.truncatingRemainder(dividingBy: 2 * .pi)
        if t < 0 { t += 2 * .pi }
        return t
    }
    /// Signed shortest difference a-b in (-pi, pi].
    @inline(__always) public static func signedDelta(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        var d = normalize(a - b)
        if d > .pi { d -= 2 * .pi }
        return d
    }
    public static func cgAngle(_ theta: CGFloat) -> CGFloat { .pi / 2 - theta }
    public static func point(theta: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: radius * sin(theta), y: radius * cos(theta))
    }

    /// Centre ring-angle of slice i (not normalised, may be 5*60 = 300 deg).
    public static func sliceCentreAngle(_ i: Int) -> CGFloat { sliceZeroCentre + CGFloat(i) * sliceAngle }
    /// [start, end] ring-angles (clockwise, start < end, not normalised) of slice i.
    public static func sliceRange(_ i: Int) -> (start: CGFloat, end: CGFloat) {
        let c = sliceCentreAngle(i); return (c - sliceAngle / 2, c + sliceAngle / 2)
    }
    /// Total angular span of a submenu arc with `count` items.
    public static func subArcSpan(count: Int) -> CGFloat { CGFloat(count) * subItemAngle }
    /// The submenu arc is CENTRED on its parent slice's centre angle.
    public static func subArcRange(slice: Int, count: Int) -> (start: CGFloat, end: CGFloat) {
        let c = sliceCentreAngle(slice), h = subArcSpan(count: count) / 2
        return (c - h, c + h)
    }
    /// Arcs centred near the bottom (Rotate) would read right-to-left if items ran clockwise, so their
    /// items run COUNTER-clockwise (left-to-right on screen). All other arcs run clockwise.
    /// Single rule used by both drawing (`subItemRange`) and hit-testing.
    public static func subItemsReversed(slice: Int) -> Bool {
        cos(sliceCentreAngle(slice)) < -0.6
    }
    /// Clockwise position (0 = first clockwise) occupied by item `item`; it is its own inverse.
    public static func position(slice: Int, item: Int, count: Int) -> Int {
        subItemsReversed(slice: slice) ? count - 1 - item : item
    }
    /// [start, end] ring-angles of sub item `item` (clockwise positions, see `position`).
    public static func subItemRange(slice: Int, item: Int, count: Int) -> (start: CGFloat, end: CGFloat) {
        let a = subArcRange(slice: slice, count: count).start
        let k = CGFloat(position(slice: slice, item: item, count: count))
        return (a + k * subItemAngle, a + (k + 1) * subItemAngle)
    }
    public static func subItemCentreAngle(slice: Int, item: Int, count: Int) -> CGFloat {
        let r = subItemRange(slice: slice, item: item, count: count); return (r.start + r.end) / 2
    }

    // MARK: Hit testing
    /// Pure hit test. See file header for the coordinate convention (y-UP, clockwise-from-top).
    ///
    /// Rules:
    ///  * r < holeRadius                          -> .none (centre = cancel)
    ///  * holeRadius <= r <= innerOuterRadius     -> .slice(angle-based index)
    ///  * innerOuterRadius < r < subInnerRadius   -> the GAP. If a submenu is open and the angle is
    ///    inside its arc span -> .slice(open) so the submenu does
    ///    not flicker shut while the pointer crosses the gap; otherwise .none.
    ///  * subInnerRadius <= r <= subOuterRadius and a submenu is open and the angle is inside the
    ///    arc span -> .subItem(open, item), EVEN when the angle lies over a neighbouring slice
    ///    (the arc is wider than its 60 deg parent).
    ///  * everything else (beyond subOuterRadius, outside the arc span, past the inner ring when no
    ///    submenu is open) -> .none. Hosts treat .none as "cancel on release / click".
    ///
    /// `subItemCounts` is injectable because Convert has 3 or 4 items depending on cwebp.
    public static func hitTest(dx: CGFloat, dy: CGFloat, openSubmenuOf: Int?,
                               subItemCounts: [Int] = defaultSubItemCounts) -> Selection {
        let r = (dx * dx + dy * dy).squareRoot()
        if r < holeRadius { return .none }
        let theta = normalize(atan2(dx, dy))
        let idx = sliceIndex(theta: theta)

        if r <= innerOuterRadius { return .slice(idx) }

        // Arc geometry of the currently open submenu (if any and non-empty).
        var arcSlice = -1, count = 0, delta: CGFloat = 0, inArc = false
        if let o = openSubmenuOf, o >= 0, o < subItemCounts.count, subItemCounts[o] > 0 {
            arcSlice = o; count = subItemCounts[o]
            delta = signedDelta(theta, sliceCentreAngle(o))           // angle from arc centre
            inArc = abs(delta) <= subArcSpan(count: count) / 2
        }
        if arcSlice < 0 || !inArc { return .none }

        if r < subInnerRadius { return .slice(arcSlice) }             // sticky gap
        if r <= subOuterRadius {
            let half = subArcSpan(count: count) / 2
            let pos = min(count - 1, max(0, Int(((delta + half) / subItemAngle).rounded(.down))))
            let item = position(slice: arcSlice, item: pos, count: count)
            return .subItem(slice: arcSlice, item: item)
        }
        return .none
    }

    /// Slice index for a normalised ring angle in [0, 2*pi).
    public static func sliceIndex(theta: CGFloat) -> Int {
        let shifted = normalize(theta - sliceZeroCentre + sliceAngle / 2)
        return min(sliceCount - 1, Int((shifted / sliceAngle).rounded(.down)))
    }
}

/// Free-function form named in the SPEC: `hitTest(dx:dy:openSubmenuOf:)`.
public func hitTest(dx: CGFloat, dy: CGFloat, openSubmenuOf: Int?,
                    subItemCounts: [Int] = RingGeometry.defaultSubItemCounts) -> Selection {
    RingGeometry.hitTest(dx: dx, dy: dy, openSubmenuOf: openSubmenuOf, subItemCounts: subItemCounts)
}
