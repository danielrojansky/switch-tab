import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            appearance.tabItem { Label("Appearance", systemImage: "paintbrush") }
            shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }
            exclusions.tabItem { Label("Exclusions", systemImage: "nosign") }
        }
        .frame(width: 540, height: 500)
    }

    private var general: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                if !settings.showMenuBarIcon {
                    Text("With the icon hidden, open Switch Tab again from Applications to get back to this window.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Show windows") {
                Toggle("From all Spaces", isOn: $settings.allSpaces)
                Toggle("Minimized windows", isOn: $settings.showMinimized)
                Toggle("Windows of hidden apps", isOn: $settings.showHidden)
                Toggle("Full-screen windows", isOn: $settings.showFullscreen)
                Toggle("Apps with no open window", isOn: $settings.showWindowless)
                Picker("Order", selection: $settings.sortOrder) {
                    Text("Recently used first").tag(0)
                    Text("Alphabetical by app").tag(1)
                }
            }
            Section("Mouse") {
                Toggle("Select the window under the pointer", isOn: $settings.hoverSelect)
            }
        }
        .formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Section("Layout") {
                Picker("Style", selection: $settings.style) {
                    ForEach(SwitcherStyle.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Picker("Size", selection: $settings.size) {
                    Text("Small").tag(0)
                    Text("Medium").tag(1)
                    Text("Large").tag(2)
                }
                .pickerStyle(.segmented)
                Picker("Theme", selection: $settings.theme) {
                    Text("Match system").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.segmented)
            }
            Section("Effects") {
                Toggle("Animations (pop-in, sliding selection, cascading tiles)", isOn: $settings.animations)
                Toggle("Glowing gradient selection", isOn: $settings.glow)
                Toggle("Dock badges (unread counts) on tiles", isOn: $settings.showDockBadges)
            }
        }
        .formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("Switch between all windows") {
                shortcutPickers(modifier: $settings.holdModifier, key: $settings.triggerKey)
            }
            Section("Switch between windows of the current app") {
                shortcutPickers(modifier: $settings.appHoldModifier, key: $settings.appTriggerKey)
            }
            Section("Always on top") {
                Toggle("⌃⌥T keeps the focused window on top", isOn: $settings.pinShortcutEnabled)
            }
            Section("While the switcher is open") {
                keyRow("Tab / Shift+Tab, arrow keys", "Move selection")
                keyRow("Release modifier, Return", "Focus selected window")
                keyRow("Esc", "Cancel")
                keyRow("W", "Close window")
                keyRow("M", "Minimize or restore")
                keyRow("F", "Toggle full screen")
                keyRow("T", "Keep on top, or stop")
                keyRow("H", "Hide or show app")
                keyRow("Q", "Quit app")
            }
        }
        .formStyle(.grouped)
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

    private func keyRow(_ keys: String, _ action: String) -> some View {
        HStack {
            Text(keys).fontWeight(.medium)
            Spacer()
            Text(action).foregroundStyle(.secondary)
        }
    }

    private var exclusions: some View {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !settings.blacklist.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        return Form {
            Section("Apps never shown in the switcher") {
                if settings.blacklist.isEmpty {
                    Text("No apps excluded").foregroundStyle(.secondary)
                }
                ForEach(settings.blacklist, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                        Spacer()
                        Button("Remove") { settings.blacklist.removeAll { $0 == bundleID } }
                    }
                }
                Menu("Add a running app") {
                    ForEach(running, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) {
                            settings.blacklist.append(app.bundleIdentifier!)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
