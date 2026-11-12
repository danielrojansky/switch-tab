import AppKit
import QuartzCore

private func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white, color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
}

final class ActionButton: NSButton {
    var handler: (() -> Void)?

    convenience init(symbolName: String, color: NSColor, tooltip: String, handler: @escaping () -> Void) {
        self.init(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        self.handler = handler
        image = symbol(symbolName, size: 15, color: color)
        imagePosition = .imageOnly
        isBordered = false
        toolTip = tooltip
        target = self
        action = #selector(fire)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func fire() { handler?() }
}

/// Glowing selection frame with a slowly rotating gradient border.
final class HighlightView: NSView {
    private let border = CALayer()
    private let gradient = CAGradientLayer()
    private let stroke = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        guard let layer else { return }
        let accent = NSColor.controlAccentColor
        layer.cornerRadius = 14
        layer.backgroundColor = accent.withAlphaComponent(0.24).cgColor
        layer.masksToBounds = false
        layer.shadowColor = accent.cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = 16
        layer.shadowOpacity = Settings.shared.glow ? 0.85 : 0

        if Settings.shared.glow {
            gradient.type = .conic
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 0.5, y: 0)
            gradient.colors = [accent, NSColor.systemPink, NSColor.systemPurple, NSColor.systemTeal, accent].map { $0.cgColor }
            border.addSublayer(gradient)
            stroke.fillColor = nil
            stroke.strokeColor = NSColor.white.cgColor
            stroke.lineWidth = 2.5
            border.mask = stroke
            layer.addSublayer(border)
        } else {
            layer.borderWidth = 2
            layer.borderColor = accent.cgColor
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        guard Settings.shared.glow else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        border.frame = bounds
        let side = hypot(bounds.width, bounds.height)
        gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        gradient.position = CGPoint(x: bounds.midX, y: bounds.midY)
        stroke.path = CGPath(roundedRect: bounds.insetBy(dx: 1.25, dy: 1.25), cornerWidth: 13, cornerHeight: 13, transform: nil)
        CATransaction.commit()

        if Settings.shared.animations, gradient.animation(forKey: "spin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = 4
            spin.repeatCount = .infinity
            gradient.add(spin, forKey: "spin")
        }
    }
}

/// One tile. Layout depends on the chosen style: thumbnail, app icon, or title row.
final class WindowCell: NSView {
    let info: WindowInfo
    var onMove: (() -> Void)?
    var onClick: (() -> Void)?
    var onAction: ((WindowAction) -> Void)?

    private let style: SwitcherStyle
    private let preview = NSImageView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let badges = NSView()
    private let buttons = NSView()
    private var selected = false
    private var hovered = false

    init(info: WindowInfo, style: SwitcherStyle, size: NSSize, thumbnail: NSImage?, pinned: Bool) {
        self.info = info
        self.style = style
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true

        let appIcon = info.app.icon
        let dimmed = info.minimized || info.hidden
        let fontSize: CGFloat = max(11, min(14, size.height / (style == .titles ? 2.6 : 12)))
        label.stringValue = info.title
        label.font = .systemFont(ofSize: fontSize, weight: .medium)
        label.textColor = dimmed ? .secondaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        toolTip = info.isWindowless || info.title == info.appName ? info.appName : "\(info.appName): \(info.title)"

        switch style {
        case .thumbnails:
            let footer: CGFloat = 34
            preview.frame = NSRect(x: 8, y: footer, width: size.width - 16, height: size.height - footer - 8)
            preview.wantsLayer = true
            preview.layer?.cornerRadius = 8
            preview.layer?.masksToBounds = true
            if let thumbnail, !info.isWindowless {
                preview.image = thumbnail
                preview.imageScaling = .scaleProportionallyUpOrDown
            } else {
                preview.image = appIcon
                preview.imageScaling = .scaleProportionallyUpOrDown
                preview.frame = preview.frame.insetBy(dx: preview.frame.width * 0.28, dy: preview.frame.height * 0.14)
            }
            preview.alphaValue = dimmed ? 0.5 : 1
            addSubview(preview)

            icon.frame = NSRect(x: 9, y: 7, width: 22, height: 22)
            icon.image = appIcon
            addSubview(icon)
            label.frame = NSRect(x: 37, y: 9, width: size.width - 46, height: fontSize + 6)
            addSubview(label)

        case .icons:
            let inset = size.width * 0.12
            preview.frame = bounds.insetBy(dx: inset, dy: inset)
            preview.image = appIcon
            preview.imageScaling = .scaleProportionallyUpOrDown
            preview.alphaValue = dimmed ? 0.5 : 1
            addSubview(preview)

        case .titles:
            let iconSize = size.height - 10
            icon.frame = NSRect(x: 8, y: 5, width: iconSize, height: iconSize)
            icon.image = appIcon
            icon.alphaValue = dimmed ? 0.5 : 1
            addSubview(icon)
            label.frame = NSRect(x: iconSize + 18, y: (size.height - fontSize - 6) / 2,
                                 width: size.width - iconSize - 28, height: fontSize + 6)
            addSubview(label)
        }

        buildBadges(pinned: pinned)
        buildButtons(pinned: pinned)
        buildDockBadge()
    }

