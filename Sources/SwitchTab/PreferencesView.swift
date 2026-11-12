import SwiftUI
import ServiceManagement

/// Preferences: a tab bar on top, then compact cards sized so no tab needs scrolling
/// (Statistics aside, which is a report).
struct PreferencesView: View {
    @ObservedObject private var settings = Settings.shared

    static let size = NSSize(width: 700, height: 540)
    private static let tabs: [(name: String, symbol: String)] = [
        ("General", "gearshape.fill"), ("Appearance", "paintbrush.fill"), ("Shortcuts", "keyboard.fill"),
        ("Exclusions", "nosign"), ("Statistics", "chart.bar.fill"),
    ]
    private let twoColumns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch settings.prefsTab {
                case 1: appearance.padding(16)
                case 2: shortcuts.padding(16)
                case 3: exclusions.padding(16)
                case 4: StatsView()
                default: general.padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(settings.prefsTab)
            .transition(.opacity)
        }
        .frame(width: PreferencesView.size.width, height: PreferencesView.size.height)
    }

    // MARK: Building blocks

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(PreferencesView.tabs.indices, id: \.self) { index in
                let selected = settings.prefsTab == index
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { settings.prefsTab = index }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: PreferencesView.tabs[index].symbol).font(.system(size: 17))
                        Text(PreferencesView.tabs[index].name).font(.system(size: 11, weight: .medium))
                    }
                    .frame(width: 92, height: 48)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .background(RoundedRectangle(cornerRadius: 9)
                        .fill(Color.accentColor.opacity(selected ? 0.16 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.09), lineWidth: 1))
    }

    /// A label on the left and a segmented control filling the rest.
    private func segmented<Content: View>(_ label: String, _ selection: Binding<Int>,
                                          @ViewBuilder _ options: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 52, alignment: .leading)
            Picker("", selection: selection) { options() }
                .labelsHidden()
                .pickerStyle(.segmented)
        }
    }

    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.2), lineWidth: 1))
    }

    private func keyRow(_ keys: [String], _ action: String) -> some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { keycap($0) }
            Text(action).font(.callout).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: General

    private var general: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Switch Tab").font(.title2).fontWeight(.semibold)
                    Text("Version \(appVersion). Windows-style window switcher.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    permissionChip("Accessibility", granted: AXIsProcessTrusted(), pane: "Privacy_Accessibility",
                                   help: "Required: reads the shortcut and controls windows.")
                    permissionChip("Screen Recording", granted: CGPreflightScreenCaptureAccess(),
                                   pane: "Privacy_ScreenCapture", help: "Window previews and always on top.")
                }
            }
            .padding(.horizontal, 4)

            HStack(alignment: .top, spacing: 12) {
                card("Startup") {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                    if !settings.showMenuBarIcon {
                        Text("Open Switch Tab again from Applications to get back to this window.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                card("Mouse") {
                    Toggle("Select the window under the pointer", isOn: $settings.hoverSelect)
                    Text("Click a tile to focus it. Buttons on a tile close, minimize, zoom or pin its window.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            card("Windows to show") {
                LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 9) {
                    Toggle("From all Spaces", isOn: $settings.allSpaces)
                    Toggle("Minimized windows", isOn: $settings.showMinimized)
                    Toggle("Windows of hidden apps", isOn: $settings.showHidden)
                    Toggle("Full-screen windows", isOn: $settings.showFullscreen)
                    Toggle("Apps with no open window", isOn: $settings.showWindowless)
                }
                Divider()
                segmented("Order", $settings.sortOrder) {
                    Text("Recently used first").tag(0)
                    Text("Alphabetical by app").tag(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Green when granted; otherwise an orange button that opens the right System Settings pane.
    @ViewBuilder
    private func permissionChip(_ name: String, granted: Bool, pane: String, help: String) -> some View {
        let label = HStack(spacing: 5) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(granted ? name : "Grant \(name)…")
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(granted ? Color.green : Color.orange)
        .background(Capsule().fill((granted ? Color.green : Color.orange).opacity(0.14)))

        if granted {
            label.help(help)
        } else {
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            } label: { label }
            .buttonStyle(.plain)
            .help(help)
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        VStack(spacing: 12) {
            // Redrawn on every settings change, with stand-in tiles.
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color.blue.opacity(0.22), Color.purple.opacity(0.22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                if let image = Switcher.previewImage() {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                }
            }
            .frame(height: 168)

            card("Layout") {
                segmented("Style", $settings.style) {
                    ForEach(SwitcherStyle.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                }
                segmented("Size", $settings.size) {
                    Text("Small").tag(0)
                    Text("Medium").tag(1)
                    Text("Large").tag(2)
                }
                segmented("Theme", $settings.theme) {
                    Text("Match system").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            card("Details and effects") {
                LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 9) {
                    Toggle("Key hints and position counter", isOn: $settings.showHints)
                    Toggle("Dock badges (unread counts)", isOn: $settings.showDockBadges)
                    Toggle("Animations", isOn: $settings.animations)
                        .help("Pop-in, sliding selection, cascading tiles, closing tiles. Follows the system Reduce Motion setting.")
                    Toggle("Glowing, breathing selection", isOn: $settings.glow)
                    Toggle("Selection takes the app's color", isOn: $settings.adaptiveColor)
                    Toggle("Ambient light behind the selection", isOn: $settings.ambientLight)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                card("All windows") {
                    shortcutPickers(modifier: $settings.holdModifier, key: $settings.triggerKey)
                }
                card("Windows of the current app") {
                    shortcutPickers(modifier: $settings.appHoldModifier, key: $settings.appTriggerKey)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            card("Always on top") {
                Toggle(isOn: $settings.pinShortcutEnabled) {
                    HStack(spacing: 4) {
                        keycap("⌃"); keycap("⌥"); keycap("T")
                        Text("keeps the focused window on top").padding(.leading, 4)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            card("While the switcher is open") {
                LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 8) {
                    keyRow(["Tab", "⇧ Tab", "← →"], "Move selection")
                    keyRow(["Return"], "Focus (or release modifier)")
                    keyRow(["1", "…", "9"], "Jump to that tile")
                    keyRow(["S", "/"], "Search by title or app")
                    keyRow(["W"], "Close window")
                    keyRow(["M"], "Minimize or restore")
                    keyRow(["F"], "Toggle full screen")
                    keyRow(["T"], "Keep on top, or stop")
                    keyRow(["H"], "Hide or show app")
                    keyRow(["Q"], "Quit app")
                    keyRow(["Esc"], "Cancel")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func shortcutPickers(modifier: Binding<Int>, key: Binding<Int>) -> some View {
        Picker("Hold", selection: modifier) {
            ForEach(Settings.modifierNames.indices, id: \.self) { Text(Settings.modifierNames[$0]).tag($0) }
        }
        Picker("Press", selection: key) {
            ForEach(KeyCode.triggerChoices, id: \.code) { Text($0.name).tag($0.code) }
        }
    }

    // MARK: Exclusions

    /// Name and icon for a bundle ID, falling back to the raw ID when the app is not installed.
    private func appDetails(_ bundleID: String) -> (name: String, icon: NSImage?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return (bundleID, nil)
        }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return (name, NSWorkspace.shared.icon(forFile: url.path))
    }

    private var exclusions: some View {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !settings.blacklist.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        return card("Apps never shown in the switcher") {
            HStack {
                Text(settings.blacklist.isEmpty ? "No apps excluded yet." : "\(settings.blacklist.count) excluded")
                    .foregroundStyle(.secondary)
                Spacer()
                Menu("Add a running app") {
                    ForEach(running, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) {
                            settings.blacklist.append(app.bundleIdentifier!)
                        }
                    }
                }
                .fixedSize()
            }
            ScrollView {
                LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 8) {
                    ForEach(settings.blacklist, id: \.self) { bundleID in
                        let details = appDetails(bundleID)
                        HStack(spacing: 8) {
                            if let icon = details.icon {
                                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                            } else {
                                Image(systemName: "app.dashed").frame(width: 26, height: 26)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(details.name).lineLimit(1)
                                if details.name != bundleID {
                                    Text(bundleID).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Button {
                                settings.blacklist.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Show this app in the switcher again")
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    }
                }
            }
        }
    }
}
