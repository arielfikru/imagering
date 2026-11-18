// RingView.swift -- reference drawing code for the ImageRing radial menu (AppKit + CoreGraphics).
// Draws in a NON-FLIPPED (y-up) context, centred in `bounds`. Geometry comes from RingGeometry,
// content from RingModel. The same `RingRenderer.draw` is used by the live NSView and by the
// offscreen `--render` PNG path, so screenshots == what the app shows (minus window compositing).
import AppKit
import CoreGraphics

// MARK: - State

public struct RingState: Equatable {
    public var hoveredSlice: Int? = nil       // highlighted inner slice (stays set while a sub-item is hovered)
    public var openSubmenu: Int? = nil        // slice whose outer arc is shown
    public var hoveredSubItem: Int? = nil     // item inside the open arc
    public var pressed = false                // mouse button down on the hovered slice / sub-item
    public var disabled = false               // no image selected -> dim, centre message, no hover
    public var webpAvailable = true
    /// 0...1, host-animated (open: ~120 ms ease-out). Scales 0.92->1 about the centre and fades in.
    public var openProgress: CGFloat = 1
    /// 0...1, host-animated (~110 ms). The arc fades in and scales 0.94->1 about the ring centre.
    public var submenuProgress: CGFloat = 1

    public init() {}
    /// Convenience: derive hover fields from a hit-test result.
    public init(selection: Selection, openSubmenu: Int?) {
        self.openSubmenu = openSubmenu
        switch selection {
        case .none: break
        case .slice(let i): hoveredSlice = i
        case .subItem(let s, let k): hoveredSlice = s; hoveredSubItem = k
        }
    }
}

// MARK: - Palette / typography (documented in design/DESIGN.md)

public enum RingStyle {
    public static let sliceFill = RingColor(0x27272B)        // idle slice / sub-item
    public static let sliceHover = RingColor(0x5E5E64)       // hovered slice (lighter, like the reference)
    public static let subHoverDarken: CGFloat = 0.50         // sub-item hover = accent mixed with black
    public static let layerAlpha: CGFloat = 0.90             // whole-ring translucency (shapes drawn opaque, then composited)
    public static let textPrimary = NSColor(white: 1, alpha: 0.96)
    public static let textDisabled = NSColor(white: 1, alpha: 0.62)
    public static let sliceLabelFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    public static let subLabelFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    public static let centreFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    public static let iconCircleDiameter: CGFloat = 38
    public static let iconPointSize: CGFloat = 17
    public static let disabledContentAlpha: CGFloat = 0.40
    public static let shadowBlur: CGFloat = 22
    public static let shadowOffset = CGSize(width: 0, height: -7)   // y-up: negative = down
    public static let shadowAlpha: CGFloat = 0.45
}

// MARK: - Renderer

public enum RingRenderer {
    typealias G = RingGeometry

    /// Annular sector between ring-angles a<b (clockwise from top), radii in..out, shrunk so that
    /// neighbours have a constant-width `gap` between parallel edges, with rounded corners (cr).
    /// Rounded corners: build the path inset by cr, then fill + stroke it (round join) in one colour.
    static func sectorPath(inR: CGFloat, outR: CGFloat, a: CGFloat, b: CGFloat,
                           gap: CGFloat, cr: CGFloat) -> CGPath {
        let rin = inR + cr, rout = outR - cr, h = gap / 2 + cr
        let aIn = a + asin(h / rin), bIn = b - asin(h / rin)
        let aOut = a + asin(h / rout), bOut = b - asin(h / rout)
        let p = CGMutablePath()
        p.move(to: G.point(theta: aOut, radius: rout))
        p.addArc(center: .zero, radius: rout, startAngle: G.cgAngle(aOut), endAngle: G.cgAngle(bOut), clockwise: true)
        p.addLine(to: G.point(theta: bIn, radius: rin))
        p.addArc(center: .zero, radius: rin, startAngle: G.cgAngle(bIn), endAngle: G.cgAngle(aIn), clockwise: false)
        p.closeSubpath()
        return p
    }