    /// Red pill with the app's Dock badge, like the one on the Dock icon.
    private func buildDockBadge() {
        guard let text = info.badge, !text.isEmpty else { return }
        let shown = text.count > 4 ? String(text.prefix(3)) + "…" : text
        let label = NSTextField(labelWithString: shown)
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()
        let height: CGFloat = 20
        let width = max(height, label.frame.width + 12)

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.systemRed.cgColor
        pill.layer?.cornerRadius = height / 2
        pill.layer?.borderWidth = 1.5
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        pill.layer?.shadowColor = NSColor.black.cgColor
        pill.layer?.shadowOpacity = 0.35
        pill.layer?.shadowRadius = 3
        pill.layer?.shadowOffset = CGSize(width: 0, height: -1)
        switch style {
        case .thumbnails: pill.frame = NSRect(x: bounds.width - width - 12, y: bounds.height - height - 12, width: width, height: height)
        case .icons: pill.frame = NSRect(x: bounds.width - width - 6, y: bounds.height - height - 6, width: width, height: height)
        case .titles:
            // right side, left of the status badges if there are any
            let taken = badges.superview == nil ? 0 : badges.frame.width + 6
            pill.frame = NSRect(x: bounds.width - width - 8 - taken, y: (bounds.height - height) / 2, width: width, height: height)
            self.label.frame.size.width -= width + 6
        }
        label.frame = NSRect(x: 0, y: (height - label.frame.height) / 2, width: width, height: label.frame.height)
        pill.addSubview(label)
        addSubview(pill)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildBadges(pinned: Bool) {
        var items: [NSView] = []
        func add(_ name: String, _ color: NSColor) {
            let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
            view.image = symbol(name, size: 12, color: color)
            items.append(view)
        }
        if pinned { add("pin.circle.fill", .systemBlue) }
        if info.minimized { add("minus.circle.fill", .systemYellow) }
        if info.hidden { add("eye.slash.circle.fill", .systemGray) }
        if info.fullscreen { add("arrow.up.left.and.arrow.down.right.circle.fill", .systemGreen) }
        if let space = info.spaceIndex, !info.onCurrentSpace || Settings.shared.allSpaces, Spaces.indexByID.count > 1 {
            let text = NSTextField(labelWithString: "\(space)")
            text.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
            text.textColor = .white
            text.alignment = .center
            text.frame = NSRect(x: 0, y: 0, width: 16, height: 15)
            items.append(text)
        }
        guard !items.isEmpty else { return }

        let width = CGFloat(items.count) * 18 + 6
        badges.wantsLayer = true
        badges.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        badges.layer?.cornerRadius = 10
        switch style {
        case .thumbnails: badges.frame = NSRect(x: bounds.width - width - 12, y: 38, width: width, height: 20)
        case .icons: badges.frame = NSRect(x: bounds.width - width - 4, y: 4, width: width, height: 20)
        case .titles: badges.frame = NSRect(x: bounds.width - width - 8, y: (bounds.height - 20) / 2, width: width, height: 20)
        }
        for (index, item) in items.enumerated() {
            item.frame.origin = NSPoint(x: 4 + CGFloat(index) * 18, y: 2)
            badges.addSubview(item)
        }
        addSubview(badges)
        if style == .titles { label.frame.size.width -= width + 6 }
    }

    private func buildButtons(pinned: Bool) {
        guard style != .icons, !info.isWindowless else { return }
        let specs: [(String, NSColor, String, WindowAction)] = [
            ("xmark.circle.fill", .systemRed, "Close (W)", .close),
            ("minus.circle.fill", .systemYellow, "Minimize (M)", .minimize),
            ("arrow.up.left.and.arrow.down.right.circle.fill", .systemGreen, "Full screen (F)", .fullscreen),
            ("pin.circle.fill", pinned ? .systemGray : .systemBlue, pinned ? "Unpin (T)" : "Keep on top (T)", .pin),
        ]
        let width = CGFloat(specs.count) * 20 + 6
        buttons.wantsLayer = true
        buttons.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        buttons.layer?.cornerRadius = 11
        buttons.frame = style == .thumbnails
            ? NSRect(x: 12, y: bounds.height - 34, width: width, height: 22)
            : NSRect(x: bounds.width - width - 8, y: (bounds.height - 22) / 2, width: width, height: 22)
        for (index, spec) in specs.enumerated() {
            let button = ActionButton(symbolName: spec.0, color: spec.1, tooltip: spec.2) { [weak self] in
                self?.onAction?(spec.3)
            }
            button.frame.origin = NSPoint(x: 4 + CGFloat(index) * 20, y: 2)
            buttons.addSubview(button)
        }
        buttons.isHidden = true
        addSubview(buttons)
    }

    func setThumbnail(_ image: NSImage) {
        guard style == .thumbnails, !info.isWindowless else { return }
        if Settings.shared.animations, preview.image != nil {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.2
            preview.layer?.add(fade, forKey: "fade")
        }
        preview.frame = NSRect(x: 8, y: 34, width: bounds.width - 16, height: bounds.height - 42)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.image = image
    }

    // Tiles sit on a faint card that brightens under the pointer. Drawn in
    // updateLayer so the color follows the panel's light or dark appearance.
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        let base: CGFloat = style == .titles ? 0 : 0.05
        layer.cornerRadius = 12
        layer.backgroundColor = NSColor.labelColor.withAlphaComponent(hovered && !selected ? 0.13 : base).cgColor
    }

