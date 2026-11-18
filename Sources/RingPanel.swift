// RingPanel.swift -- the ring window and its interaction state machine.
// Drawing and hit-testing come from RingView / RingGeometry / RingModel, unchanged.
import AppKit

// MARK: - Pure decisions (exercised by --selftest)

/// SPEC: released >= 250 ms after press = hold. Released earlier = tap (the ring stays open).
enum ReleaseMode: Equatable { case hold, tap }
func releaseMode(heldMs: Double) -> ReleaseMode { heldMs >= 250 ? .hold : .tap }

enum Resolution: Equatable {
    case run(String)   // item id to run
    case stay          // tap-click on a slice that only opens its submenu
    case cancel
}

/// What a pick means. A slice with a submenu has no action of its own:
/// hold-release on it cancels, tap-click leaves the ring open.
func resolve(_ sel: Selection, slices: [RingSlice], disabled: Bool, hold: Bool) -> Resolution {
    if disabled { return .cancel }
    switch sel {
    case .none: return .cancel
    case .slice(let i):
        let s = slices[i]
        if s.subItems.isEmpty { return .run(s.id) }
        return hold ? .cancel : .stay
    case .subItem(let s, let k):
        return .run("\(slices[s].id).\(slices[s].subItems[k].id)")
    }
}

// MARK: - Host view: receives the mouse (RingView itself is final and has no mouse handlers)

final class RingHostView: NSView {
    weak var controller: RingController?
    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return self }
        return bounds.contains(convert(point, from: sv)) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { controller?.mouseDown() }
    override func mouseUp(with event: NSEvent) {
        controller?.mouseUp(at: convert(event.locationInWindow, from: nil))
    }
}

// MARK: - Controller

final class RingController {
    private var panel: NSPanel?
    private var ring: RingView?
    private var origin = CGPoint.zero          // panel frame origin in screen points
    private var slices: [RingSlice] = []
    private var images: [URL] = []
    private var demo = false
    private var pressedAt: Double?             // systemUptime of the hotkey press being held
    private var loading = false                // Finder read in progress (blocking)
    private var pendingHoldRelease = false     // hold released while the Finder read was blocking
    private var openedAt = 0.0
    private var submenuStart = 0.0
    private var timer: Timer?
    private var outsideMonitor: Any?

    private var uptime: Double { ProcessInfo.processInfo.systemUptime }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var isOpen: Bool { panel != nil }

    // MARK: entry points

    func hotkeyEvent(_ e: HotkeyEvent) {
        switch e {
        case .press: onPress()
        case .release: onRelease()
        case .escape: close("Esc")
        }
    }

    /// --demo: ring at the cursor with a fake selection. Picks print their id and do nothing else.
    func openDemo() {
        demo = true
        images = []
        show(disabled: false)
        Hotkey.shared.registerEscape()
    }

    private func onPress() {
        guard !isOpen else { Log.write("PRESS ignored: ring already open"); return }
        pressedAt = uptime
        let front = FinderSelection.isFinderFrontmost
        Log.write("PRESS frontmost=\(front ? "finder" : "other")")
        show(disabled: false)                // panel first (idle look): NSAppleScript blocks and pumps the run loop
        guard front else {
            images = []
            Log.write("FINDER skipped: frontmost is not Finder")
            finishLoading()
            return
        }
        loading = true
        let (paths, err) = FinderSelection.selectedPaths()
        loading = false
        images = FinderSelection.imageFiles(paths)
        Log.write("FINDER selected=\(paths.count) images=\(images.count) errorNumber=\(err.map(String.init) ?? "none")")
        finishLoading()
    }

    private func finishLoading() {
        guard let ring = ring else { return }
        var st = ring.state
        st.disabled = images.isEmpty
        ring.state = st
        if pendingHoldRelease {
            pendingHoldRelease = false
            commitHoldRelease()
        }
    }

    private func onRelease() {
        guard let p = pressedAt else { return }
        pressedAt = nil
        guard isOpen else { return }          // released after the ring already closed
        let held = (uptime - p) * 1000
        guard releaseMode(heldMs: held) == .hold else {
            Log.write(String(format: "RELEASE after %.0f ms: tap, ring stays open", held))
            return
        }
        if loading { pendingHoldRelease = true; return }
        commitHoldRelease()
    }

    private func commitHoldRelease() {
        let sel = updateHover()
        let r = resolve(sel, slices: slices, disabled: ring?.state.disabled ?? true, hold: true)
        Log.write("RELEASE hold: \(sel) -> \(r)")
        switch r {
        case .run(let id): close("hold release", runID: id)
        case .stay, .cancel: close("hold release, nothing under pointer")
        }
    }

    // MARK: mouse (called by RingHostView)

    func mouseDown() {
        guard isOpen, !loading, let ring = ring else { return }
        var st = ring.state; st.pressed = true; ring.state = st
    }

