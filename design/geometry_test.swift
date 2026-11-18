// design/geometry_test.swift -- pure geometry self-test (no GUI). Run: design/geometry_test.sh
import CoreGraphics
import Foundation

@main struct GeometryTest {
    static var failures = 0
    static func check(_ name: String, _ got: Selection, _ want: Selection) {
        if got == want { print("ok   \(name)") } else { print("FAIL \(name): got \(got), want \(want)"); failures += 1 }
    }
    /// dx,dy (y-UP) for ring-angle in degrees (clockwise from top) and radius.
    static func p(_ deg: CGFloat, _ r: CGFloat) -> (CGFloat, CGFloat) {
        let t = deg * .pi / 180; return (r * sin(t), r * cos(t))
    }
    static func ht(_ x: (CGFloat, CGFloat), _ open: Int?, counts: [Int] = RingGeometry.defaultSubItemCounts) -> Selection {
        hitTest(dx: x.0, dy: x.1, openSubmenuOf: open, subItemCounts: counts)
    }
    static func main() {
        // Centre dead zone and exact centre
        check("centre", hitTest(dx: 0, dy: 0, openSubmenuOf: nil), .none)
        check("inside hole", hitTest(dx: 30, dy: -30, openSubmenuOf: nil), .none)
        // Asymmetric points: a y-flip or x-flip makes at least one of these fail
        check("up = Compress", hitTest(dx: 0, dy: 100, openSubmenuOf: nil), .slice(0))
        check("down = Rotate", hitTest(dx: 0, dy: -100, openSubmenuOf: nil), .slice(3))
        check("right-up = Resize", hitTest(dx: 100, dy: 40, openSubmenuOf: nil), .slice(1))
        check("right-down = Convert", hitTest(dx: 100, dy: -40, openSubmenuOf: nil), .slice(2))
        check("left-down = Strip", hitTest(dx: -100, dy: -40, openSubmenuOf: nil), .slice(4))
        check("left-up = Copy", hitTest(dx: -100, dy: 40, openSubmenuOf: nil), .slice(5))
        check("just left of top = Compress (wrap)", ht(p(-20, 120), nil), .slice(0))
        check("just right of 30deg divider = Resize", ht(p(31, 120), nil), .slice(1))
        check("just left of 30deg divider = Compress", ht(p(29, 120), nil), .slice(0))
        check("just left of -30deg divider = Copy", ht(p(-31, 120), nil), .slice(5))
        // Gap and outside
        check("gap, no submenu open", ht(p(0, 156), nil), .none)
        check("gap, submenu open, in arc span", ht(p(0, 156), 0), .slice(0))
        check("gap, submenu open, over neighbour slice but inside arc", ht(p(55, 156), 0), .slice(0))
        check("gap, submenu open, outside arc span", ht(p(120, 156), 0), .none)
        check("no-submenu slice (Strip) outer band", ht(p(240, 200), 4), .none)
        check("beyond outer radius", ht(p(0, 235), 0), .none)
        check("outer band but nothing open", ht(p(0, 200), nil), .none)
        // Submenu items of Compress (5 items x 28deg, arc -70..+70, centred on 0)
        check("sub centre item", ht(p(0, 200), 0), .subItem(slice: 0, item: 2))
        check("sub wrap: -10deg (left of top) still item 2", ht(p(-10, 200), 0), .subItem(slice: 0, item: 2))
        check("sub wrap: -30deg item 1", ht(p(-30, 200), 0), .subItem(slice: 0, item: 1))
        check("sub first item (-60deg, over the Copy slice angle)", ht(p(-60, 200), 0), .subItem(slice: 0, item: 0))
        check("sub last item (+60deg, over the Resize slice angle)", ht(p(60, 200), 0), .subItem(slice: 0, item: 4))
        check("sub just outside arc (+75deg)", ht(p(75, 200), 0), .none)
        check("sub at inner edge r=160", ht(p(0, 160.5), 0), .subItem(slice: 0, item: 2))
        check("sub at outer edge r=225", ht(p(0, 225), 0), .subItem(slice: 0, item: 2))
        // Rotate (bottom, 3 items, arc 138..222): crossing the 180deg seam is NOT a wrap, but check both sides
        check("rotate sub left item (+210deg) is item 0 (reads left to right)", ht(p(210, 200), 3), .subItem(slice: 3, item: 0))
        check("rotate sub right item (+150deg) is item 2", ht(p(150, 200), 3), .subItem(slice: 3, item: 2))
        check("convert (right side) stays clockwise: +75deg is item 0", ht(p(75, 200), 2), .subItem(slice: 2, item: 0))
        // Convert without cwebp has 3 items
        let noWebp = RingModel.subItemCounts(webpAvailable: false)
        check("convert 3 items: arc 78..162 (centre 120 -> item 1)", ht(p(120, 200), 2, counts: noWebp), .subItem(slice: 2, item: 1))
        check("convert 3 items: 165deg is outside", ht(p(165, 200), 2, counts: noWebp), .none)
        check("convert 4 items: 165deg is item 3", ht(p(165, 200), 2), .subItem(slice: 2, item: 3))

        // Round trips: every slice centre and every sub item centre hit-tests to itself
        for webp in [true, false] {
            let counts = RingModel.subItemCounts(webpAvailable: webp)
            for i in 0..<RingGeometry.sliceCount {
                let c = p(RingGeometry.sliceCentreAngle(i) * 180 / .pi, RingGeometry.sliceMidRadius)
                check("roundtrip slice \(i)", ht(c, nil, counts: counts), .slice(i))
                for k in 0..<counts[i] {
                    let a = RingGeometry.subItemCentreAngle(slice: i, item: k, count: counts[i]) * 180 / .pi
                    check("roundtrip sub \(i)/\(k) webp=\(webp)", ht(p(a, RingGeometry.subMidRadius), i, counts: counts),
                          .subItem(slice: i, item: k))
                }
            }
        }
        // Geometry sanity
        let sum = RingGeometry.sliceAngle * CGFloat(RingGeometry.sliceCount)
        if abs(sum - 2 * .pi) > 1e-9 { print("FAIL slices do not sum to 360"); failures += 1 }
        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
        exit(failures == 0 ? 0 : 1)
    }
}
