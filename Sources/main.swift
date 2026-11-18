// main.swift -- entry point and debug modes:
//   (none)                       run as the status-bar app
//   --demo                       ring at the cursor with a fake selection; picks print their id
//   --render <state> <out.png> [grey|light|clear]   offscreen PNG via RingView.pngData (default grey)
//   --run <itemId> <files...>    run one action headlessly, print OUT lines and RESULT
//   --selftest                   pure-logic and environment checks
//   --log <path>                 also append the log to this file (any mode)
import AppKit

let argv = CommandLine.arguments
if let i = argv.firstIndex(of: "--log"), i + 1 < argv.count { Log.path = argv[i + 1] }

func renderStates() -> [String: (inout RingState) -> Void] {
    [
        "idle": { _ in },
        "hover-slice": { $0.hoveredSlice = 0 },
        "submenu-open": { $0.hoveredSlice = 0; $0.openSubmenu = 0 },
        "hover-subitem": { $0.hoveredSlice = 0; $0.openSubmenu = 0; $0.hoveredSubItem = 1 },
        "no-selection": { $0.disabled = true },
        "pressed-subitem": { $0.hoveredSlice = 0; $0.openSubmenu = 0; $0.hoveredSubItem = 1; $0.pressed = true },
        "open-half": { $0.hoveredSlice = 0; $0.openSubmenu = 0; $0.openProgress = 0.5; $0.submenuProgress = 0.5 },
        "pressed-slice": { $0.hoveredSlice = 3; $0.pressed = true },
        "submenu-rotate": { $0.hoveredSlice = 3; $0.openSubmenu = 3; $0.hoveredSubItem = 2 },
        "submenu-resize": { $0.hoveredSlice = 1; $0.openSubmenu = 1; $0.hoveredSubItem = 1 },
    ]
}

func renderMain(_ args: [String]) -> Int32 {
    guard args.count >= 4 else { print("usage: --render <state> <out.png> [grey|light|clear]"); return 2 }
    guard let apply = renderStates()[args[2]] else { print("unknown state \(args[2])"); return 2 }
    var st = RingState()
    apply(&st)
    st.webpAvailable = FileManager.default.fileExists(atPath: Actions.cwebpPath)
    let bgName = args.count >= 5 ? args[4] : "grey"
    let bg: NSColor?
    switch bgName {
    case "light": bg = .white
    case "clear": bg = nil
    default: bg = NSColor(srgbRed: 0x7F / 255, green: 0x7F / 255, blue: 0x82 / 255, alpha: 1)
    }
    guard let data = RingView.pngData(state: st, scale: 2, background: bg) else { print("render failed"); return 1 }
    do { try data.write(to: URL(fileURLWithPath: args[3])) } catch { print("write failed: \(error)"); return 1 }
    print("RENDER \(args[2]) -> \(args[3])")
    return 0
}

func runMain(_ args: [String]) -> Int32 {
    guard args.count >= 3 else { print("usage: --run <itemId> <files...>"); return 2 }
    guard let action = ImageAction.parse(args[2]) else { print("unknown item id \(args[2])"); return 2 }
    let files = args.dropFirst(3).map { URL(fileURLWithPath: $0) }
    let o = Actions.perform(action, files: files)
    for p in o.outputs { print("OUT \(p)") }
    for n in o.notes { print("NOTE \(n)") }
    print("RESULT ok=\(o.ok) skipped=\(o.skipped) failed=\(o.failed) summary=\(o.summary)")
    return o.failed == 0 ? 0 : 1
}

func selftestMain() -> Int32 {
    var fails = 0
    func check(_ name: String, _ ok: Bool) {
        print((ok ? "PASS " : "FAIL ") + name)
        if !ok { fails += 1 }
    }
    check("releaseMode 0 ms is tap", releaseMode(heldMs: 0) == .tap)
    check("releaseMode 249.9 ms is tap", releaseMode(heldMs: 249.9) == .tap)
    check("releaseMode 250 ms is hold", releaseMode(heldMs: 250) == .hold)
    check("releaseMode 1000 ms is hold", releaseMode(heldMs: 1000) == .hold)

    let slices = RingModel.slices(webpAvailable: true)
    for s in slices {
        if s.subItems.isEmpty {
            check("action parses for \(s.id)", ImageAction.parse(s.id) != nil)
        } else {
            for it in s.subItems {
                let id = "\(s.id).\(it.id)"
                check("action parses for \(id)", ImageAction.parse(id) != nil)
            }
        }
    }
    check("centre cancels", resolve(.none, slices: slices, disabled: false, hold: true) == .cancel)
    check("submenu slice tap stays open", resolve(.slice(0), slices: slices, disabled: false, hold: false) == .stay)
    check("submenu slice hold cancels", resolve(.slice(0), slices: slices, disabled: false, hold: true) == .cancel)
    check("Strip runs directly", resolve(.slice(4), slices: slices, disabled: false, hold: true) == .run("strip"))
    check("sub-item maps to id", resolve(.subItem(slice: 0, item: 1), slices: slices, disabled: false, hold: true) == .run("compress.1mb"))
    check("disabled cancels", resolve(.subItem(slice: 0, item: 1), slices: slices, disabled: true, hold: false) == .cancel)
    check("webp absent hides WebP item", !RingModel.slices(webpAvailable: false)[2].subItems.contains { $0.id == "webp" })
    check("webp present shows WebP item", RingModel.slices(webpAvailable: true)[2].subItems.contains { $0.id == "webp" })
    check("cwebp detected", FileManager.default.fileExists(atPath: Actions.cwebpPath))
    print("INFO isFinderFrontmost=\(FinderSelection.isFinderFrontmost)")
    let (paths, err) = FinderSelection.selectedPaths()
    print("INFO finder paths=\(paths) errorNumber=\(err.map(String.init) ?? "none")")
    check("Finder AppleScript runs without error", err == nil)
    let inst = Hotkey.shared.installHandler()
    check("InstallEventHandler status 0 (got \(inst))", inst == noErr)
    let reg = Hotkey.shared.registerMain()
    print("INFO RegisterEventHotKey(ctrl+opt+space)=\(reg) (-9878 means another process holds it)")
    Hotkey.shared.unregisterMain()
    print("SELFTEST failures=\(fails)")
    return fails == 0 ? 0 : 1
}

if argv.count >= 2 && argv[1] == "--render" { exit(renderMain(argv)) }
if argv.count >= 2 && argv[1] == "--run" { exit(runMain(argv)) }
if argv.contains("--selftest") { exit(selftestMain()) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if argv.contains("--demo") {
    let c = RingController()
    gDemoController = c
    gHotkeyHandler = { c.hotkeyEvent($0) }
    Hotkey.shared.installHandler()
    c.openDemo()
    app.run()
} else {
    let d = AppDelegate()
    gDelegate = d
    app.delegate = d
    app.run()
}
