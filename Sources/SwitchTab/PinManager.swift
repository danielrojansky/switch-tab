import AppKit
import ScreenCaptureKit

// Always on top.
//
// macOS does not let one app change the stacking level of another app's window.
// Instead, a pinned window gets a floating, always-on-top live mirror placed exactly
// over it. While the real window has focus the mirror hides, so you work in the real
// window. When something else comes to the front, the mirror appears and keeps the
// window visible above everything. Clicking the mirror brings the real window back.

private final class PinOverlayView: NSView {
    let imageLayer = CALayer()
    var onClick: ((NSPoint) -> Void)?
    var onUnpin: (() -> Void)?
    private var unpinButton: ActionButton!

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        guard let layer else { return }
        layer.cornerRadius = 10
        layer.masksToBounds = true
        layer.borderWidth = 2
        layer.borderColor = NSColor.controlAccentColor.cgColor
        layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageLayer.contentsGravity = .resize
        imageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        imageLayer.frame = bounds
        layer.addSublayer(imageLayer)

        unpinButton = ActionButton(symbolName: "pin.slash.circle.fill", color: .systemBlue,
                                   tooltip: "Stop keeping this window on top") { [weak self] in
            self?.onUnpin?()
        }
        addSubview(unpinButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        unpinButton.frame = NSRect(x: bounds.width - 26, y: bounds.height - 26, width: 20, height: 20)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        onClick?(NSEvent.mouseLocation)
    }
}

final class PinnedWindow: NSObject, SCStreamOutput, SCStreamDelegate {
    let info: WindowInfo
    private let panel: NSPanel
    private let view = PinOverlayView(frame: .zero)
    private let queue = DispatchQueue(label: "switchtab.pin", qos: .userInteractive)
    private var stream: SCStream?
    private var streamSize = CGSize.zero
    private var hasFrame = false
    var suppressedUntil = Date.distantPast
    var onStopped: (() -> Void)?

    init(info: WindowInfo) {
        self.info = info
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = view

        view.onUnpin = { PinManager.shared.unpin(info.id) }
        view.onClick = { [weak self] point in self?.activate(clickAt: point) }
    }

    private func configuration(for size: CGSize) -> SCStreamConfiguration {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let config = SCStreamConfiguration()
        config.width = max(2, Int(size.width * scale))
        config.height = max(2, Int(size.height * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 3
        return config
    }

    func start() {
        let id = info.id
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let window = content.windows.first(where: { $0.windowID == id }) else {
                    await MainActor.run { self.onStopped?() }
                    return
                }
                let size = window.frame.size
                let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window),
                                      configuration: configuration(for: size), delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                try await stream.startCapture()
                await MainActor.run {
                    self.stream = stream
                    self.streamSize = size
                }
            } catch {
                await MainActor.run { self.onStopped?() }
            }
        }
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
        panel.orderOut(nil)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.view.imageLayer.contents = surface
            CATransaction.commit()
            self.hasFrame = true
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onStopped?() }
    }

    /// Called a few times per second: keeps the mirror glued to the real window.
    func sync(frame: NSRect, visible: Bool) {
        if abs(frame.width - streamSize.width) > 1 || abs(frame.height - streamSize.height) > 1, let stream {
            streamSize = frame.size
            stream.updateConfiguration(configuration(for: frame.size)) { _ in }
        }
        if visible, hasFrame, Date() > suppressedUntil {
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    /// Brings the real window forward and passes the click on to it.
    private func activate(clickAt point: NSPoint) {
        suppressedUntil = Date().addingTimeInterval(0.6)
        panel.orderOut(nil)
        WindowManager.focus(info)

        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let location = CGPoint(x: point.x, y: mainHeight - point.y)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left)?
                    .post(tap: .cghidEventTap)
            }
        }
    }
}

final class PinManager {
    static let shared = PinManager()

    private var pins: [CGWindowID: PinnedWindow] = [:]
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    var pinnedIDs: Set<CGWindowID> { Set(pins.keys) }
    var pinned: [WindowInfo] { pins.values.map { $0.info }.sorted { $0.title < $1.title } }

    func isPinned(_ id: CGWindowID) -> Bool { pins[id] != nil }

    func toggleFocused() {
        guard let window = WindowManager.focusedWindow() else {
            NSSound.beep()
            return
        }
        toggle(window)
    }

    func toggle(_ window: WindowInfo) {
        if isPinned(window.id) { unpin(window.id) } else { pin(window) }
    }

    func pin(_ window: WindowInfo) {
        guard window.element != nil, !isPinned(window.id) else { return }
        guard CGPreflightScreenCaptureAccess() else {
            // The live mirror needs Screen Recording permission.
            CGRequestScreenCaptureAccess()
            NSSound.beep()
            return
        }
        let pin = PinnedWindow(info: window)
        pin.onStopped = { [weak self] in self?.unpin(window.id) }
        pins[window.id] = pin
        pin.start()
        startWatching()
    }

    func unpin(_ id: CGWindowID) {
        pins.removeValue(forKey: id)?.stop()
        if pins.isEmpty { stopWatching() }
    }

    func unpinAll() {
        pins.keys.forEach(unpin)
    }

    private func startWatching() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private func tick() {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let focusedID = WindowManager.focusedWindowID()

        for (id, pin) in pins {
            guard let element = pin.info.element, !pin.info.app.isTerminated,
                  let frame = WindowManager.frame(of: element) else {
                unpin(id) // window or app is gone
                continue
            }
            let minimized: Bool = WindowManager.attribute(element, kAXMinimizedAttribute) ?? false
            let hasFocus = frontPID == pin.info.app.processIdentifier && focusedID == id
            pin.sync(frame: frame, visible: !hasFocus && !minimized && !pin.info.app.isHidden)
        }
    }
}