    /// Window buttons show under the pointer, and on the selected thumbnail so the actions are discoverable.
    private func updateChrome() {
        let show = hovered || (selected && style == .thumbnails)
        buttons.isHidden = !show
        if style == .titles { badges.isHidden = show && buttons.superview != nil }
        needsDisplay = true
    }

    func setSelected(_ value: Bool, animated: Bool) {
        guard value != selected, let layer else { return }
        selected = value
        updateChrome()
        label.font = .systemFont(ofSize: label.font?.pointSize ?? 12, weight: value ? .bold : .medium)
        guard style != .titles else { return }

        // Layer-backed views anchor at the origin, so scale around the center by hand.
        let scale: CGFloat = value ? 1.045 : 1
        let cx = bounds.width / 2, cy = bounds.height / 2
        var target = CATransform3DMakeTranslation(-cx, -cy, 0)
        target = CATransform3DConcat(target, CATransform3DMakeScale(scale, scale, 1))
        target = CATransform3DConcat(target, CATransform3DMakeTranslation(cx, cy, 0))

        if animated, Settings.shared.animations {
            let spring = CASpringAnimation(keyPath: "transform")
            spring.fromValue = layer.presentation()?.transform ?? layer.transform
            spring.toValue = target
            spring.damping = 13
            spring.stiffness = 260
            spring.duration = spring.settlingDuration
            layer.add(spring, forKey: "scale")
        }
        layer.transform = target
        layer.zPosition = value ? 1 : 0
    }

