import AppKit
import ApplicationServices
import Combine
import ServiceManagement
import SwiftUI

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    private var timers: [Timer] = []
    private var settingsObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Debug mode: render the switcher with stand-in tiles to a PNG, then exit.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--snapshot"), arguments.count > flag + 1 {
            let ok = Switcher.shared.snapshot(to: arguments[flag + 1])
            exit(ok ? 0 : 1)
        }
        if let flag = arguments.firstIndex(of: "--snapshot-menu-icon"), arguments.count > flag + 1 {
            exit(Icons.writeMenuBarPreview(to: arguments[flag + 1]) ? 0 : 1)
        }
        if let flag = arguments.firstIndex(of: "--snapshot-ui"), arguments.count > flag + 1 {
            exit(MenuViews.writeUISnapshots(to: arguments[flag + 1], target: self) ? 0 : 1)
        }
        if let flag = arguments.firstIndex(of: "--snapshot-preview"), arguments.count > flag + 1 {
            let data = Switcher.previewImage()?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?
                .representation(using: .png, properties: [:])
            let ok = (try? data?.write(to: URL(fileURLWithPath: arguments[flag + 1]))) != nil && data != nil
            exit(ok ? 0 : 1)
        }

        if arguments.contains("--stats-selftest") {
            UserDefaults.standard.set(true, forKey: "statsEnabled")
            Settings.shared.statsEnabled = true
            exit(StatsStore.shared.selfTest() ? 0 : 1)
        }

        applySettings()
        settingsObserver = Settings.shared.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.applySettings() }
        }

        // Accessibility: required to read keys globally and to control windows.
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)

        // Screen Recording: window previews and always on top.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        if !Switcher.shared.startListening() {
            every(2) { timer in
                if AXIsProcessTrusted(), Switcher.shared.startListening() {
                    timer.invalidate()
                    RemoteWindowScanner.scanAll()
                }
            }
        }

        // Keep focus history and the list of windows on other Spaces fresh.
        every(0.4) { _ in if AXIsProcessTrusted() { FocusTracker.poll() } }
        every(5) { _ in RemoteWindowScanner.scanAll() }
        every(15) { _ in StatsStore.shared.tick(interval: 15) }
        RemoteWindowScanner.scanAll()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didLaunchApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in RemoteWindowScanner.scanAll() }
        }

        enableLoginItemOnFirstInstall()
    }

    private func every(_ interval: TimeInterval, _ block: @escaping (Timer) -> Void) {
        let timer = Timer(timeInterval: interval, repeats: true, block: block)
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    /// Reacts to preference changes: menu bar icon and native shortcut takeover.
    private func applySettings() {
        let settings = Settings.shared

        if settings.showMenuBarIcon, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = Icons.menuBar
            item.button?.toolTip = "Switch Tab"
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if !settings.showMenuBarIcon, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }

        // Using Command means the built-in macOS switcher has to step aside.
        let usesCommand: (Int) -> Bool = { key in
            (settings.holdModifier == 1 && settings.triggerKey == key)
                || (settings.appHoldModifier == 1 && settings.appTriggerKey == key)
        }
        NativeHotKey.set(commandTab: !usesCommand(KeyCode.tab), keyAboveTab: !usesCommand(KeyCode.backtick))
    }

    private func enableLoginItemOnFirstInstall() {
        let key = "didSetUpLoginItem"
        guard !UserDefaults.standard.bool(forKey: key),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NativeHotKey.restore()
        PinManager.shared.unpinAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferences()
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let settings = Settings.shared
        let accessibility = AXIsProcessTrusted() && Switcher.shared.isListening
        let recording = CGPreflightScreenCaptureAccess()

        let header = NSMenuItem()
        header.view = MenuViews.header(ready: accessibility)
        menu.addItem(header)

        // Permissions only take up space while one is missing.
        if !accessibility {
            menu.addItem(item("Grant Accessibility (required)…", #selector(openAccessibility),
                              symbol: "exclamationmark.triangle.fill"))
        }
        if !recording {
            menu.addItem(item("Grant Screen Recording (previews, always on top)…", #selector(openScreenRecording),
                              symbol: "exclamationmark.triangle.fill"))
        }
        menu.addItem(.separator())

        // Style is one click: a segmented control right in the menu.
        let style = NSMenuItem()
        style.view = MenuViews.styleRow(selected: settings.style, target: self, action: #selector(styleSegmentChanged(_:)))
        menu.addItem(style)
        menu.addItem(item("Windows from All Spaces", #selector(toggleAllSpaces),
                          symbol: "rectangle.3.group", checked: settings.allSpaces))
        menu.addItem(item("Key Hints in Switcher", #selector(toggleHints),
                          symbol: "keyboard", checked: settings.showHints))
        menu.addItem(.separator())

        let pinned = PinManager.shared.pinned
        let pin = item("Keep Focused Window on Top", #selector(pinFocused), symbol: "pin")
        if settings.pinShortcutEnabled {
            pin.keyEquivalent = "t"
            pin.keyEquivalentModifierMask = [.control, .option]
        }
        menu.addItem(pin)
        for window in pinned {
            let name = window.title.isEmpty || window.title == window.appName
                ? window.appName : "\(window.appName): \(window.title)"
            let entry = item(name.count > 44 ? String(name.prefix(43)) + "…" : name, #selector(unpin(_:)), checked: true)
            if let icon = window.app.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                entry.image = icon
            }
            entry.indentationLevel = 1
            entry.toolTip = "Click to stop keeping this window on top"
            entry.tag = Int(window.id)
            menu.addItem(entry)
        }
        if pinned.count > 1 {
            menu.addItem(item("Unpin All", #selector(unpinAll), symbol: "pin.slash"))
        }
        menu.addItem(.separator())

        let preferences = item("Preferences…", #selector(showPreferences), symbol: "gearshape")
        preferences.keyEquivalent = ","
        menu.addItem(preferences)
        menu.addItem(NSMenuItem(title: "Quit Switch Tab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector?, symbol: String? = nil, checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    @objc private func styleSegmentChanged(_ sender: NSSegmentedControl) {
        Settings.shared.style = sender.selectedSegment
    }

    @objc private func toggleAllSpaces() {
        Settings.shared.allSpaces.toggle()
    }

    @objc private func toggleHints() {
        Settings.shared.showHints.toggle()
    }

    @objc private func pinFocused() {
        // The menu took focus for a moment; wait until the previous window has it back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { PinManager.shared.toggleFocused() }
    }

    @objc private func unpin(_ sender: NSMenuItem) {
        PinManager.shared.unpin(CGWindowID(sender.tag))
    }

    @objc private func unpinAll() {
        PinManager.shared.unpinAll()
    }

    @objc func showPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView()))
            window.title = "Switch Tab Preferences"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibility() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openScreenRecording() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }

    @objc private func toggleLoginItem() {
        Settings.shared.launchAtLogin.toggle()
    }
}

// If the app is stopped from outside, still hand the native shortcuts back to macOS.
for code in [SIGTERM, SIGINT, SIGHUP] {
    signal(code) { _ in
        NativeHotKey.restore()
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
