import AppKit
import ScreenCaptureKit

/// Captures window previews. Needs the Screen Recording permission; without it the
/// switcher falls back to app icons.
final class Thumbnailer {
    static let shared = Thumbnailer()

    private(set) var cache: [CGWindowID: NSImage] = [:]
    private let maxPixelWidth: CGFloat = 640

    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Refreshes previews for the given windows. `onUpdate` runs on the main thread per window.
    func refresh(_ ids: [CGWindowID], onUpdate: @escaping (CGWindowID, NSImage) -> Void) {
        guard hasPermission, !ids.isEmpty else { return }
        let wanted = Set(ids)
        let maxWidth = maxPixelWidth

        Task.detached(priority: .userInitiated) {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else { return }

            await withTaskGroup(of: Void.self) { group in
                for window in content.windows where wanted.contains(window.windowID) {
                    let size = window.frame.size
                    guard size.width > 1, size.height > 1 else { continue }
                    group.addTask {
                        let scale = min(2, maxWidth / size.width)
                        let config = SCStreamConfiguration()
                        config.width = max(1, Int(size.width * scale))
                        config.height = max(1, Int(size.height * scale))
                        config.showsCursor = false
                        let filter = SCContentFilter(desktopIndependentWindow: window)
                        guard let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return }
                        let image = NSImage(cgImage: cgImage, size: size)
                        let id = window.windowID
                        await MainActor.run {
                            Thumbnailer.shared.cache[id] = image
                            onUpdate(id, image)
                        }
                    }
                }
            }
        }
    }

    /// Drops previews of windows that no longer exist.
    func prune(keeping ids: [CGWindowID]) {
        let keep = Set(ids)
        cache = cache.filter { keep.contains($0.key) }
    }
}