    static func fillRounded(_ ctx: CGContext, _ path: CGPath, color: CGColor, cr: CGFloat) {
        ctx.setFillColor(color); ctx.setStrokeColor(color)
        ctx.setLineWidth(2 * cr); ctx.setLineJoin(.round)
        ctx.addPath(path); ctx.drawPath(using: .fillStroke)
    }

    /// Draws `body` into a group with one soft shadow and global alpha (so overlapping/edge strokes of the
    /// opaque shapes never double-blend).
    static func shapeLayer(_ ctx: CGContext, alpha: CGFloat, shadow: Bool = true, _ body: () -> Void) {
        ctx.saveGState()
        if shadow {
            ctx.setShadow(offset: RingStyle.shadowOffset, blur: RingStyle.shadowBlur,
                          color: CGColor(gray: 0, alpha: RingStyle.shadowAlpha))
        }
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // Text / icon helpers ------------------------------------------------------------------------
    static func attributed(_ s: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    }
    /// Measured size of a single-line label.
    public static func textSize(_ s: String, font: NSFont) -> CGSize {
        attributed(s, font: font, color: .white).size()
    }
    static func drawCentred(_ s: String, font: NSFont, color: NSColor, at c: CGPoint) {
        let a = attributed(s, font: font, color: color), sz = a.size()
        a.draw(at: CGPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2))
    }
    static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .semibold) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
    }
    static func drawSymbol(_ name: String, pointSize: CGFloat, at c: CGPoint, alpha: CGFloat = 1) {
        guard let img = symbol(name, pointSize: pointSize) else { return }
        let sz = img.size
        img.draw(in: CGRect(x: c.x - sz.width / 2, y: c.y - sz.height / 2, width: sz.width, height: sz.height),
                 from: .zero, operation: .sourceOver, fraction: alpha)
    }

    // Layout (public so render.swift can check that labels fit) ----------------------------------
    /// Slice labels wrap to two lines when wider than `sliceLabelMaxWidth` (only "Strip metadata").
    public static let sliceLabelMaxWidth: CGFloat = 72
    public static func labelLines(_ label: String) -> [String] {
        if textSize(label, font: RingStyle.sliceLabelFont).width > sliceLabelMaxWidth,
           let sp = label.firstIndex(of: " ") {
            return [String(label[..<sp]), String(label[label.index(after: sp)...])]
        }
        return [label]
    }
    /// Centre of the icon circle and one rect per label line for slice i
    /// (icon + label group is centred on the slice mid-radius).
    public static func sliceLayout(_ i: Int, label: String) -> (circle: CGPoint, lines: [(text: String, rect: CGRect)]) {
        let c = G.point(theta: G.sliceCentreAngle(i), radius: G.sliceMidRadius)
        let d = RingStyle.iconCircleDiameter, spacing: CGFloat = 5
        let lines = labelLines(label)
        let lh = textSize("Ag", font: RingStyle.sliceLabelFont).height
        let total = d + spacing + lh * CGFloat(lines.count)
        let top = c.y + total / 2
        let circle = CGPoint(x: c.x, y: top - d / 2)
        var out: [(String, CGRect)] = []
        for (n, t) in lines.enumerated() {
            let w = textSize(t, font: RingStyle.sliceLabelFont).width
            out.append((t, CGRect(x: c.x - w / 2, y: top - d - spacing - lh * CGFloat(n + 1), width: w, height: lh)))
        }
        return (circle, out)
    }
    public static func subLabelRect(slice: Int, item: Int, count: Int, label: String) -> CGRect {
        let c = G.point(theta: G.subItemCentreAngle(slice: slice, item: item, count: count), radius: G.subMidRadius)
        let sz = textSize(label, font: RingStyle.subLabelFont)
        return CGRect(x: c.x - sz.width / 2, y: c.y - sz.height / 2, width: sz.width, height: sz.height)
    }

    // Main entry ---------------------------------------------------------------------------------
    /// Draw the ring centred at `centre` in the CURRENT NSGraphicsContext (must be y-up).
    public static func draw(state st: RingState, centre: CGPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let slices = RingModel.slices(webpAvailable: st.webpAvailable)
        let counts = slices.map { $0.subItems.count }
        let hovered = st.disabled ? nil : st.hoveredSlice
        let contentAlpha: CGFloat = st.disabled ? RingStyle.disabledContentAlpha : 1
        let cr = G.cornerRadius, gap = G.shapeGap
        // `pressed` applies to the innermost hovered thing: the sub-item if one is hovered, else the slice.
        let slicePressed = st.pressed && st.hoveredSubItem == nil

        ctx.saveGState()
        ctx.translateBy(x: centre.x, y: centre.y)
        let op = max(0, min(1, st.openProgress))
        if op < 1 {
            let s = 0.92 + 0.08 * op
            ctx.scaleBy(x: s, y: s); ctx.setAlpha(op)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }

        // 1. Inner ring shapes ------------------------------------------------------------------
        shapeLayer(ctx, alpha: RingStyle.layerAlpha) {
            for (i, sl) in slices.enumerated() {
                let r = G.sliceRange(i)
                var fill = RingStyle.sliceFill
                if hovered == i {
                    fill = slicePressed ? RingStyle.sliceFill.mixed(with: sl.accent, 0.50) : RingStyle.sliceHover
                }
                let path = sectorPath(inR: G.holeRadius, outR: G.innerOuterRadius, a: r.start, b: r.end, gap: gap, cr: cr)
                fillRounded(ctx, path, color: fill.cgColor(), cr: cr)
            }
        }

        // 2. Centre disc (cancel zone). Faint when idle, opaque dark carrying the message when disabled.
        ctx.saveGState()
        let disc = CGRect(x: -G.holeRadius + 4, y: -G.holeRadius + 4, width: 2 * (G.holeRadius - 4), height: 2 * (G.holeRadius - 4))
        ctx.setFillColor(CGColor(gray: 0.10, alpha: st.disabled ? 0.92 : 0.12))
        ctx.fillEllipse(in: disc)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14)); ctx.setLineWidth(1)
        ctx.strokeEllipse(in: disc.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()

        // 3. Inner ring content --------------------------------------------------------------------
        ctx.saveGState(); ctx.setAlpha(contentAlpha); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for (i, sl) in slices.enumerated() {
            let lay = sliceLayout(i, label: sl.label)
            let isHot = hovered == i
            let scale: CGFloat = isHot ? (slicePressed ? 0.95 : 1.07) : 1
            let d = RingStyle.iconCircleDiameter * scale
            let rect = CGRect(x: lay.circle.x - d / 2, y: lay.circle.y - d / 2, width: d, height: d)
            ctx.setFillColor(sl.accent.cgColor()); ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.28)); ctx.setLineWidth(0.5)
            ctx.strokeEllipse(in: rect.insetBy(dx: 0.25, dy: 0.25))
            drawSymbol(sl.symbol, pointSize: RingStyle.iconPointSize * scale, at: lay.circle)
            for l in lay.lines {
                attributed(l.text, font: RingStyle.sliceLabelFont, color: RingStyle.textPrimary).draw(at: l.rect.origin)
            }
        }
        ctx.endTransparencyLayer(); ctx.restoreGState()

        // 4. Disabled message in the centre ----------------------------------------------------------
        if st.disabled {
            drawSymbol("photo.on.rectangle", pointSize: 19, at: CGPoint(x: 0, y: 16), alpha: 0.78)
            let ps = NSMutableParagraphStyle(); ps.alignment = .center; ps.lineBreakMode = .byWordWrapping
            let msg = NSAttributedString(string: "Pilih gambar di Finder", attributes: [
                .font: RingStyle.centreFont, .foregroundColor: NSColor(white: 1, alpha: 0.9), .paragraphStyle: ps])
            let w: CGFloat = 80
            let bb = msg.boundingRect(with: CGSize(width: w, height: 100), options: [.usesLineFragmentOrigin])
            msg.draw(with: CGRect(x: -w / 2, y: -4 - bb.height, width: w, height: bb.height),
                     options: [.usesLineFragmentOrigin])
        }

        // 5. Submenu arc -----------------------------------------------------------------------------------
        if !st.disabled, let o = st.openSubmenu, o >= 0, o < slices.count, counts[o] > 0 {
            let n = counts[o], items = slices[o].subItems, accent = slices[o].accent
            let sp = max(0, min(1, st.submenuProgress))
            ctx.saveGState()
            let s = 0.94 + 0.06 * sp
            ctx.scaleBy(x: s, y: s); ctx.setAlpha(sp)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            shapeLayer(ctx, alpha: RingStyle.layerAlpha) {
                for k in 0..<n {
                    let r = G.subItemRange(slice: o, item: k, count: n)
                    var fill = RingStyle.sliceFill
                    if st.hoveredSubItem == k {
                        fill = accent.mixed(with: RingColor(0x000000), st.pressed ? 0.62 : RingStyle.subHoverDarken)   // darkened: white text >= 4.5:1 even after the 90% composite on white
                    }
                    let path = sectorPath(inR: G.subInnerRadius, outR: G.subOuterRadius, a: r.start, b: r.end, gap: gap, cr: cr)
                    fillRounded(ctx, path, color: fill.cgColor(), cr: cr)
                }
            }
            for k in 0..<n {
                let rect = subLabelRect(slice: o, item: k, count: n, label: items[k].label)
                let hot = st.hoveredSubItem == k
                let a = attributed(items[k].label,
                                   font: hot ? NSFont.systemFont(ofSize: 13, weight: .semibold) : RingStyle.subLabelFont,
                                   color: hot ? .white : RingStyle.textPrimary)
                a.draw(at: rect.origin)
            }
            ctx.endTransparencyLayer(); ctx.restoreGState()
        }

        if op < 1 { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }
}