    func animateEntrance(delay: CFTimeInterval) {
        guard let layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let rise = CABasicAnimation(keyPath: "transform.translation.y")
        rise.fromValue = -14
        rise.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [fade, rise]
        group.duration = 0.22
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .backwards
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "entrance")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    // Selection follows the pointer only once it actually moves, so a panel that
    // opens under a resting pointer does not steal the selection.
    override func mouseMoved(with event: NSEvent) {
        if !hovered {
            hovered = true
            updateChrome()
        }
        onMove?()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateChrome()
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}

/// Floating overlay that never takes keyboard focus away from the current app.
final class SwitcherPanel: NSPanel {
    private let padding: CGFloat = 18
    private let spacing: CGFloat = 10
    private let root = NSView()
    private let effect = NSVisualEffectView()
    private let footer = NSTextField(labelWithString: "")
    private let hints = NSTextField(labelWithString: "")
    private let counter = NSTextField(labelWithString: "")
    private let searchIcon = NSImageView()
    private let searchField = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "No matching windows")
    private var highlight = HighlightView(frame: .zero)
    private var cells: [WindowCell] = []
    private var generation = 0

    /// How far the selection moves for left/right and up/down keys.
    private(set) var horizontalStep = 1
    private(set) var verticalStep = 1

    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?
    var onAction: ((Int, WindowAction) -> Void)?

    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        root.wantsLayer = true
        contentView = root

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 22
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        effect.autoresizingMask = [.width, .height]
        root.addSubview(effect)

        footer.font = .systemFont(ofSize: 14, weight: .semibold)
        footer.textColor = .labelColor
        footer.alignment = .center
        footer.lineBreakMode = .byTruncatingTail

        hints.alignment = .center
        counter.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        counter.textColor = .secondaryLabelColor
        counter.alignment = .right

        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        searchIcon.contentTintColor = .secondaryLabelColor
        searchField.font = .systemFont(ofSize: 15, weight: .medium)
        searchField.lineBreakMode = .byTruncatingHead
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
    }

