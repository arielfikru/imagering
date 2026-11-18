# ImageRing — spec

A background macOS app (no Dock icon, `LSUIElement`). In Finder, select one or more images,
press a global hotkey, and a radial (pie) menu appears around the mouse cursor. Pick an
action; results are written next to the originals (originals are never modified).

Visual reference: a pie-menu sketch from the user
(inner ring of slices with an icon circle + label each, hovered slice lighter, white/empty
centre, and a separate outer arc showing the submenu of the hovered slice, with a gap
between the rings).

## Interaction
- Hotkey: **⌃⌥Space** (Carbon `RegisterEventHotKey`, no Accessibility permission needed).
- Hold mode: hold the hotkey, move the mouse toward a slice, release → runs the hovered item.
- Tap mode: if the hotkey is released < 250 ms after press, the ring stays open; click an item.
- Hovering a slice that has a submenu opens the outer arc; moving outward onto the arc selects
  a sub-item. Moving back into the inner ring returns to slice selection.
- Centre circle = cancel (dead zone). Esc cancels. Clicking outside cancels.
- Ring centres on the mouse, clamped so it fits on the screen that holds the cursor.
- Only acts on Finder's selection, read at hotkey-press time while Finder is frontmost.
  Non-image files are ignored. No image selected → ring shows a disabled state with a short
  message in the centre ("Pilih gambar di Finder").
- Panel is a borderless transparent non-activating `NSPanel` so Finder keeps focus/selection.

## Menu (inner ring, clockwise from top)
| Slice | Submenu (outer arc) | Backend |
|---|---|---|
| Compress | 500 KB · 1 MB · 2 MB · 5 MB · Custom… | `~/.local/bin/img-shrink <target> files…` (existing, tested) |
| Resize | 50% · 3840 px · 1920 px · 1280 px · 800 px (long edge) | `sips -Z` / scale |
| Convert | JPG · PNG · HEIC · WebP (WebP only if `/opt/homebrew/bin/cwebp` exists) | `sips -s format`, `cwebp` |
| Rotate | 90° ↺ · 90° ↻ · 180° | `sips -r` |
| Strip metadata | — (runs directly) | re-encode without EXIF/GPS |
| Copy | — (copies the first image to the clipboard) | NSPasteboard |

Output naming: `<name>-<suffix>.<ext>` next to original, with `-2`, `-3` on collision.
After running: a macOS notification with the result (same style as `img-shrink`).

## Build
- No Xcode: Command Line Tools only. Build with `swiftc -swift-version 5` into a hand-assembled
  `ImageRing.app` bundle, ad-hoc signed (`codesign -s -`), installed to `~/Applications`.
- Info.plist must contain `LSUIElement=true` and `NSAppleEventsUsageDescription`.
- Debug flags: `--render <state> <out.png>` renders the ring offscreen to a PNG
  (states: idle, hover-slice, submenu-open, hover-subitem, no-selection);
  `--demo` shows the ring at the cursor with a fake selection.
- Hit-testing is one pure function `hitTest(dx, dy, openSubmenuOf) -> Selection` shared by
  drawing and input, unit-testable without a GUI.