// MARK: - Live view

public final class RingView: NSView {
    public var state = RingState() { didSet { if state != oldValue { needsDisplay = true } } }
    public override var isFlipped: Bool { false }        // y-up: hitTest dy = point.y - centre.y
    public override var isOpaque: Bool { false }
    public override var intrinsicContentSize: NSSize { NSSize(width: G.canvasSize, height: G.canvasSize) }
    typealias G = RingGeometry

    public var centre: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    /// Hit test a point in this view's coordinates.
    public func selection(at p: CGPoint) -> Selection {
        if state.disabled { return .none }
        let counts = RingModel.subItemCounts(webpAvailable: state.webpAvailable)
        return RingGeometry.hitTest(   // call via RingGeometry: bare `hitTest` would resolve to NSView.hitTest(_:)
            dx: p.x - centre.x, dy: p.y - centre.y,
                                    openSubmenuOf: state.openSubmenu, subItemCounts: counts)
    }

    public override func draw(_ dirtyRect: NSRect) {
        RingRenderer.draw(state: state, centre: centre)
    }

    /// Offscreen render to PNG data. `scale` = pixels per point (use 2). `background` nil = transparent.
    public static func pngData(state: RingState, scale: CGFloat = 2, background: NSColor? = nil) -> Data? {
        let side = G.canvasSize
        let px = Int(side * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = NSSize(width: side, height: side)     // points; context CTM maps points -> pixels
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        gc.cgContext.scaleBy(x: scale, y: scale)
        if let bg = background { bg.setFill(); CGRect(x: 0, y: 0, width: side, height: side).fill() }
        RingRenderer.draw(state: state, centre: CGPoint(x: side / 2, y: side / 2))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
