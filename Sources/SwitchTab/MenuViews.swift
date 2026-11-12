import AppKit
import SwiftUI

/// Custom rows for the menu bar menu, plus the `--snapshot-ui` debug renders.
enum MenuViews {
    static let width: CGFloat = 280

    /// App icon, name, and a status line with a green or orange dot.
    static func header(ready: Bool) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 52))

        let icon = NSImageView(frame: NSRect(x: 14, y: 9, width: 34, height: 34))
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(icon)

        let title = NSTextField(labelWithString: "Switch Tab")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 58, y: 27, width: width - 72, height: 17)
        view.addSubview(title)

        let dot = NSView(frame: NSRect(x: 59, y: 13, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = (ready ? NSColor.systemGreen : NSColor.systemOrange).cgColor
        view.addSubview(dot)

        let status = NSTextField(labelWithString: (ready ? "Ready" : "Needs permission") + ", version \(appVersion)")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 72, y: 9, width: width - 86, height: 15)
        view.addSubview(status)
        return view
    }

    /// Switcher style as a segmented control, so changing it takes one click.
    static func styleRow(selected: Int, target: AnyObject, action: Selector) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 36))
        let control = NSSegmentedControl(labels: SwitcherStyle.allCases.map { $0.name },
                                         trackingMode: .selectOne, target: target, action: action)
        control.segmentDistribution = .fillEqually
        control.selectedSegment = selected
        control.frame = NSRect(x: 14, y: 6, width: width - 28, height: 24)
        view.addSubview(control)
        return view
    }

    // MARK: Debug renders

    private static func write(_ view: NSView, size: NSSize, to path: String) -> Bool {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// Writes each Preferences tab and the custom menu rows as PNG files into a folder.
    static func writeUISnapshots(to folder: String, target: AnyObject) -> Bool {
        var ok = true
        for (index, name) in ["general", "appearance", "shortcuts", "exclusions"].enumerated() {
            Settings.shared.prefsTab = index
            let host = NSHostingView(rootView: PreferencesView())
            ok = write(host, size: PreferencesView.size, to: "\(folder)/prefs-\(name).png") && ok
        }
        let menu = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 88))
        let top = header(ready: true)
        top.frame.origin.y = 36
        menu.addSubview(top)
        menu.addSubview(styleRow(selected: Settings.shared.style, target: target, action: #selector(NSResponder.cancelOperation(_:))))
        ok = write(menu, size: menu.frame.size, to: "\(folder)/menu-rows.png") && ok
        return ok
    }
}
