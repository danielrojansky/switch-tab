import AppKit

/// Owns the global keyboard tap and the switching session:
/// hold the modifier, press the trigger key to cycle, release the modifier to focus.
final class Switcher {
    static let shared = Switcher()

    private let panel = SwitcherPanel()
    private var tap: CFMachPort?
    private var windows: [WindowInfo] = []
    private var selected = 0
    private var active = false
    private var scope: Scope = .all
    private var holdFlag: CGEventFlags = .maskAlternate
    private var triggerKey = KeyCode.tab
    // for statistics: where the session started and how many moves it took
    private var sessionFrom: String?
    private var sessionMoves = 0

    private static let modifierMask: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl]

    var isListening: Bool { tap != nil }

    private init() {
        panel.onClick = { [weak self] index in
            guard let self, self.active else { return }
            self.selected = index
            self.commit()
        }
        panel.onHover = { [weak self] index in
            guard let self, self.active, Settings.shared.hoverSelect, index != self.selected else { return }
            self.selected = index
            self.panel.select(index, animated: true)
        }
        panel.onAction = { [weak self] index, action in
            guard let self, self.active else { return }
            self.selected = index
            self.perform(action)
        }
    }

    /// Installs the keyboard tap. Returns false until the Accessibility permission is granted.
    @discardableResult
    func startListening() -> Bool {
        if tap != nil { return true }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, _ in
                Switcher.shared.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: nil)
        else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        return true
    }

    /// Returns true when the event is consumed and must not reach other apps.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        let flags = event.flags
        let held = flags.intersection(Switcher.modifierMask)
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let settings = Settings.shared

        switch type {
        case .keyDown:
            if !active {
                if settings.pinShortcutEnabled, keyCode == KeyCode.t, held == [.maskControl, .maskAlternate] {
                    PinManager.shared.toggleFocused()
                    return true
                }
                let shortcuts: [(CGEventFlags, Int, Scope)] = [
                    (Settings.flags(forModifier: settings.holdModifier), settings.triggerKey, .all),
                    (Settings.flags(forModifier: settings.appHoldModifier), settings.appTriggerKey, .activeApp),
                ]
                for (hold, key, scope) in shortcuts where keyCode == key && held == hold {
                    return begin(hold: hold, key: key, scope: scope, backward: flags.contains(.maskShift))
                }
                return false
            }

            if keyCode == triggerKey {
                move(by: flags.contains(.maskShift) ? -1 : 1)
                return true
            }
            switch keyCode {
            case KeyCode.right: move(by: panel.horizontalStep)
            case KeyCode.left: move(by: -panel.horizontalStep)
            case KeyCode.down: move(by: panel.verticalStep)
            case KeyCode.up: move(by: -panel.verticalStep)
            case KeyCode.returnKey: commit()
            case KeyCode.escape:
                StatsStore.shared.record("cancel")
                close()
            case KeyCode.w: perform(.close)
            case KeyCode.m: perform(.minimize)
            case KeyCode.f: perform(.fullscreen)
            case KeyCode.q: perform(.quit)
            case KeyCode.h: perform(.hide)
            case KeyCode.t: perform(.pin)
            default: break
            }
            return true // swallow every key while the switcher is open

        case .keyUp:
            return active

        case .flagsChanged:
            if active, !flags.contains(holdFlag) { commit() }
            return false

        default:
            return false
        }
    }

    private func begin(hold: CGEventFlags, key: Int, scope: Scope, backward: Bool) -> Bool {
        windows = WindowManager.listWindows(scope: scope)
        guard !windows.isEmpty else { return false }

        active = true
        sessionFrom = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        sessionMoves = 1
        StatsStore.shared.record("open", other: scope == .all ? "all" : "app", value: Double(windows.count))
        holdFlag = hold
        triggerKey = key
        self.scope = scope
        // Index 0 is the window already in front, so start on the previous one.
        selected = backward ? windows.count - 1 : min(1, windows.count - 1)
        show(animated: true)
        return true
    }

    private func show(animated: Bool) {
        panel.present(windows: windows, selected: selected,
                      pinned: PinManager.shared.pinnedIDs, animated: animated)
        let ids = windows.filter { !$0.isWindowless }.map { $0.id }
        Thumbnailer.shared.prune(keeping: ids)
        Thumbnailer.shared.refresh(ids) { [weak self] id, image in
            self?.panel.updateThumbnail(id, image)
        }
    }

    private func move(by delta: Int) {
        guard !windows.isEmpty else { return }
        let count = windows.count
        selected = ((selected + delta) % count + count) % count
        sessionMoves += 1
        panel.select(selected, animated: true)
    }

    private func perform(_ action: WindowAction) {
        guard windows.indices.contains(selected) else { return }
        let window = windows[selected]
        if window.isWindowless, action != .quit, action != .hide { return }
        WindowManager.perform(action, on: window)
        StatsStore.shared.record("action", app: window.app.bundleIdentifier, other: "\(action)")

        // Give the app a moment to close or change the window, then redraw the list.
        DispatchQueue.main.asyncAfter(deadline: .now() + (action == .pin ? 0.05 : 0.35)) { [weak self] in
            guard let self, self.active else { return }
            self.windows = WindowManager.listWindows(scope: self.scope)
            if self.windows.isEmpty {
                self.close()
                return
            }
            self.selected = min(self.selected, self.windows.count - 1)
            self.show(animated: false)
        }
    }

    private func commit() {
        guard active else { return }
        let target = windows.indices.contains(selected) ? windows[selected] : nil
        close()
        if let target {
            StatsStore.shared.record("switch", app: target.app.bundleIdentifier, other: sessionFrom,
                                     value: Double(sessionMoves))
            WindowManager.focus(target)
        }
    }

    private func close() {
        active = false
        panel.dismiss()
        windows = []
    }

    /// Debug helper: shows the panel with stand-in tiles and saves it as a PNG.
    func snapshot(to path: String) -> Bool {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.prefix(7)
        var demo: [WindowInfo] = []
        for (index, app) in apps.enumerated() {
            var info = WindowInfo(id: CGWindowID(9000 + index), element: nil, app: app,
                                  title: "\(app.localizedName ?? "App") window")
            info.badge = index == 1 ? "3" : (index == 4 ? "12" : nil)
            info.minimized = index == 2
            info.fullscreen = index == 3
            info.spaceIndex = index % 3 + 1
            demo.append(info)
        }
        guard !demo.isEmpty else { return false }
        panel.present(windows: demo, selected: min(1, demo.count - 1), pinned: [9004], animated: false)
        return panel.writeSnapshot(to: path)
    }
}
