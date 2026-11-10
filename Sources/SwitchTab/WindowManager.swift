import AppKit
import ApplicationServices

struct WindowInfo {
    let id: CGWindowID
    let element: AXUIElement
    let app: NSRunningApplication
    let title: String
    let minimized: Bool
}

enum WindowManager {
    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    /// Windows of all regular apps, most recently used first, minimized and hidden ones last.
    static func listWindows() -> [WindowInfo] {
        // Front-to-back order of on-screen windows doubles as recency order.
        var order: [CGWindowID: Int] = [:]
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for (index, entry) in list.enumerated() {
                if let number = entry[kCGWindowNumber as String] as? Int {
                    order[CGWindowID(number)] = index
                }
            }
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var result: [WindowInfo] = []

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25) // do not hang on an unresponsive app
            guard let windows: [AXUIElement] = attribute(axApp, kAXWindowsAttribute) else { continue }

            for window in windows {
                let subrole: String = attribute(window, kAXSubroleAttribute) ?? ""
                guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }

                var id: CGWindowID = 0
                guard axGetWindowID(window, &id) == .success, id != 0 else { continue }

                let rawTitle: String = attribute(window, kAXTitleAttribute) ?? ""
                let minimized: Bool = attribute(window, kAXMinimizedAttribute) ?? false
                let title = rawTitle.isEmpty ? (app.localizedName ?? "Window") : rawTitle
                result.append(WindowInfo(id: id, element: window, app: app, title: title, minimized: minimized))
            }
        }

        return result.enumerated().sorted { a, b in
            let ia = order[a.element.id] ?? Int.max
            let ib = order[b.element.id] ?? Int.max
            return ia == ib ? a.offset < b.offset : ia < ib
        }.map { $0.element }
    }

    static func focus(_ window: WindowInfo) {
        if window.minimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if window.app.isHidden {
            window.app.unhide()
        }

        var psn = ProcessSerialNumber()
        var broughtToFront = false
        if processSerialNumber(forPID: window.app.processIdentifier, &psn) == noErr {
            broughtToFront = setFrontProcess(&psn, window.id, frontProcessUserGenerated) == .success
        }

        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)

        if !broughtToFront {
            window.app.activate()
        }
    }
}
