import AppKit
import ApplicationServices

struct WindowInfo {
    let id: CGWindowID
    let element: AXUIElement?
    let app: NSRunningApplication
    let title: String
    var minimized = false
    var fullscreen = false
    var spaceIndex: Int?
    var onCurrentSpace = true
    /// An app with no open window, shown as a single tile.
    var isWindowless = false

    var appName: String { app.localizedName ?? "App" }
    var hidden: Bool { app.isHidden }
}

enum WindowAction {
    case close, minimize, fullscreen, quit, hide, pin
}

enum Scope {
    case all, activeApp
}

/// Mission Control Spaces, read through the window server.
enum Spaces {
    private(set) static var indexByID: [UInt64: Int] = [:]
    private(set) static var current: Set<UInt64> = []

    static func refresh() {
        indexByID = [:]
        current = []
        guard let displays = cgsCopyManagedDisplaySpaces(cgsMainConnection())?.takeRetainedValue() as? [[String: Any]] else { return }
        var index = 1
        for display in displays {
            if let active = display["Current Space"] as? [String: Any],
               let id = (active["id64"] as? NSNumber)?.uint64Value {
                current.insert(id)
            }
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = (space["id64"] as? NSNumber)?.uint64Value else { continue }
                // type 0 is a normal desktop; full-screen apps get their own unnumbered space
                if (space["type"] as? NSNumber)?.intValue == 0 {
                    indexByID[id] = index
                    index += 1
                }
            }
        }
    }

    static func spaces(of window: CGWindowID) -> [UInt64] {
        let ids = [NSNumber(value: window)] as CFArray
        guard let result = cgsCopySpacesForWindows(cgsMainConnection(), 7, ids)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return result.map { $0.uint64Value }
    }
}

/// The Accessibility API only lists windows on the current Space. Windows elsewhere are
/// found by probing each app's accessibility element IDs in the background.
enum RemoteWindowScanner {
    private static var cache: [pid_t: [AXUIElement]] = [:]
    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "switchtab.scanner", qos: .utility)
    private static var scanning = false

    static func cached(_ pid: pid_t) -> [AXUIElement] {
        lock.lock(); defer { lock.unlock() }
        return cache[pid] ?? []
    }

    static func scanAll() {
        guard AXIsProcessTrusted() else { return }
        lock.lock()
        if scanning { lock.unlock(); return }
        scanning = true
        lock.unlock()

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID }
            .map { $0.processIdentifier }

        queue.async {
            // Only apps that own windows which are not on screen right now need probing.
            let offscreen = pidsWithOffscreenWindows()
            var found: [pid_t: [AXUIElement]] = [:]
            for pid in pids where offscreen.contains(pid) {
                found[pid] = scan(pid)
            }
            lock.lock()
            cache = found
            scanning = false
            lock.unlock()
        }
    }

    private static func pidsWithOffscreenWindows() -> Set<pid_t> {
        func windows(_ options: CGWindowListOption) -> [(CGWindowID, pid_t)] {
            let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            return list.compactMap { entry in
                guard (entry[kCGWindowLayer as String] as? Int) == 0,
                      let id = entry[kCGWindowNumber as String] as? Int,
                      let pid = entry[kCGWindowOwnerPID as String] as? Int else { return nil }
                return (CGWindowID(id), pid_t(pid))
            }
        }
        let onScreen = Set(windows([.optionOnScreenOnly, .excludeDesktopElements]).map { $0.0 })
        return Set(windows([.excludeDesktopElements]).filter { !onScreen.contains($0.0) }.map { $0.1 })
    }

    private static func scan(_ pid: pid_t) -> [AXUIElement] {
        var result: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(0.15)
        for elementID: UInt64 in 0..<1000 {
            if Date() > deadline { break }
            var token = Data(count: 20)
            token.withUnsafeMutableBytes { raw in
                raw.storeBytes(of: pid, toByteOffset: 0, as: Int32.self)
                raw.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
                raw.storeBytes(of: Int32(0x636f_636f), toByteOffset: 8, as: Int32.self)
                withUnsafeBytes(of: elementID) { raw.baseAddress!.advanced(by: 12).copyMemory(from: $0.baseAddress!, byteCount: 8) }
            }
            guard let element = axCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            var subrole: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
                  let name = subrole as? String,
                  name == kAXStandardWindowSubrole || name == kAXDialogSubrole else { continue }
            result.append(element)
        }
        return result
    }
}

/// Remembers the order in which windows were last focused.
enum FocusTracker {
    private static var history: [CGWindowID] = []

    static func note(_ id: CGWindowID) {
        guard id != 0, history.first != id else { return }
        history.removeAll { $0 == id }
        history.insert(id, at: 0)
        if history.count > 300 { history.removeLast() }
    }

    static func poll() {
        if let id = WindowManager.focusedWindowID() { note(id) }
    }

    static func rank(_ id: CGWindowID) -> Int? {
        history.firstIndex(of: id)
    }
}

