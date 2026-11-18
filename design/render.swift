// design/render.swift -- renders every state offscreen to PNG and checks that labels fit.
// Build + run: design/render.sh
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "design/shots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func make(_ f: (inout RingState) -> Void) -> RingState { var s = RingState(); f(&s); return s }
let states: [(String, RingState)] = [
    ("idle", make { _ in }),
    ("hover-slice", make { $0.hoveredSlice = 0 }),
    ("submenu-open", make { $0.hoveredSlice = 0; $0.openSubmenu = 0 }),
    ("hover-subitem", make { $0.hoveredSlice = 0; $0.openSubmenu = 0; $0.hoveredSubItem = 1 }),
    ("no-selection", make { $0.disabled = true }),
    // extras (not required by SPEC)
    ("pressed-subitem", make { $0.hoveredSlice = 0; $0.openSubmenu = 0; $0.hoveredSubItem = 1; $0.pressed = true }),
    ("open-half", make { $0.hoveredSlice = 0; $0.openSubmenu = 0; $0.openProgress = 0.5; $0.submenuProgress = 0.5 }),
    ("pressed-slice", make { $0.hoveredSlice = 3; $0.pressed = true }),
    ("submenu-rotate", make { $0.hoveredSlice = 3; $0.openSubmenu = 3; $0.hoveredSubItem = 2 }),
    ("submenu-resize", make { $0.hoveredSlice = 1; $0.openSubmenu = 1; $0.hoveredSubItem = 1 }),
]
let grey = NSColor(srgbRed: 0x7F / 255, green: 0x7F / 255, blue: 0x82 / 255, alpha: 1)
for (name, st) in states {
    for (suffix, bg) in [("", grey), ("-light", NSColor.white)] {
        guard let data = RingView.pngData(state: st, scale: 2, background: bg) else { print("FAIL \(name)"); exit(1) }
        try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)\(suffix).png"))
    }
}
print("wrote \(states.count * 2) PNGs to \(outDir)")

// --- label fit check (measured, not eyeballed) -------------------------------------------------
// A label rect fits if its four corners lie inside the annular sector (minus `pad`).
typealias G = RingGeometry
func inside(_ p: CGPoint, rin: CGFloat, rout: CGFloat, a: CGFloat, b: CGFloat, pad: CGFloat) -> Bool {
    let r = hypot(p.x, p.y)
    if r < rin + pad || r > rout - pad { return false }
    let d = G.signedDelta(atan2(p.x, p.y), (a + b) / 2)
    let half = (b - a) / 2 - asin(min(1, (G.shapeGap / 2 + pad) / r))   // keep pad away from the side edges
    return abs(d) <= half
}
func corners(_ r: CGRect) -> [CGPoint] { [r.minX, r.maxX].flatMap { x in [r.minY, r.maxY].map { CGPoint(x: x, y: $0) } } }
var bad = 0
for webp in [true, false] {
    let slices = RingModel.slices(webpAvailable: webp)
    for (i, s) in slices.enumerated() {
        let rr = G.sliceRange(i)
        // inner ring: whole group = circle + label; check label rect and circle bounding box
        let lay = RingRenderer.sliceLayout(i, label: s.label)
        let d = RingStyle.iconCircleDiameter * 1.07
        let circleRect = CGRect(x: lay.circle.x - d / 2, y: lay.circle.y - d / 2, width: d, height: d)
        for (what, rect) in lay.lines.map({ ("label", $0.rect) }) + [("circle", circleRect)] {
            for c in corners(rect) where !inside(c, rin: G.holeRadius, rout: G.innerOuterRadius, a: rr.start, b: rr.end, pad: 3) {
                print("OVERFLOW slice \(s.id) \(what) corner \(c)"); bad += 1; break
            }
        }
        for (k, item) in s.subItems.enumerated() {
            let ir = G.subItemRange(slice: i, item: k, count: s.subItems.count)
            let rect = RingRenderer.subLabelRect(slice: i, item: k, count: s.subItems.count, label: item.label)
            // use semibold (hovered) width as worst case
            let w = RingRenderer.textSize(item.label, font: .systemFont(ofSize: 13, weight: .semibold)).width
            let wide = rect.insetBy(dx: (rect.width - w) / 2, dy: 0)
            for c in corners(wide) where !inside(c, rin: G.subInnerRadius, rout: G.subOuterRadius, a: ir.start, b: ir.end, pad: 3) {
                print("OVERFLOW sub \(s.id)/\(item.id) corner \(c)"); bad += 1; break
            }
        }
    }
}
print(bad == 0 ? "label fit check: OK (all labels inside their shapes, webp on/off)" : "label fit check: \(bad) OVERFLOWS")
exit(bad == 0 ? 0 : 2)