    /// Key hints for the bottom bar: the longest set that fits the panel width.
    private func hintText(maxWidth: CGFloat, searching: Bool) -> NSAttributedString? {
        let all: [(String, String)] = [
            ("⇥", "Next"), ("⇧⇥", "Back"), ("↩", "Focus"), ("W", "Close"), ("M", "Minimize"),
            ("F", "Full screen"), ("T", "Pin"), ("Q", "Quit"), ("esc", "Cancel"),
            ("S", "Search"), ("1-9", "Jump"),
        ]
        let search: [(String, String)] = [
            ("⇥", "Next"), ("⇧⇥", "Back"), ("↩", "Focus"), ("⌫", "Delete"), ("esc", "Clear, then cancel"),
        ]
        let variants = searching
            ? [search, [search[2], search[4]], [search[2]]]
            : [[0, 1, 2, 9, 10, 3, 4, 5, 6, 7, 8].map { all[$0] }, [0, 2, 9, 10, 3, 4, 7, 8].map { all[$0] },
               [0, 2, 9, 3, 7, 8].map { all[$0] }, [9, 3, 4, 7].map { all[$0] }, [all[9], all[8]], [all[8]]]
        let keyFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let textFont = NSFont.systemFont(ofSize: 11)
        for variant in variants {
            let line = NSMutableAttributedString()
            for (index, hint) in variant.enumerated() {
                if index > 0 { line.append(NSAttributedString(string: "     ")) }
                line.append(NSAttributedString(string: hint.0, attributes: [
                    .font: keyFont, .foregroundColor: NSColor.labelColor]))
                line.append(NSAttributedString(string: " " + hint.1, attributes: [
                    .font: textFont, .foregroundColor: NSColor.secondaryLabelColor]))
            }
            guard line.size().width <= maxWidth else { continue }
            let centered = NSMutableParagraphStyle()
            centered.alignment = .center
            line.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: line.length))
            return line
        }
        return nil
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func grid(count: Int, style: SwitcherStyle, visible: NSRect, footerHeight: CGFloat)
        -> (cell: NSSize, columns: Int, rows: Int) {
        let size = min(2, max(0, Settings.shared.size))
        var cell: NSSize
        switch style {
        case .thumbnails:
            let width: CGFloat = [170, 230, 300][size]
            cell = NSSize(width: width, height: (width * 0.6 + 42).rounded())
        case .icons:
            let width: CGFloat = [88, 116, 150][size]
            cell = NSSize(width: width, height: width)
        case .titles:
            cell = NSSize(width: [340, 440, 540][size], height: [32, 38, 46][size])
        }

        let maxWidth = visible.width * 0.92 - padding * 2
        let maxHeight = visible.height * 0.88 - padding * 2 - footerHeight
        var columns = 1, rows = 1
        // Shrink tiles until everything fits on screen.
        for _ in 0..<14 {
            if style == .titles {
                rows = min(count, max(1, Int((maxHeight + spacing) / (cell.height + spacing))))
                columns = Int(ceil(Double(count) / Double(rows)))
                if CGFloat(columns) * (cell.width + spacing) - spacing <= maxWidth { break }
            } else {
                columns = min(count, max(1, Int((maxWidth + spacing) / (cell.width + spacing))))
                rows = Int(ceil(Double(count) / Double(columns)))
                if CGFloat(rows) * (cell.height + spacing) - spacing <= maxHeight { break }
            }
            cell = NSSize(width: (cell.width * 0.88).rounded(), height: (cell.height * 0.88).rounded())
        }
        return (cell, columns, rows)
    }

    /// `onScreen: false` lays the panel out without showing it, for previews and snapshots.
    func present(windows: [WindowInfo], selected: Int, pinned: Set<CGWindowID>, animated: Bool,
                 onScreen: Bool = true, search: String? = nil) {
        generation += 1
        let settings = Settings.shared
        let style = settings.switcherStyle
        let animate = animated && settings.animations && onScreen

        switch settings.theme {
        case 1: appearance = NSAppearance(named: .aqua)
        case 2: appearance = NSAppearance(named: .darkAqua)
        default: appearance = nil
        }

        cells.forEach { $0.removeFromSuperview() }
        cells = []
        highlight.removeFromSuperview()
        highlight = HighlightView(frame: .zero)
        footer.removeFromSuperview()
        hints.removeFromSuperview()
        counter.removeFromSuperview()
        searchIcon.removeFromSuperview()
        searchField.removeFromSuperview()
        emptyLabel.removeFromSuperview()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        let titleRow: CGFloat = style == .icons ? 30 : 0
        let hintRow: CGFloat = settings.showHints ? 24 : 0
        let footerHeight = titleRow + hintRow
        let searchRow: CGFloat = search == nil ? 0 : 34
        let layout = grid(count: max(1, windows.count), style: style, visible: visible,
                          footerHeight: footerHeight + searchRow)
        let cell = layout.cell
        let columns = layout.columns, rows = layout.rows
        horizontalStep = style == .titles ? rows : 1
        verticalStep = style == .titles ? 1 : columns

        // In search mode the panel keeps a minimum width so the text has room.
        let gridWidth = CGFloat(columns) * cell.width + CGFloat(columns - 1) * spacing
        let width = padding * 2 + (search == nil ? gridWidth : max(gridWidth, 420))
        let inset = (width - padding * 2 - gridWidth) / 2
        let height = padding * 2 + footerHeight + searchRow
            + CGFloat(rows) * cell.height + CGFloat(rows - 1) * spacing
        setFrame(NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height),
                 display: false)
        effect.frame = root.bounds

        if !windows.isEmpty { root.addSubview(highlight) }
        if let search {
            let top = height - padding - 24
            searchIcon.frame = NSRect(x: padding + 2, y: top + 2, width: 18, height: 18)
            searchField.frame = NSRect(x: padding + 28, y: top, width: width - padding * 2 - 28, height: 22)
            searchField.stringValue = search.isEmpty ? "Type to search windows" : search
            searchField.textColor = search.isEmpty ? .tertiaryLabelColor : .labelColor
            root.addSubview(searchIcon)
            root.addSubview(searchField)
        }
        if windows.isEmpty {
            emptyLabel.frame = NSRect(x: padding, y: padding + footerHeight + (cell.height - 20) / 2,
                                      width: width - padding * 2, height: 20)
            root.addSubview(emptyLabel)
            footer.stringValue = ""
            counter.stringValue = "0 / 0"
        }
        if titleRow > 0 {
            footer.frame = NSRect(x: padding, y: padding - 4 + hintRow, width: width - padding * 2, height: 22)
            root.addSubview(footer)
        }
        if hintRow > 0 {
            // The counter sits on the right; the hints stay centered between equal margins.
            let side: CGFloat = 54
            counter.frame = NSRect(x: width - padding - side, y: padding - 9, width: side, height: 16)
            root.addSubview(counter)
            if let text = hintText(maxWidth: width - padding * 2 - side * 2, searching: search != nil) {
                hints.attributedStringValue = text
                hints.frame = NSRect(x: padding + side, y: padding - 9, width: width - padding * 2 - side * 2, height: 16)
                root.addSubview(hints)
            }
        }

        let stagger = min(0.018, 0.22 / Double(max(1, windows.count)))
        for (index, window) in windows.enumerated() {
            let view = WindowCell(info: window, style: style, size: cell,
                                  thumbnail: Thumbnailer.shared.cache[window.id],
                                  pinned: pinned.contains(window.id))
            let column = style == .titles ? index / rows : index % columns
            let row = style == .titles ? index % rows : index / columns
            view.frame.origin = NSPoint(
                x: padding + inset + CGFloat(column) * (cell.width + spacing),
                y: height - padding - searchRow - cell.height - CGFloat(row) * (cell.height + spacing))
            view.onMove = { [weak self] in self?.onHover?(index) }
            view.onClick = { [weak self] in self?.onClick?(index) }
            view.onAction = { [weak self] action in self?.onAction?(index, action) }
            root.addSubview(view)
            cells.append(view)
            if animate { view.animateEntrance(delay: Double(index) * stagger) }
        }

        select(selected, animated: false)

        if !onScreen {
            alphaValue = 1
            root.layoutSubtreeIfNeeded()
            return
        }
        if animate {
            alphaValue = 0
            orderFrontRegardless()
            if let layer = root.layer {
                // scale around the panel center (the layer anchors at its origin)
                let cx = root.bounds.midX, cy = root.bounds.midY
                var start = CATransform3DMakeTranslation(-cx, -cy, 0)
                start = CATransform3DConcat(start, CATransform3DMakeScale(0.93, 0.93, 1))
                start = CATransform3DConcat(start, CATransform3DMakeTranslation(cx, cy, 0))
                let pop = CASpringAnimation(keyPath: "transform")
                pop.fromValue = start
                pop.toValue = CATransform3DIdentity
                pop.damping = 15
                pop.stiffness = 240
                pop.duration = pop.settlingDuration
                layer.add(pop, forKey: "pop")
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                animator().alphaValue = 1
            }
        } else {
            alphaValue = 1
            orderFrontRegardless()
        }
        invalidateShadow()
    }

    func select(_ index: Int, animated: Bool) {
        guard cells.indices.contains(index) else { return }
        let target = cells[index].frame.insetBy(dx: -3, dy: -3)
        if animated, Settings.shared.animations {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
                context.allowsImplicitAnimation = true
                highlight.animator().frame = target
            }
        } else {
            highlight.frame = target
        }
        for (i, cell) in cells.enumerated() {
            cell.setSelected(i == index, animated: animated)
        }
        counter.stringValue = "\(index + 1) / \(cells.count)"
        let info = cells[index].info
        footer.stringValue = info.isWindowless || info.title == info.appName
            ? info.appName
            : "\(info.appName): \(info.title)"
    }

    func updateThumbnail(_ id: CGWindowID, _ image: NSImage) {
        guard isVisible else { return }
        cells.first { $0.info.id == id }?.setThumbnail(image)
    }

    func dismiss() {
        generation += 1
        guard Settings.shared.animations, isVisible else {
            orderOut(nil)
            return
        }
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == current else { return }
            self.orderOut(nil)
        })
    }

    /// Renders the panel content to a bitmap. Used by the preferences preview and `--snapshot`.
    func renderBitmap() -> NSBitmapImageRep? {
        guard let view = contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// Renders the panel content to a PNG file. Used by the `--snapshot` debug mode.
    func writeSnapshot(to path: String) -> Bool {
        guard let data = renderBitmap()?.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
