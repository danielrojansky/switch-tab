import AppKit

/// Owns the global keyboard tap and the switching session:
/// hold the modifier, press the trigger key to cycle, release the modifier to focus.
final class Switcher {
    static let shared = Switcher()

    private let panel = SwitcherPanel()
    private var tap: CFMachPort?
    private var windows: [WindowInfo] = []
    /// Every window of the session; `windows` is this list narrowed by the search text.
    private var allWindows: [WindowInfo] = []
    /// Search mode: typing filters the list and the switcher stays open after the modifier is released.
    private var searching = false
    private var query = ""
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
            if searching {
                handleSearchKey(keyCode, event: event)
                return true
            }
            if let digit = KeyCode.digits.firstIndex(of: keyCode) {
                if digit < windows.count, digit != selected {
                    selected = digit
                    sessionMoves += 1
                    panel.select(selected, animated: true)
                }
                return true
            }
            switch keyCode {
            case KeyCode.s, KeyCode.slash:
                searching = true
                query = ""
                show(animated: false)
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
            if active, !searching, !flags.contains(holdFlag) { commit() }
            return false

        default:
            return false
        }
    }

    /// Keys while search mode is on: text edits the query, the rest navigates.
    private func handleSearchKey(_ keyCode: Int, event: CGEvent) {
        switch keyCode {
        case KeyCode.right: move(by: panel.horizontalStep)
        case KeyCode.left: move(by: -panel.horizontalStep)
        case KeyCode.down: move(by: panel.verticalStep)
        case KeyCode.up: move(by: -panel.verticalStep)
        case KeyCode.returnKey: commit()
        case KeyCode.escape:
            // First Esc clears the text, the next one closes the switcher.
            if query.isEmpty {
                StatsStore.shared.record("cancel")
                close()
            } else {
                query = ""
                applyFilter()
            }
        case KeyCode.delete:
            guard !query.isEmpty else { return }
            query.removeLast()
            applyFilter()
        default:
            let text = typedText(event)
            guard !text.isEmpty else { return }
            query += text
            applyFilter()
        }
    }

    /// The character a key produces in the current keyboard layout, ignoring the held modifier.
    private func typedText(_ event: CGEvent) -> String {
        guard let copy = event.copy() else { return "" }
        copy.flags = event.flags.intersection(.maskShift)
        var length = 0
        var units = [UniChar](repeating: 0, count: 4)
        copy.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &units)
        let text = String(utf16CodeUnits: units, count: length)
        let printable = text.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
        }
        return printable ? text : ""
    }

    /// Narrows the list to windows whose title or app name contains the search text.
    private func applyFilter() {
        if query.isEmpty {
            windows = allWindows
        } else {
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            windows = allWindows.filter {
                $0.title.range(of: query, options: options) != nil
                    || $0.appName.range(of: query, options: options) != nil
            }
        }
        selected = 0
        show(animated: false)
    }

    private func begin(hold: CGEventFlags, key: Int, scope: Scope, backward: Bool) -> Bool {
        allWindows = WindowManager.listWindows(scope: scope)
        windows = allWindows
        searching = false
        query = ""
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
                      pinned: PinManager.shared.pinnedIDs, animated: animated,
                      search: searching ? query : nil)
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
        if action == .close || action == .quit { panel.animateRemoval(at: selected) }
        StatsStore.shared.record("action", app: window.app.bundleIdentifier, other: "\(action)")

        // Give the app a moment to close or change the window, then redraw the list.
        DispatchQueue.main.asyncAfter(deadline: .now() + (action == .pin ? 0.05 : 0.35)) { [weak self] in
            guard let self, self.active else { return }
            self.allWindows = WindowManager.listWindows(scope: self.scope)
            if self.allWindows.isEmpty {
                self.close()
                return
            }
            let previous = self.selected
            self.applyFilter()
            self.selected = max(0, min(previous, self.windows.count - 1))
            self.panel.select(self.selected, animated: false)
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
        searching = false
        query = ""
        panel.dismiss()
        windows = []
        allWindows = []
    }

    /// Debug helper: shows the panel with stand-in tiles and saves it as a PNG.
    func snapshot(to path: String) -> Bool {
        let demo = Switcher.demoWindows(count: 7)
        guard !demo.isEmpty else { return false }
        // SWITCHTAB_DEMO_SEARCH=<text> renders search mode; a text that matches nothing shows the empty state.
        let search = ProcessInfo.processInfo.environment["SWITCHTAB_DEMO_SEARCH"]
        let shown = search.map { text in
            text.isEmpty ? demo : demo.filter { $0.title.range(of: text, options: .caseInsensitive) != nil }
        } ?? demo
        panel.present(windows: shown, selected: search == nil ? min(1, shown.count - 1) : 0,
                      pinned: [9004], animated: false, search: search)
        return panel.writeSnapshot(to: path)
    }

    /// Panel used only to draw the preview in Preferences; it never goes on screen.
    private static let previewPanel = SwitcherPanel()

    /// The switcher drawn with stand-in tiles and the current appearance settings.
    static func previewImage() -> NSImage? {
        let demo = demoWindows(count: 4)
        guard !demo.isEmpty else { return nil }
        previewPanel.present(windows: demo, selected: min(1, demo.count - 1), pinned: [9002],
                             animated: false, onScreen: false)
        guard let rep = previewPanel.renderBitmap() else { return nil }
        let image = NSImage(size: previewPanel.frame.size)
        image.addRepresentation(rep)
        return image
    }

    static func demoWindows(count: Int) -> [WindowInfo] {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.prefix(count)
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
        return demo
    }
}
