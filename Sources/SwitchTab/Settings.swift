import AppKit
import Combine
import ServiceManagement

enum SwitcherStyle: Int, CaseIterable {
    case thumbnails, icons, titles

    var name: String {
        switch self {
        case .thumbnails: return "Thumbnails"
        case .icons: return "App Icons"
        case .titles: return "Titles"
        }
    }
}

enum KeyCode {
    static let tab = 48, backtick = 50, space = 49
    static let escape = 53, returnKey = 36
    static let left = 123, right = 124, down = 125, up = 126
    static let w = 13, m = 46, f = 3, q = 12, h = 4, t = 17
    static let s = 1, slash = 44, delete = 51
    /// Key codes of the number row, 1 through 9, in order.
    static let digits = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    static let triggerChoices: [(code: Int, name: String)] = [
        (tab, "Tab"), (backtick, "` (key above Tab)"), (space, "Space"),
    ]
}

/// User preferences, stored in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    private static let store = UserDefaults.standard
    private static func load<T>(_ key: String, _ fallback: T) -> T {
        store.object(forKey: key) as? T ?? fallback
    }
    private func save(_ value: Any, _ key: String) {
        Settings.store.set(value, forKey: key)
    }

    static let modifierNames = ["⌥ Option", "⌘ Command", "⌃ Control"]
    static func flags(forModifier index: Int) -> CGEventFlags {
        switch index {
        case 1: return .maskCommand
        case 2: return .maskControl
        default: return .maskAlternate
        }
    }

    // Shortcut 1: all windows. Shortcut 2: windows of the active app.
    @Published var holdModifier: Int = Settings.load("holdModifier", 0) { didSet { save(holdModifier, "holdModifier") } }
    @Published var triggerKey: Int = Settings.load("triggerKey", KeyCode.tab) { didSet { save(triggerKey, "triggerKey") } }
    @Published var appHoldModifier: Int = Settings.load("appHoldModifier", 0) { didSet { save(appHoldModifier, "appHoldModifier") } }
    @Published var appTriggerKey: Int = Settings.load("appTriggerKey", KeyCode.backtick) { didSet { save(appTriggerKey, "appTriggerKey") } }
    @Published var pinShortcutEnabled: Bool = Settings.load("pinShortcutEnabled", true) { didSet { save(pinShortcutEnabled, "pinShortcutEnabled") } }

    // Appearance
    @Published var style: Int = Settings.load("style", 0) { didSet { save(style, "style") } }
    @Published var size: Int = Settings.load("size", 1) { didSet { save(size, "size") } }
    @Published var theme: Int = Settings.load("theme", 0) { didSet { save(theme, "theme") } }
    @Published var animations: Bool = Settings.load("animations", true) { didSet { save(animations, "animations") } }
    @Published var glow: Bool = Settings.load("glow", true) { didSet { save(glow, "glow") } }

    @Published var adaptiveColor: Bool = Settings.load("adaptiveColor", true) { didSet { save(adaptiveColor, "adaptiveColor") } }
    @Published var ambientLight: Bool = Settings.load("ambientLight", true) { didSet { save(ambientLight, "ambientLight") } }
    /// Selected tab of the Preferences window. Not stored.
    @Published var prefsTab: Int = 0

    /// Animations are on and the system "Reduce motion" setting is off.
    var motion: Bool { animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    @Published var showHints: Bool = Settings.load("showHints", true) { didSet { save(showHints, "showHints") } }

    @Published var showDockBadges: Bool = Settings.load("showDockBadges", true) { didSet { save(showDockBadges, "showDockBadges") } }

    // Statistics (opt-in)
    @Published var statsEnabled: Bool = Settings.load("statsEnabled", false) { didSet { save(statsEnabled, "statsEnabled") } }
    @Published var statsPeriod: Int = Settings.load("statsPeriod", 0) { didSet { save(statsPeriod, "statsPeriod") } }

    // Which windows to show
    @Published var allSpaces: Bool = Settings.load("allSpaces", true) { didSet { save(allSpaces, "allSpaces") } }
    @Published var showMinimized: Bool = Settings.load("showMinimized", true) { didSet { save(showMinimized, "showMinimized") } }
    @Published var showHidden: Bool = Settings.load("showHidden", true) { didSet { save(showHidden, "showHidden") } }
    @Published var showFullscreen: Bool = Settings.load("showFullscreen", true) { didSet { save(showFullscreen, "showFullscreen") } }
    @Published var showWindowless: Bool = Settings.load("showWindowless", false) { didSet { save(showWindowless, "showWindowless") } }
    @Published var sortOrder: Int = Settings.load("sortOrder", 0) { didSet { save(sortOrder, "sortOrder") } }

    // Behavior
    @Published var hoverSelect: Bool = Settings.load("hoverSelect", true) { didSet { save(hoverSelect, "hoverSelect") } }
    @Published var showMenuBarIcon: Bool = Settings.load("showMenuBarIcon", true) { didSet { save(showMenuBarIcon, "showMenuBarIcon") } }
    @Published var blacklist: [String] = Settings.load("blacklist", [String]()) { didSet { save(blacklist, "blacklist") } }

    /// Mirrors the system login item; not stored in UserDefaults.
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            let enabled = SMAppService.mainApp.status == .enabled
            guard launchAtLogin != enabled else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = enabled
            }
        }
    }

    var switcherStyle: SwitcherStyle { SwitcherStyle(rawValue: style) ?? .thumbnails }
}
