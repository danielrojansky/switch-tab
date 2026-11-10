import SwiftUI
import UniformTypeIdentifiers

struct StatsView: View {
    @ObservedObject private var settings = Settings.shared

    private var days: Int? { [7, 30, nil][min(2, max(0, settings.statsPeriod))] }

    var body: some View {
        let summary = StatsStore.shared.summary(days: days)

        return Form {
            Section {
                Toggle("Collect usage statistics", isOn: $settings.statsEnabled)
                Text("Stored only on this Mac. Records app names, switch counts and active time. Never window titles or content.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                Picker("Period", selection: $settings.statsPeriod) {
                    Text("7 days").tag(0)
                    Text("30 days").tag(1)
                    Text("All time").tag(2)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    tile("\(summary.switches)", "switches")
                    tile(duration(summary.focusSeconds), "active time")
                    tile(String(format: "%.0f", summary.switchesPerHour), "switches / hour")
                    tile(String(format: "%.1f", summary.averageDepth), "Tab presses / switch")
                }
                HStack(spacing: 10) {
                    tile(String(format: "%.1f", summary.averageWindows), "open windows (avg)")
                    tile("\(summary.cancels)", "cancelled")
                    tile(summary.opens > 0 ? "\(Int((Double(summary.cancels) / Double(summary.opens) * 100).rounded()))%" : "0%", "cancel rate")
                }
            }

            Section("Active time by app") {
                if summary.focus.isEmpty { empty }
                let top = summary.focus.first?.seconds ?? 1
                ForEach(summary.focus.indices, id: \.self) { index in
                    bar(summary.focus[index].app, summary.focus[index].seconds / top, duration(summary.focus[index].seconds))
                }
            }

            Section("Most common switches") {
                if summary.pairs.isEmpty { empty }
                let top = Double(summary.pairs.first?.count ?? 1)
                ForEach(summary.pairs.indices, id: \.self) { index in
                    let pair = summary.pairs[index]
                    bar("\(pair.from) → \(pair.to)", Double(pair.count) / top, "\(pair.count)")
                }
            }

            Section("Switches by hour of day") {
                hourChart(summary.hours)
            }

            Section("Switcher actions") {
                if summary.actions.isEmpty { empty }
                let top = Double(summary.actions.first?.count ?? 1)
                ForEach(summary.actions.indices, id: \.self) { index in
                    bar(summary.actions[index].name.capitalized, Double(summary.actions[index].count) / top, "\(summary.actions[index].count)")
                }
            }

            Section {
                HStack {
                    Button("Refresh") { settings.objectWillChange.send() }
                    Button("Export CSV…") { export("csv") }
                    Button("Export JSON…") { export("json") }
                    Spacer()
                    Button("Delete All Data…", role: .destructive) { deleteAll() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var empty: some View {
        Text("No data yet").foregroundStyle(.secondary)
    }

    private func tile(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
    }

    private func bar(_ label: String, _ fraction: Double, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).lineLimit(1).truncationMode(.middle).frame(width: 170, alignment: .leading)
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: max(3, geometry.size.width * fraction))
            }
            .frame(height: 12)
            Text(value).monospacedDigit().frame(width: 64, alignment: .trailing)
        }
    }

    private func hourChart(_ hours: [Int]) -> some View {
        let top = Double(max(1, hours.max() ?? 1))
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { hour in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(hours[hour] > 0 ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: max(2, 60 * Double(hours[hour]) / top))
                        .frame(maxWidth: .infinity)
                        .help("\(hour):00, \(hours[hour]) switches")
                }
            }
            .frame(height: 62, alignment: .bottom)
            HStack {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text("\(hour):00").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func export(_ format: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "switch-tab-stats.\(format)"
        panel.allowedContentTypes = [format == "csv" ? .commaSeparatedText : .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if format == "csv" { try StatsStore.shared.exportCSV(to: url) } else { try StatsStore.shared.exportJSON(to: url) }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func deleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all collected statistics?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        StatsStore.shared.deleteAll()
        settings.objectWillChange.send()
    }
}
