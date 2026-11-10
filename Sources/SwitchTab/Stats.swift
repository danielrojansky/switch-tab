import AppKit
import SQLite3

// Local usage statistics. Off by default. Everything stays in one SQLite file on this
// Mac. Only app bundle IDs are stored, never window titles.

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct StatsSummary {
    var switches = 0
    var cancels = 0
    var opens = 0
    var averageDepth = 0.0
    var averageWindows = 0.0
    var focusSeconds = 0.0
    var focus: [(app: String, seconds: Double)] = []
    var pairs: [(from: String, to: String, count: Int)] = []
    var hours = [Int](repeating: 0, count: 24)
    var actions: [(name: String, count: Int)] = []

    /// Switches per hour of tracked active time.
    var switchesPerHour: Double { focusSeconds > 0 ? Double(switches) / (focusSeconds / 3600) : 0 }
}

final class StatsStore {
    static let shared = StatsStore()

    let url: URL
    private var db: OpaquePointer?
    private var nameCache: [String: String] = [:]

    var enabled: Bool { Settings.shared.statsEnabled }

    private init() {
        if let override = ProcessInfo.processInfo.environment["SWITCHTAB_STATS_DB"] {
            url = URL(fileURLWithPath: override)
        } else {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SwitchTab", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            url = folder.appendingPathComponent("stats.sqlite")
        }
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            db = nil
            return
        }
        run("""
            CREATE TABLE IF NOT EXISTS events(
                id INTEGER PRIMARY KEY, ts REAL NOT NULL, kind TEXT NOT NULL,
                app TEXT, other TEXT, value REAL NOT NULL DEFAULT 0)
            """)
        run("CREATE INDEX IF NOT EXISTS events_ts ON events(ts)")
        run("""
            CREATE TABLE IF NOT EXISTS focus(
                day TEXT NOT NULL, app TEXT NOT NULL, seconds REAL NOT NULL,
                PRIMARY KEY(day, app))
            """)
    }

    // MARK: Recording

    /// kind: open, switch, cancel, action. `other` holds the source app or the action name.
    func record(_ kind: String, app: String? = nil, other: String? = nil, value: Double = 0) {
        guard enabled else { return }
        run("INSERT INTO events(ts, kind, app, other, value) VALUES(?, ?, ?, ?, ?)",
            [Date().timeIntervalSince1970, kind, app, other, value])
    }

    func addFocus(app: String, seconds: Double) {
        guard enabled else { return }
        run("""
            INSERT INTO focus(day, app, seconds) VALUES(date('now', 'localtime'), ?, ?)
            ON CONFLICT(day, app) DO UPDATE SET seconds = seconds + excluded.seconds
            """, [app, seconds])
    }

    /// Called every few seconds: credits the frontmost app while the user is active.
    func tick(interval: Double) {
        guard enabled, let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        let idle = [CGEventType.keyDown, .mouseMoved, .leftMouseDown, .scrollWheel]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
        if idle < 60 { addFocus(app: app, seconds: interval) }
    }

    // MARK: Reading

    func summary(days: Int?) -> StatsSummary {
        var result = StatsSummary()
        let cutoff = days.map { Date().timeIntervalSince1970 - Double($0) * 86_400 } ?? 0
        let dayCutoff = days.map { "date('now', 'localtime', '-\($0 - 1) days')" } ?? "'0000-00-00'"

        func count(_ kind: String) -> Int {
            Int(query("SELECT COUNT(*) FROM events WHERE kind = ? AND ts >= ?", [kind, cutoff]).first?[0] as? Double ?? 0)
        }
        result.switches = count("switch")
        result.cancels = count("cancel")
        result.opens = count("open")
        result.averageDepth = query("SELECT AVG(value) FROM events WHERE kind = 'switch' AND ts >= ?", [cutoff]).first?[0] as? Double ?? 0
        result.averageWindows = query("SELECT AVG(value) FROM events WHERE kind = 'open' AND ts >= ?", [cutoff]).first?[0] as? Double ?? 0

        for row in query("SELECT app, SUM(seconds) FROM focus WHERE day >= \(dayCutoff) GROUP BY app ORDER BY 2 DESC") {
            if let app = row[0] as? String, let seconds = row[1] as? Double {
                result.focusSeconds += seconds
                if result.focus.count < 8 { result.focus.append((displayName(app), seconds)) }
            }
        }
        for row in query("""
            SELECT other, app, COUNT(*) FROM events
            WHERE kind = 'switch' AND ts >= ? AND other IS NOT NULL AND app IS NOT NULL AND other != app
            GROUP BY other, app ORDER BY 3 DESC LIMIT 6
            """, [cutoff]) {
            if let from = row[0] as? String, let to = row[1] as? String, let n = row[2] as? Double {
                result.pairs.append((displayName(from), displayName(to), Int(n)))
            }
        }
        for row in query("""
            SELECT CAST(strftime('%H', ts, 'unixepoch', 'localtime') AS INTEGER), COUNT(*) FROM events
            WHERE kind = 'switch' AND ts >= ? GROUP BY 1
            """, [cutoff]) {
            if let hour = row[0] as? Double, let n = row[1] as? Double, (0..<24).contains(Int(hour)) {
                result.hours[Int(hour)] = Int(n)
            }
        }
        for row in query("SELECT other, COUNT(*) FROM events WHERE kind = 'action' AND ts >= ? GROUP BY other ORDER BY 2 DESC", [cutoff]) {
            if let name = row[0] as? String, let n = row[1] as? Double {
                result.actions.append((name, Int(n)))
            }
        }
        return result
    }

    func displayName(_ bundleID: String) -> String {
        if let cached = nameCache[bundleID] { return cached }
        var name = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        nameCache[bundleID] = name
        return name
    }

    // MARK: Export and delete

    func exportCSV(to url: URL) throws {
        func cell(_ value: Any?) -> String {
            guard let value else { return "" }
            let text = value is Double ? String(format: "%g", value as! Double) : "\(value)"
            return text.contains(",") || text.contains("\"") ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
        }
        var lines = ["table,timestamp_or_day,kind,app,other,value"]
        for row in query("SELECT datetime(ts, 'unixepoch', 'localtime'), kind, app, other, value FROM events ORDER BY ts") {
            lines.append((["events"] + row.map(cell)).joined(separator: ","))
        }
        for row in query("SELECT day, app, seconds FROM focus ORDER BY day, app") {
            lines.append(["focus", cell(row[0]), "focus", cell(row[1]), "", cell(row[2])].joined(separator: ","))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func exportJSON(to url: URL) throws {
        let events = query("SELECT ts, kind, app, other, value FROM events ORDER BY ts").map { row -> [String: Any] in
            var item: [String: Any] = ["timestamp": row[0] as? Double ?? 0, "kind": row[1] as? String ?? "", "value": row[4] as? Double ?? 0]
            if let app = row[2] as? String { item["app"] = app }
            if let other = row[3] as? String { item["other"] = other }
            return item
        }
        let focus = query("SELECT day, app, seconds FROM focus ORDER BY day, app").map { row -> [String: Any] in
            ["day": row[0] as? String ?? "", "app": row[1] as? String ?? "", "seconds": row[2] as? Double ?? 0]
        }
        let data = try JSONSerialization.data(withJSONObject: ["events": events, "focus": focus],
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    func deleteAll() {
        run("DELETE FROM events")
        run("DELETE FROM focus")
    }

    // MARK: SQLite plumbing

    private func prepare(_ sql: String, _ arguments: [Any?]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard let db, sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        for (index, argument) in arguments.enumerated() {
            let position = Int32(index + 1)
            switch argument {
            case let text as String: sqlite3_bind_text(statement, position, text, -1, sqliteTransient)
            case let number as Double: sqlite3_bind_double(statement, position, number)
            case let number as Int: sqlite3_bind_int64(statement, position, Int64(number))
            default: sqlite3_bind_null(statement, position)
            }
        }
        return statement
    }

    private func run(_ sql: String, _ arguments: [Any?] = []) {
        guard let statement = prepare(sql, arguments) else { return }
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    /// Rows of values: text as String, numbers as Double, NULL as nil.
    private func query(_ sql: String, _ arguments: [Any?] = []) -> [[Any?]] {
        guard let statement = prepare(sql, arguments) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [[Any?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [Any?] = []
            for column in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, column) {
                case SQLITE_NULL: row.append(nil)
                case SQLITE_TEXT: row.append(String(cString: sqlite3_column_text(statement, column)))
                default: row.append(sqlite3_column_double(statement, column))
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Debug helper for `--stats-selftest`: writes sample data and prints the summary.
    func selfTest() -> Bool {
        deleteAll()
        record("open", value: 6)
        record("switch", app: "com.apple.Safari", other: "com.apple.finder", value: 1)
        record("switch", app: "com.apple.finder", other: "com.apple.Safari", value: 3)
        record("switch", app: "com.apple.Safari", other: "com.apple.finder", value: 2)
        record("cancel")
        record("action", app: "com.apple.Safari", other: "pin")
        addFocus(app: "com.apple.Safari", seconds: 1800)
        addFocus(app: "com.apple.Safari", seconds: 1800)
        addFocus(app: "com.apple.finder", seconds: 600)
        let s = summary(days: 7)
        print("switches=\(s.switches) cancels=\(s.cancels) opens=\(s.opens) depth=\(s.averageDepth) windows=\(s.averageWindows)")
        print("focus=\(s.focus) total=\(s.focusSeconds) perHour=\(s.switchesPerHour)")
        print("pairs=\(s.pairs) actions=\(s.actions) hourTotal=\(s.hours.reduce(0, +))")
        let folder = url.deletingLastPathComponent()
        do {
            try exportCSV(to: folder.appendingPathComponent("selftest.csv"))
            try exportJSON(to: folder.appendingPathComponent("selftest.json"))
        } catch {
            print("export failed: \(error)")
            return false
        }
        return s.switches == 3 && s.cancels == 1 && s.averageDepth == 2 && s.focusSeconds == 4200
            && s.pairs.first?.count == 2 && s.hours.reduce(0, +) == 3
    }
}