enum WindowManager {
    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func windowID(_ element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard axGetWindowID(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    private static func focusedElement() -> (NSRunningApplication, AXUIElement)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (app, value as! AXUIElement)
    }

    static func focusedWindowID() -> CGWindowID? {
        focusedElement().flatMap { windowID($0.1) }
    }

    static func focusedWindow() -> WindowInfo? {
        guard let (app, element) = focusedElement(), let id = windowID(element) else { return nil }
        let title: String = attribute(element, kAXTitleAttribute) ?? ""
        return WindowInfo(id: id, element: element, app: app, title: title.isEmpty ? (app.localizedName ?? "Window") : title)
    }

    /// Window frame in AppKit screen coordinates (origin bottom-left of the main display).
    static func frame(of element: AXUIElement) -> NSRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: position.x, y: mainHeight - position.y - size.height, width: size.width, height: size.height)
    }

    static func listWindows(scope: Scope) -> [WindowInfo] {
        let settings = Settings.shared
        Spaces.refresh()
        FocusTracker.poll()

        // Front-to-back order of on-screen windows, used when focus history has no entry.
        var zOrder: [CGWindowID: Int] = [:]
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for (index, entry) in list.enumerated() {
                if let number = entry[kCGWindowNumber as String] as? Int {
                    zOrder[CGWindowID(number)] = index
                }
            }
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var result: [WindowInfo] = []
        var windowless: [WindowInfo] = []

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            if let bundleID = app.bundleIdentifier, settings.blacklist.contains(bundleID) { continue }
            if scope == .activeApp, app.processIdentifier != frontPID { continue }
            if app.isHidden, !settings.showHidden { continue }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25) // do not hang on an unresponsive app
            var elements: [AXUIElement] = attribute(axApp, kAXWindowsAttribute) ?? []
            elements += RemoteWindowScanner.cached(app.processIdentifier)

            var seen = Set<CGWindowID>()
            for element in elements {
                let subrole: String = attribute(element, kAXSubroleAttribute) ?? ""
                guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole,
                      let id = windowID(element), seen.insert(id).inserted else { continue }

                let rawTitle: String = attribute(element, kAXTitleAttribute) ?? ""
                var info = WindowInfo(id: id, element: element, app: app,
                                      title: rawTitle.isEmpty ? (app.localizedName ?? "Window") : rawTitle)
                info.minimized = attribute(element, kAXMinimizedAttribute) ?? false
                info.fullscreen = attribute(element, "AXFullScreen") ?? false

                let spaces = Spaces.spaces(of: id)
                info.onCurrentSpace = spaces.isEmpty || !Spaces.current.isDisjoint(with: spaces)
                info.spaceIndex = spaces.compactMap { Spaces.indexByID[$0] }.first

                if info.minimized, !settings.showMinimized { continue }
                if info.fullscreen, !settings.showFullscreen { continue }
                if !info.onCurrentSpace, !info.minimized, !settings.allSpaces { continue }
                result.append(info)
            }

            if seen.isEmpty, settings.showWindowless, scope == .all {
                var info = WindowInfo(id: 0, element: nil, app: app, title: app.localizedName ?? "App")
                info.isWindowless = true
                windowless.append(info)
            }
        }

        if settings.sortOrder == 1 {
            result.sort {
                let byApp = $0.appName.localizedCaseInsensitiveCompare($1.appName)
                return byApp == .orderedSame
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : byApp == .orderedAscending
            }
        } else {
            func rank(_ info: WindowInfo) -> Int {
                if let recent = FocusTracker.rank(info.id) { return recent }
                return 10_000 + (zOrder[info.id] ?? 50_000)
            }
            result = result.enumerated().sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                return ra == rb ? a.offset < b.offset : ra < rb
            }.map { $0.element }
        }
        return result + windowless
    }

    static func focus(_ window: WindowInfo) {
        guard let element = window.element else {
            // Windowless app: reopening it asks the app to show a window.
            if let url = window.app.bundleURL {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else {
                window.app.activate()
            }
            return
        }

        if window.minimized {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if window.app.isHidden {
            window.app.unhide()
        }

        var psn = ProcessSerialNumber()
        var broughtToFront = false
        if processSerialNumber(forPID: window.app.processIdentifier, &psn) == noErr {
            broughtToFront = setFrontProcess(&psn, window.id, frontProcessUserGenerated) == .success
            makeKeyWindow(&psn, window.id)
        }

        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)

        if !broughtToFront {
            window.app.activate()
        }
        FocusTracker.note(window.id)
    }

    /// Tells the window server which window of the app receives keyboard input.
    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { source in
            for (offset, byte) in source.enumerated() { bytes[0x3c + offset] = byte }
        }
        for index in 0x20..<0x30 { bytes[index] = 0xff }
        bytes[0x08] = 0x01
        _ = postEventRecord(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = postEventRecord(&psn, &bytes)
    }

    static func perform(_ action: WindowAction, on window: WindowInfo) {
        switch action {
        case .quit:
            window.app.terminate()
        case .hide:
            if window.app.isHidden { window.app.unhide() } else { window.app.hide() }
        case .close:
            guard let element = window.element else { return }
            var button: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success,
               let button, CFGetTypeID(button) == AXUIElementGetTypeID() {
                AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            }
        case .minimize:
            guard let element = window.element else { return }
            let value: CFBoolean = window.minimized ? kCFBooleanFalse : kCFBooleanTrue
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, value)
        case .fullscreen:
            guard let element = window.element else { return }
            let value: CFBoolean = window.fullscreen ? kCFBooleanFalse : kCFBooleanTrue
            AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, value)
        case .pin:
            PinManager.shared.toggle(window)
        }
    }
}
