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
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail

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
            (pinned ? "pin.slash.circle.fill" : "pin.circle.fill", .systemBlue, pinned ? "Unpin (T)" : "Keep on top (T)", .pin),
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

    func setSelected(_ value: Bool, animated: Bool) {
        guard value != selected, let layer else { return }
        selected = value
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
        buttons.isHidden = false
        if style == .titles { badges.isHidden = true }
        onMove?()
    }

    override func mouseExited(with event: NSEvent) {
        buttons.isHidden = true
        badges.isHidden = false
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

    func present(windows: [WindowInfo], selected: Int, pinned: Set<CGWindowID>, animated: Bool) {
        generation += 1
        let settings = Settings.shared
        let style = settings.switcherStyle
        let animate = animated && settings.animations

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

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        let footerHeight: CGFloat = style == .icons ? 30 : 0
        let layout = grid(count: windows.count, style: style, visible: visible, footerHeight: footerHeight)
        let cell = layout.cell
        let columns = layout.columns, rows = layout.rows
        horizontalStep = style == .titles ? rows : 1
        verticalStep = style == .titles ? 1 : columns

        let width = padding * 2 + CGFloat(columns) * cell.width + CGFloat(columns - 1) * spacing
        let height = padding * 2 + footerHeight + CGFloat(rows) * cell.height + CGFloat(rows - 1) * spacing
        setFrame(NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height),
                 display: false)
        effect.frame = root.bounds

        root.addSubview(highlight)
        if footerHeight > 0 {
            footer.frame = NSRect(x: padding, y: padding - 4, width: width - padding * 2, height: 22)
            root.addSubview(footer)
        }

        let stagger = min(0.018, 0.22 / Double(max(1, windows.count)))
        for (index, window) in windows.enumerated() {
            let view = WindowCell(info: window, style: style, size: cell,
                                  thumbnail: Thumbnailer.shared.cache[window.id],
                                  pinned: pinned.contains(window.id))
            let column = style == .titles ? index / rows : index % columns
            let row = style == .titles ? index % rows : index / columns
            view.frame.origin = NSPoint(
                x: padding + CGFloat(column) * (cell.width + spacing),
                y: height - padding - cell.height - CGFloat(row) * (cell.height + spacing))
            view.onMove = { [weak self] in self?.onHover?(index) }
            view.onClick = { [weak self] in self?.onClick?(index) }
            view.onAction = { [weak self] action in self?.onAction?(index, action) }
            root.addSubview(view)
            cells.append(view)
            if animate { view.animateEntrance(delay: Double(index) * stagger) }
        }

        select(selected, animated: false)

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

    /// Renders the panel content to a PNG file. Used by the `--snapshot` debug mode.
    func writeSnapshot(to path: String) -> Bool {
        guard let view = contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