    func mouseUp(at p: NSPoint) {
        guard isOpen, !loading, let ring = ring else { return }
        var st = ring.state; st.pressed = false; ring.state = st
        let sel = ring.selection(at: p)
        let r = resolve(sel, slices: slices, disabled: ring.state.disabled, hold: false)
        Log.write("CLICK \(sel) -> \(r)")
        switch r {
        case .run(let id): close("pick", runID: id)
        case .stay: updateHover()
        case .cancel: close("click, nothing under pointer")
        }
    }

    // MARK: tracking + animation (60 Hz timer)

    private func localMouse() -> NSPoint {
        let m = NSEvent.mouseLocation
        return NSPoint(x: m.x - origin.x, y: m.y - origin.y)   // ring centre = panel centre
    }

    /// Hit-tests the pointer and updates hover and the open submenu. Returns the selection.
    @discardableResult
    private func updateHover() -> Selection {
        guard let ring = ring else { return .none }
        let sel = ring.selection(at: localMouse())
        var st = ring.state
        switch sel {
        case .none:
            st.hoveredSlice = nil; st.hoveredSubItem = nil          // keep an open arc until the pointer moves onto a slice
        case .slice(let i):
            st.hoveredSlice = i; st.hoveredSubItem = nil
            setOpen(&st, slices[i].subItems.isEmpty ? nil : i)
        case .subItem(let s, let k):
            st.hoveredSlice = s; st.hoveredSubItem = k
            setOpen(&st, s)
        }
        ring.state = st
        return sel
    }

    private func setOpen(_ st: inout RingState, _ slice: Int?) {
        guard slice != st.openSubmenu else { return }
        st.openSubmenu = slice
        if slice != nil { st.submenuProgress = 0; submenuStart = uptime }
    }

    private func tick() {
        guard isOpen else { return }
        updateHover()
        animate()
    }

    /// Open 120 ms ease-out; submenu arc 110 ms ease-out (DESIGN.md). Reduce Motion: jump to 1.
    private func animate() {
        guard let ring = ring else { return }
        var st = ring.state
        let now = uptime
        if reduceMotion {
            st.openProgress = 1
            if st.openSubmenu != nil { st.submenuProgress = 1 }
        } else {
            st.openProgress = easeOut((now - openedAt) / 0.120)
            if st.openSubmenu != nil { st.submenuProgress = easeOut((now - submenuStart) / 0.110) }
        }
        ring.state = st
    }

    private func easeOut(_ t: Double) -> CGFloat {
        let c = min(1, max(0, t))
        return CGFloat(1 - pow(1 - c, 3))
    }

    // MARK: show / close

    private func show(disabled: Bool) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let s = RingGeometry.canvasSize
        let x = min(max(mouse.x - s / 2, vf.minX), vf.maxX - s)
        let y = min(max(mouse.y - s / 2, vf.minY), vf.maxY - s)
        origin = CGPoint(x: x, y: y)

        let webp = FileManager.default.fileExists(atPath: Actions.cwebpPath)
        slices = RingModel.slices(webpAvailable: webp)

        let p = NSPanel(contentRect: NSRect(x: x, y: y, width: s, height: s),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isReleasedWhenClosed = false

        let host = RingHostView(frame: NSRect(x: 0, y: 0, width: s, height: s))
        host.controller = self
        let rv = RingView(frame: host.bounds)
        rv.autoresizingMask = [.width, .height]
        var st = RingState()
        st.webpAvailable = webp
        st.disabled = disabled
        st.openProgress = reduceMotion ? 1 : 0
        rv.state = st
        host.addSubview(rv)
        p.contentView = host
        p.orderFrontRegardless()
        panel = p
        ring = rv
        openedAt = uptime

        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close("click outside")
        }
        Hotkey.shared.registerEscape()
        Log.write("SHOW centre=(\(Int(x + s / 2)),\(Int(y + s / 2))) mouse=(\(Int(mouse.x)),\(Int(mouse.y))) webp=\(webp)")
    }

    /// Fades out (80 ms), then runs the picked action on a background queue (copy hops to main itself).
    private func close(_ why: String, runID: String? = nil) {
        guard let p = panel else { return }
        panel = nil
        ring = nil
        timer?.invalidate(); timer = nil
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        Hotkey.shared.unregisterEscape()
        pendingHoldRelease = false
        Log.write("CLOSE (\(why)) run=\(runID ?? "none")")
        let files = images
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.08
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            if let id = runID { self?.dispatch(id, files) }
        })
    }

    private func dispatch(_ id: String, _ files: [URL]) {
        if demo { print("DEMO pick \(id)"); return }
        guard let action = ImageAction.parse(id) else { Log.write("unknown item \(id)"); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let o = Actions.perform(action, files: files)
            Log.write("ACTION \(id): ok=\(o.ok) skipped=\(o.skipped) failed=\(o.failed) outputs=\(o.outputs) notes=\(o.notes)")
            if !action.notifiesItself { Notify.send(o.summary) }
        }
    }
}
