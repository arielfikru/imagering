# Notes

Decisions made beyond the brief:
- Slice 0 (Compress) is centred at 12 o'clock (dividers at +-30 deg), not starting at a divider. One constant (`sliceZeroCentre`) changes it.
- Hit-test gap is sticky only inside the open arc's angular span; `subItemCounts` is an injectable defaulted parameter because Convert has 3 or 4 items.
- Arcs centred near the bottom (Rotate) run counter-clockwise so they read left to right (`subItemsReversed`).
- "Strip metadata" wraps to two lines (a one-line label overflowed its slice by the measured check).
- Hovered sub-item fill is the accent darkened 50% (raw accents ~2:1; 38% still gave 4.09:1 for green on white after the 90% composite).
- No live vibrancy (NSVisualEffectView does not render offscreen); shapes are opaque colours composited at 90%.
- Extra PNGs: pressed-slice, pressed-subitem, submenu-rotate, submenu-resize, open-half (each also `-light`).
- Animation and hover transitions are specified in DESIGN.md; the view only takes `openProgress` / `submenuProgress`, the host animates them.
- `design/contrast.swift` is a small helper to sample a PNG pixel and print its contrast vs white.

## Evidence
- Geometry self-test passes: `design/geometry_test.sh | tail -1` -> `ALL PASS`; `design/geometry_test.sh | grep -c '^ok'` -> 78
- Self-test detects a y-flip: `mkdir -p design/.build/mut && sed 's/atan2(dx, dy)/atan2(dx, -dy)/' Sources/RingGeometry.swift > design/.build/mut/RingGeometry.swift && swiftc -swift-version 5 -parse-as-library design/.build/mut/RingGeometry.swift Sources/RingModel.swift design/geometry_test.swift -o design/.build/mut/t && design/.build/mut/t | tail -1` -> `66 FAILURES` (run before the Rotate reversal change; not re-run after)
- 20 PNGs (10 states x grey/white) render at 1024x1024: `design/render.sh | head -1` -> `wrote 20 PNGs`; `file design/shots/idle.png` -> `PNG image data, 1024 x 1024`
- Label fit (measured, webp on/off): `design/render.sh | tail -1` -> `label fit check: OK`; earlier version printed `OVERFLOW slice strip label` before the wrap fix
- Visually inspected with Read after final render: idle, idle-light, hover-slice, hover-slice-light, submenu-open, submenu-open-light, hover-subitem, hover-subitem-light, pressed-subitem, pressed-slice, submenu-rotate-light, submenu-resize, open-half, no-selection. Not opened: submenu-rotate (grey), submenu-resize-light, pressed-*-light, open-half-light, no-selection-light after the last render.
- Composited contrast: `swiftc -swift-version 5 design/contrast.swift -o <tmp>/contrast && <tmp>/contrast design/shots/hover-subitem-light.png 190,105` -> 5.25 (green); `<tmp>/contrast design/shots/submenu-rotate-light.png 350,418` -> 4.84 (orange)
- Pressed sub-item no longer presses parent: `design/shots/pressed-subitem.png` shows parent Compress in plain hover grey, 1 MB dark green; code `slicePressed` in `Sources/RingView.swift`
- RingGeometry.swift imports only CoreGraphics + Foundation: `grep ^import Sources/RingGeometry.swift`
- Stray `${TMPDIR}/imagering-build` created by the first render.sh draft (outside the project) was removed: `rm -rf "${TMPDIR:-/tmp}/imagering-build"`
