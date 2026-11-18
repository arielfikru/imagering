#!/bin/bash
# Tests every action with `ImageRing --run` on generated fixtures (test/fixtures -> test/work).
# Prints one PASS/FAIL line per case and a final count. Originals are md5-checked at the end.
# Not covered: Compress "Custom..." (opens a dialog), the hotkey/panel (see NOTES.md).
set -u
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/ImageRing.app/Contents/MacOS/ImageRing"
PROBE="$ROOT/test/bin/probe"
mkdir -p "$ROOT/test/bin"
[ -x "$ROOT/test/bin/make_fixtures" ] || swiftc -O -o "$ROOT/test/bin/make_fixtures" "$ROOT/test/tools/make_fixtures.swift"
[ -x "$ROOT/test/bin/clipcheck" ] || swiftc -O -o "$ROOT/test/bin/clipcheck" "$ROOT/test/tools/clipcheck.swift"
PASS=0; FAIL=0

check() {  # check "<name>" <command...>
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "PASS $name"; PASS=$((PASS+1))
    else echo "FAIL $name"; FAIL=$((FAIL+1)); fi
}
kv()     { "$PROBE" "$1" | tr ' ' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }   # kv <file> <key>
is_red() { local v; v=$(kv "$1" "$2"); local r=${v%%,*}; local g=${v#*,}; g=${g%%,*}; [ "$r" -gt 150 ] && [ "$g" -lt 110 ]; }
size_is(){ [ "$(kv "$1" size)" = "$2" ]; }
has()    { [ "$(kv "$1" "$2")" = "$3" ]; }   # has <file> <key> <value>
run()    { RUN_OUT=$("$APP" --run "$@" 2>&1); RUN_RC=$?; export RUN_OUT RUN_RC; }
result_is() { echo "$RUN_OUT" | grep -q "^RESULT $1 "; }   # e.g. "ok=1 skipped=0 failed=0"
export -f kv is_red size_is has result_is
export PROBE

./build.sh >/dev/null 2>&1 || { echo "FAIL build"; exit 1; }
[ -x "$PROBE" ] || swiftc -O -o "$PROBE" test/tools/probe.swift
[ -d test/fixtures ] || test/bin/make_fixtures test/fixtures >/dev/null
rm -rf test/work && cp -R test/fixtures test/work
W="$ROOT/test/work"; cd "$W"
ORIGINALS=("holiday photo.jpg" "shot.png" "tiny.png" "clip.heic" "notes.txt")
md5_before=$(for f in "${ORIGINALS[@]}"; do md5 -q "$f"; done)
md5_after() { for f in "${ORIGINALS[@]}"; do md5 -q "$f"; done; }

J="$W/holiday photo.jpg"; P="$W/shot.png"; T="$W/tiny.png"; H="$W/clip.heic"; N="$W/notes.txt"

# Sanity: originals really carry the metadata and red corner the tests rely on
check "sanity original jpg has EXIF+GPS+Make" bash -c "[ \"\$(kv '$J' gps)\" = 1 ] && [ \"\$(kv '$J' make)\" = 1 ] && [ \"\$(kv '$J' exif)\" = 1 ]"
check "sanity original png has description" has "$P" pngdesc 1
check "sanity original heic has GPS" has "$H" gps 1
check "sanity original jpg red at TL" is_red "$J" TL

# Compress
run compress.500kb "$J"
check "compress 500KB: RESULT ok=1" result_is "ok=1 skipped=0 failed=0"
check "compress 500KB: output exists, named <name>-500KB.jpg" test -f "$W/holiday photo-500KB.jpg"
check "compress 500KB: output <= 500000 bytes" bash -c "[ \$(stat -f%z '$W/holiday photo-500KB.jpg') -le 500000 ]"
run compress.1mb "$T"
check "compress 1MB on 599-byte file: skipped, no output" bash -c "[ ! -e '$W/tiny-1MB.jpg' ] && grep -q 'skipped=1' <<<\"\$RUN_OUT\""

# Resize
run resize.50pct "$J"
check "resize 50%: RESULT ok=1" result_is "ok=1 skipped=0 failed=0"
check "resize 50%: output 2000x1500 jpeg" bash -c "size_is '$W/holiday photo-50pct.jpg' 2000x1500 && has '$W/holiday photo-50pct.jpg' uti public.jpeg"
run resize.3840 "$J"
check "resize 3840px: output long edge 3840 (3840x2880)" size_is "$W/holiday photo-3840px.jpg" 3840x2880
run resize.1920 "$J"
check "resize 1920px: output 1920x1440" size_is "$W/holiday photo-1920px.jpg" 1920x1440
run resize.800 "$T"
check "resize 800px on 200x100: skipped, no output" bash -c "grep -q 'skipped=1' <<<\"\$RUN_OUT\" && [ ! -e '$W/tiny-800px.png' ]"
run resize.50pct "$H"
check "resize 50% on HEIC: output clip-50pct.heic 1500x1000 heic" bash -c "size_is '$W/clip-50pct.heic' 1500x1000 && has '$W/clip-50pct.heic' uti public.heic"
run resize.50pct "$J"
check "collision: second resize 50% gets -2 suffix" test -f "$W/holiday photo-50pct-2.jpg"

# Convert
run convert.jpg "$J"
check "convert jpg->jpg: skipped (already jpg)" bash -c "grep -q 'skipped=1' <<<\"\$RUN_OUT\""
run convert.png "$J"
check "convert jpg->png: holiday photo.png is png, 4000x3000" bash -c "has '$W/holiday photo.png' uti public.png && size_is '$W/holiday photo.png' 4000x3000"
run convert.heic "$P"
check "convert png->heic: shot.heic is heic" has "$W/shot.heic" uti public.heic
run convert.webp "$P"
check "convert png->webp: shot.webp has RIFF/WEBP header" bash -c "[ \"\$(head -c 4 '$W/shot.webp')\" = RIFF ] && [ \"\$(head -c 12 '$W/shot.webp' | tail -c 4)\" = WEBP ]"
check "convert png->webp: RESULT ok=1" result_is "ok=1 skipped=0 failed=0"

# Rotate (red marker starts top-left: ccw90 -> bottom-left, cw90 -> top-right, 180 -> bottom-right)
run rotate.ccw90 "$J"
check "rotate ccw90: 3000x4000 and marker at BL" bash -c "size_is '$W/holiday photo-rot270.jpg' 3000x4000 && is_red '$W/holiday photo-rot270.jpg' BL && ! is_red '$W/holiday photo-rot270.jpg' TL"
run rotate.cw90 "$J"
check "rotate cw90: 3000x4000 and marker at TR" bash -c "size_is '$W/holiday photo-rot90.jpg' 3000x4000 && is_red '$W/holiday photo-rot90.jpg' TR"
run rotate.180 "$J"
check "rotate 180: 4000x3000 and marker at BR" bash -c "size_is '$W/holiday photo-rot180.jpg' 4000x3000 && is_red '$W/holiday photo-rot180.jpg' BR"

# Strip metadata
run strip "$J"
check "strip jpg: RESULT ok=1" result_is "ok=1 skipped=0 failed=0"
check "strip jpg: no DateTime/GPS/Make, same size, marker TL" bash -c "has '$W/holiday photo-clean.jpg' dt 0 && has '$W/holiday photo-clean.jpg' gps 0 && has '$W/holiday photo-clean.jpg' make 0 && size_is '$W/holiday photo-clean.jpg' 4000x3000 && is_red '$W/holiday photo-clean.jpg' TL"
run strip "$P"
check "strip png: description removed" has "$W/shot-clean.png" pngdesc 0
run strip "$H"
check "strip heic: no DateTime/GPS/Make, output heic" bash -c "has '$W/clip-clean.heic' gps 0 && has '$W/clip-clean.heic' dt 0 && has '$W/clip-clean.heic' make 0 && has '$W/clip-clean.heic' uti public.heic"

# Copy (clipboard is overwritten)
run copy "$J"
check "copy: RESULT ok=1" result_is "ok=1 skipped=0 failed=0"
check "copy: clipboard has PNG data and public.file-url" bash -c "'$ROOT/test/bin/clipcheck' | grep -q 'public.file-url' && '$ROOT/test/bin/clipcheck' | grep -q 'public.png'"

# Failure path and originals
run resize.50pct "$N"
check "non-image file: exit 1, RESULT failed=1" bash -c "[ '$RUN_RC' = 1 ] && grep -q 'failed=1' <<<\"\$RUN_OUT\""
md5_now=$(md5_after)
check "originals unchanged (md5 before == after)" [ "$md5_now" = "$md5_before" ]

# Visuals: --render must equal the design reference shots byte for byte
cd "$ROOT"
mkdir -p test/render
for s in idle hover-slice submenu-open hover-subitem no-selection pressed-subitem pressed-slice submenu-rotate submenu-resize; do
    "$APP" --render "$s" "test/render/$s.png" >/dev/null 2>&1
    check "render $s == design/shots/$s.png" cmp -s "test/render/$s.png" "design/shots/$s.png"
done
check "--selftest exits 0" "$APP" --selftest

echo "TOTAL $PASS/$((PASS+FAIL)) passed"
[ "$FAIL" -eq 0 ]
