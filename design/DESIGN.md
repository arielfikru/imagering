# ImageRing design

## Files

- Reference implementation: `Sources/RingGeometry.swift`, `Sources/RingModel.swift`, `Sources/RingView.swift`.
- Screenshots: `design/shots/*.png` (2x, mid-grey `#7F7F82`; `*-light.png` on white). Rebuild with `design/render.sh`.
- Call `RingGeometry.hitTest(...)` from any `NSView` subclass: the bare name `hitTest` resolves to `NSView.hitTest(_:)` there.

## Coordinates

- Origin = ring centre. **y-up** (AppKit non-flipped; `dy = mouse.y - centre.y`). In a flipped view negate dy.
- Ring angle theta = radians **clockwise from 12 o'clock**: `theta = atan2(dx, dy)` normalised to [0, 2pi). 12h = 0, 3h = 90 deg, 6h = 180 deg, 9h = 270 deg.
- CoreGraphics angle = `pi/2 - theta` (`RingGeometry.cgAngle`). Point on ring = `(r sin theta, r cos theta)`.
- Panel/view must be square, `RingGeometry.canvasSize` = **512 pt** (outer radius 226 + 30 shadow margin each side). The ring is centred in it. Draw and hit-test around `bounds.mid`.

## Geometry (points)

| Item | Value |
|---|---|
| Centre dead zone (cancel) radius | 54 |
| Inner ring | r 54 to 152 (thickness 98) |
| Gap between rings | 8 (r 152 to 160) |
| Submenu arc | r 160 to 226 (thickness 66) |
| Gap between neighbouring shapes | 2.5, constant width, parallel edges |
| Corner radius | 5 (all shapes) |
| Slices | 6 x 60 deg. **Slice i is centred at i x 60 deg** (Compress 0 = 12 o'clock, Resize 60, Convert 120, Rotate 180, Strip 240, Copy 300). Dividers at 30, 90, 150, 210, 270, 330 deg. Change `sliceZeroCentre` to rotate everything. |
| Slice content | icon circle + label, centred on r = 103 along the slice centre angle, kept upright (not rotated) |
| Sub-item width | 28 deg each, equal for all items. Arc span = n x 28 deg (Compress/Resize 140, Convert 112 or 84, Rotate 84). |
| Submenu arc position | **centred on the parent slice's centre angle**, so it is wider than its 60 deg parent and overhangs neighbouring slices. Items run clockwise from the arc start, except arcs centred near the bottom (Rotate), which run counter-clockwise so they read left to right: `RingGeometry.subItemsReversed(slice:)`, used by both drawing and hit-testing. |
| Sub-item label | centred at r = 193 on the item centre angle, upright |

### Hit-testing rules (`hitTest(dx:dy:openSubmenuOf:subItemCounts:)`)

1. r < 54: `.none` (centre, cancel).
2. 54 to 152: `.slice(index)` by angle.
3. Gap 152 to 160: with a submenu open and the angle inside its arc span, `.slice(open)` (sticky, so the arc does not flicker closed while crossing); otherwise `.none`.
4. 160 to 226 with a submenu open and the angle inside the arc span: `.subItem(open, item)`, even over a neighbouring slice's angle.
5. Anything else (beyond 226, outside the arc span, outer band with nothing open, slice without submenu): `.none`. Host: release or click on `.none` cancels.
6. `subItemCounts` defaults to `[5,5,4,3,0,0]`; use `RingModel.subItemCounts(webpAvailable:)` (Convert has 3 items without cwebp).

## Colours

| Role | Value |
|---|---|
| Slice / sub-item idle fill | `#27272B` (drawn opaque, whole ring composited at 90% alpha) |
| Slice hovered | `#5E5E64` (lighter, as in the reference) |
| Slice pressed | `#27272B` mixed 50% with the slice accent (only when no sub-item is hovered) |
| Sub-item hovered | slice accent mixed 50% with black. Measured on the composited pixels (90% alpha) over white: green 5.25:1, orange 4.84:1 vs white text; blue and purple are higher. Raw accents are about 2:1 and fail. |
| Sub-item pressed | accent mixed 62% with black |
| Label text | white 96% (on idle fill 14.9:1; on hovered slice 6.4:1) |
| Icon glyph | white |
| Icon circle | the slice accent, 0.5 pt white 28% hairline |
| Centre disc | black-ish `#1A1A1A` at 12% with a 1 pt white 14% ring; disabled: 92% opaque |
| Disabled content | slices at 40% opacity; centre message white 90%, icon white 78% |
| Shadow | black 45%, blur 22, offset (0, -7) pt (down), one shadow per ring group |

Text is drawn on dark shapes, so it reads on any Finder background (checked on `#7F7F82` and white).
No `NSVisualEffectView`: it does not render offscreen and would make PNGs differ from the app. A vibrancy backdrop can be added later behind `RingView` without changing the drawing code.

## Typography and icons

| Element | Spec |
|---|---|
| Slice label | SF (system font) 11.5 pt semibold; wraps to two lines only when wider than 72 pt ("Strip metadata" becomes "Strip" / "metadata") |
| Sub-item label | SF 13 pt medium; hovered 13 pt semibold |
| Centre message | SF 12 pt medium, centred, wraps in 80 pt width |
| Icon circle | 38 pt diameter; hovered 1.07x, pressed 0.95x |
| Icon glyph | SF Symbol 17 pt semibold, palette white; centre message symbol 19 pt |

## Slices

| # | Slice | SF Symbol | Accent |
|---|---|---|---|
| 0 | Compress | `arrow.down.right.and.arrow.up.left` | `#34C759` |
| 1 | Resize | `aspectratio` | `#0A84FF` |
| 2 | Convert | `arrow.triangle.2.circlepath` | `#BF5AF2` |
| 3 | Rotate | `rotate.right` | `#FF9F0A` |
| 4 | Strip metadata | `eye.slash` | `#FF453A` |
| 5 | Copy | `doc.on.doc` | `#40C8E0` |

Sub-items are text only (no icons): Compress 500 KB, 1 MB, 2 MB, 5 MB, Custom…; Resize 50%, 3840 px, 1920 px, 1280 px, 800 px; Convert JPG, PNG, HEIC, WebP (last only if cwebp exists); Rotate 90° ↺, 90° ↻, 180°.

## States

| State | `RingState` | Look |
|---|---|---|
| Idle | all nil | six dark slices, empty centre, no arc |
| Slice hovered | `hoveredSlice = i` | slice fill `#5E5E64`, icon circle 1.07x. No arc for Strip/Copy. |
| Submenu open | `hoveredSlice = i, openSubmenu = i` | outer arc with all sub-items idle, parent slice stays highlighted |
| Sub-item hovered | plus `hoveredSubItem = k` | that sub-item filled with the darkened accent, label semibold; parent slice stays highlighted |
| Pressed | plus `pressed = true` | applies to the innermost hovered item only: with a sub-item hovered, that sub-item darkens and the parent slice keeps its plain hover look; otherwise the slice fill mixes toward its accent and the icon scales to 0.95x. Action fires on release. |
| Disabled (no image) | `disabled = true` | slices 40% opacity, no hover, no arc, centre disc nearly opaque with `photo.on.rectangle` and "Pilih gambar di Finder" |

Convenience: `RingState(selection:openSubmenu:)` builds the hover fields from a `Selection`.

## Animation (host drives the numbers; drawing takes `openProgress` and `submenuProgress`)

- Open: 120 ms ease-out, scale 0.92 to 1 about the centre plus fade 0 to 1 (`openProgress`).
- Slice hover: fill cross-fade 90 ms ease-out. Icon scale 1 to 1.07 with the same timing.
- Submenu arc in: 110 ms ease-out, scale 0.94 to 1 plus fade (`submenuProgress`). Switching to another slice: old arc out 60 ms, new arc in 110 ms. Arc out: 60 ms.
- Sub-item hover: 70 ms fill cross-fade.
- Pressed: immediate (no animation).
- Close/cancel: 80 ms fade, no scale. Honour Reduce Motion: drop the scale, keep 80 ms fades.

## Do / Don't

- Do keep the arc centred on its parent and use the same angular width for every item.
- Do keep the parent slice highlighted while a sub-item is hovered.
- Do treat the gap as sticky only inside the arc's angular span.
- Do keep all labels upright and horizontal.
- Do pass `webpAvailable` from the app; the model never touches disk.
- Don't draw the arc over the gap or touching the inner ring.
- Don't put a title, subtitle or eyebrow text anywhere in the ring (the only extra text is the disabled message in the centre).
- Don't rotate labels along the arc, and don't add per-item icons in the arc.
- Don't use a flipped view without negating dy.
- Don't reduce the 8 pt gap or the 54 pt cancel zone: both are touch targets for hold-mode release.

## Self-test

`design/geometry_test.sh` (compiles `RingGeometry.swift` + `RingModel.swift` + `design/geometry_test.swift` with `swiftc -swift-version 5 -parse-as-library`, no AppKit) prints `ALL PASS`.
`design/render.sh` writes the PNGs (including `pressed-subitem` and `open-half`, a frame at `openProgress = submenuProgress = 0.5`) and runs a measured label-fit check (every label and icon circle must lie inside its shape with 3 pt padding).
