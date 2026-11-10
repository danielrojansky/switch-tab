import AppKit

private enum Key {
    static let tab: Int64 = 48
    static let escape: Int64 = 53
    static let returnKey: Int64 = 36
    static let left: Int64 = 123
    static let right: Int64 = 124
    static let down: Int64 = 125
    static let up: Int64 = 126
}

/// Owns the global keyboard tap and the switching session:
/// hold Option, press Tab to cycle, release Option to focus the selected window.
final class Switcher {
    static let shared = Switcher()

    private let panel = SwitcherPanel()
    private var tap: CFMachPort?
    private var windows: [WindowInfo] = []
    private var selected = 0
    private var active = false

    var isListening: Bool { tap != nil }

    private init() {
        panel.onCellClicked = { [weak self] index in
            guard let self, self.active else { return }
            self.selected = index
            self.commit()
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
        let optionDown = flags.contains(.maskAlternate)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .keyDown:
            if keyCode == Key.tab, optionDown,
               !flags.contains(.maskCommand), !flags.contains(.maskControl) {
                let backward = flags.contains(.maskShift)
                if active {
                    move(by: backward ? -1 : 1)
                    return true
                }
                return begin(backward: backward)
            }
            guard active else { return false }
            switch keyCode {
            case Key.right: move(by: 1)
            case Key.left: move(by: -1)
            case Key.down: move(by: panel.columns)
            case Key.up: move(by: -panel.columns)
            case Key.returnKey: commit()
            case Key.escape: cancel()
            default: break
            }
            return true // swallow every key while the switcher is open

        case .keyUp:
            return active

        case .flagsChanged:
            if active, !optionDown { commit() }
            return false

        default:
            return false
        }
    }

    private func begin(backward: Bool) -> Bool {
        windows = WindowManager.listWindows()
        guard !windows.isEmpty else { return false }

        active = true
        // Index 0 is the window already in front, so start on the previous one.
        selected = backward ? windows.count - 1 : min(1, windows.count - 1)
        panel.present(windows: windows, selected: selected)

        let ids = windows.map { $0.id }
        Thumbnailer.shared.prune(keeping: ids)
        Thumbnailer.shared.refresh(ids) { [weak self] id, image in
            self?.panel.updateThumbnail(id, image)
        }
        return true
    }

    private func move(by delta: Int) {
        guard !windows.isEmpty else { return }
        let count = windows.count
        selected = ((selected + delta) % count + count) % count
        panel.select(selected)
    }

    private func commit() {
        guard active else { return }
        let target = windows.indices.contains(selected) ? windows[selected] : nil
        close()
        if let target { WindowManager.focus(target) }
    }

    private func cancel() {
        close()
    }

    private func close() {
        active = false
        panel.orderOut(nil)
        windows = []
    }
}
