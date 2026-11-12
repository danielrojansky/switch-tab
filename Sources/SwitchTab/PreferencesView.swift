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
            StatsView().tabItem { Label("Statistics", systemImage: "chart.bar") }
        }
        .frame(width: 580, height: 600)
    }

    private var general: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Switch Tab").font(.title2).fontWeight(.semibold)
                        Text("Version \(appVersion). Windows-style window switcher.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            Section("Permissions") {
                permissionRow("Accessibility", "Required: reads the shortcut and controls windows.",
                              granted: AXIsProcessTrusted(),
                              pane: "Privacy_Accessibility")
                permissionRow("Screen Recording", "Window previews and always on top.",
                              granted: CGPreflightScreenCaptureAccess(),
                              pane: "Privacy_ScreenCapture")
            }
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

    private func permissionRow(_ name: String, _ detail: String, granted: Bool, pane: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text("Granted").foregroundStyle(.secondary)
            } else {
                Button("Open System Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private var appearance: some View {
        Form {
            Section("Preview") {
                // Redrawn on every settings change, with stand-in tiles.
                if let image = Switcher.previewImage() {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 170)
                        .padding(.vertical, 4)
                }
            }
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
            Section("Details") {
                Toggle("Key hints and position counter at the bottom", isOn: $settings.showHints)
                Toggle("Dock badges (unread counts) on tiles", isOn: $settings.showDockBadges)
            }
            Section("Effects") {
                Toggle("Animations (pop-in, sliding selection, cascading tiles)", isOn: $settings.animations)
                Toggle("Glowing gradient selection", isOn: $settings.glow)
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
                Toggle(isOn: $settings.pinShortcutEnabled) {
                    HStack(spacing: 4) {
                        keycap("⌃"); keycap("⌥"); keycap("T")
                        Text("keeps the focused window on top").padding(.leading, 4)
                    }
                }
            }
            Section("While the switcher is open") {
                keyRow(["Tab", "⇧ Tab", "← → ↑ ↓"], "Move selection")
                keyRow(["Release modifier", "Return"], "Focus selected window")
                keyRow(["Esc"], "Cancel")
                keyRow(["W"], "Close window")
                keyRow(["M"], "Minimize or restore")
                keyRow(["F"], "Toggle full screen")
                keyRow(["T"], "Keep on top, or stop")
                keyRow(["H"], "Hide or show app")
                keyRow(["Q"], "Quit app")
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

    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.2), lineWidth: 1))
    }

    private func keyRow(_ keys: [String], _ action: String) -> some View {
        HStack(spacing: 6) {
            Text(action)
            Spacer()
            ForEach(keys, id: \.self) { keycap($0) }
        }
    }

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

        return Form {
            Section("Apps never shown in the switcher") {
                if settings.blacklist.isEmpty {
                    Text("No apps excluded").foregroundStyle(.secondary)
                }
                ForEach(settings.blacklist, id: \.self) { bundleID in
                    let details = appDetails(bundleID)
                    HStack(spacing: 10) {
                        if let icon = details.icon {
                            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "app.dashed").frame(width: 24, height: 24)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(details.name)
                            if details.name != bundleID {
                                Text(bundleID).font(.caption).foregroundStyle(.secondary)
                            }
                        }
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
