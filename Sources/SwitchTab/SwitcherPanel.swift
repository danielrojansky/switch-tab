import AppKit

/// One tile: window preview, app icon and title.
final class WindowCell: NSView {
    static let size = NSSize(width: 220, height: 172)

    let windowID: CGWindowID
    var onClick: (() -> Void)?

    private let preview = NSImageView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hasThumbnail = false

    var isSelected = false {
        didSet {
            layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
                : NSColor.clear.cgColor
            layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        }
    }

    init(window: WindowInfo, thumbnail: NSImage?) {
        windowID = window.id
        super.init(frame: NSRect(origin: .zero, size: WindowCell.size))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.clear.cgColor

        let appIcon = window.app.icon

        preview.frame = NSRect(x: 8, y: 36, width: 204, height: 128)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
        preview.layer?.masksToBounds = true
        preview.alphaValue = window.minimized ? 0.55 : 1
        addSubview(preview)

        icon.frame = NSRect(x: 8, y: 8, width: 22, height: 22)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = appIcon
        addSubview(icon)

        label.frame = NSRect(x: 36, y: 9, width: 176, height: 18)
        label.stringValue = window.title
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        if let thumbnail {
            setThumbnail(thumbnail)
        } else {
            preview.image = appIcon
            preview.imageScaling = .scaleProportionallyDown
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setThumbnail(_ image: NSImage) {
        hasThumbnail = true
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.image = image
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}

/// Floating overlay that never takes keyboard focus away from the current app.
final class SwitcherPanel: NSPanel {
    private let padding: CGFloat = 16
    private let spacing: CGFloat = 8
    private let effect = NSVisualEffectView()
    private var cells: [WindowCell] = []
    private(set) var columns = 1

    var onCellClicked: ((Int) -> Void)?

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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        contentView = effect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(windows: [WindowInfo], selected: Int) {
        cells.forEach { $0.removeFromSuperview() }
        cells = []

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        let cell = WindowCell.size
        let usableWidth = visible.width * 0.9 - padding * 2
        let maxColumns = max(1, Int((usableWidth + spacing) / (cell.width + spacing)))
        columns = min(windows.count, maxColumns)
        let rows = Int(ceil(Double(windows.count) / Double(columns)))

        let width = padding * 2 + CGFloat(columns) * cell.width + CGFloat(columns - 1) * spacing
        let height = padding * 2 + CGFloat(rows) * cell.height + CGFloat(rows - 1) * spacing

        let frame = NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
        setFrame(frame, display: false)

        for (index, window) in windows.enumerated() {
            let view = WindowCell(window: window, thumbnail: Thumbnailer.shared.cache[window.id])
            let column = index % columns
            let row = index / columns
            view.frame.origin = NSPoint(
                x: padding + CGFloat(column) * (cell.width + spacing),
                y: height - padding - cell.height - CGFloat(row) * (cell.height + spacing))
            view.onClick = { [weak self] in self?.onCellClicked?(index) }
            effect.addSubview(view)
            cells.append(view)
        }

        select(selected)
        orderFrontRegardless()
    }

    func select(_ index: Int) {
        for (i, cell) in cells.enumerated() {
            cell.isSelected = i == index
        }
    }

    func updateThumbnail(_ id: CGWindowID, _ image: NSImage) {
        guard isVisible else { return }
        cells.first { $0.windowID == id }?.setThumbnail(image)
    }
}
