import AppKit

/// An app Singe has been used in, as shown in the menu's Apps tab.
struct AppRecord: Identifiable, Hashable {
    var id: String { bundle }
    let bundle: String
    let name: String
    let lookups: Int
    /// Lookups where the app said where the word was, so the highlight could be drawn.
    let placed: Int
    let lastUsed: Date
    /// The switch: highlight the word in this app. Off: meanings only, and Singe leaves the
    /// app's accessibility settings alone.
    let highlight: Bool
    /// The app only reported positions after Singe turned on its full accessibility mode
    /// (AXEnhancedUserInterface, the switch VoiceOver uses). Chrome needs this.
    let deep: Bool
}

/// Per-app highlight settings, read by the selection reader on background threads and
/// written by the menu. One table in the history database; this keeps an in-memory copy
/// behind a lock so a lookup never waits on SQLite.
final class AppAccess: ObservableObject {
    static let shared = AppAccess()

    @Published private(set) var apps: [AppRecord] = []

    private let db: SQLiteDB?
    private let lock = NSLock()
    private var cache: [String: AppRecord] = [:]

    init(path: String = Store.supportDir.appendingPathComponent("history.sqlite").path) {
        db = SQLiteDB(path: path)
        db?.script("""
            CREATE TABLE IF NOT EXISTS apps (bundle TEXT PRIMARY KEY, name TEXT NOT NULL,
                lookups INTEGER NOT NULL DEFAULT 0, placed INTEGER NOT NULL DEFAULT 0,
                last_used REAL NOT NULL DEFAULT 0, highlight INTEGER NOT NULL DEFAULT 1,
                deep INTEGER NOT NULL DEFAULT 0);
            """)
        reload()
    }

    // MARK: read (any thread)

    /// Apps never seen before are allowed: the switch is for turning the highlight off.
    func highlightAllowed(_ bundle: String?) -> Bool {
        guard let bundle else { return true }
        lock.lock(); defer { lock.unlock() }
        return cache[bundle]?.highlight ?? true
    }

    func needsDeep(_ bundle: String?) -> Bool {
        guard let bundle else { return false }
        lock.lock(); defer { lock.unlock() }
        return cache[bundle]?.deep ?? false
    }

    // MARK: write

    /// One lookup in this app, and whether the highlight could be placed.
    func noteLookup(bundle: String?, name: String, placed: Bool) {
        guard let bundle else { return }
        db?.exec("""
            INSERT INTO apps (bundle, name, lookups, placed, last_used) VALUES (?, ?, 1, ?, ?)
            ON CONFLICT(bundle) DO UPDATE SET name = excluded.name, lookups = lookups + 1,
                placed = placed + excluded.placed, last_used = excluded.last_used
            """, [bundle, name, placed ? 1 : 0, Date().timeIntervalSince1970])
        reload()
    }

    /// The app needed its full accessibility mode to report positions; turn it on when it
    /// comes to the front from now on.
    func markDeep(bundle: String?, name: String) {
        guard let bundle, !needsDeep(bundle) else { return }
        db?.exec("""
            INSERT INTO apps (bundle, name, deep) VALUES (?, ?, 1)
            ON CONFLICT(bundle) DO UPDATE SET deep = 1
            """, [bundle, name])
        reload()
    }

    /// `apply: false` only records it (the offscreen menu render must not touch running apps).
    func setHighlight(_ on: Bool, for bundle: String, apply: Bool = true) {
        db?.exec("UPDATE apps SET highlight = ? WHERE bundle = ?", [on ? 1 : 0, bundle])
        reload()
        guard apply else { return }
        // put the app back the way it was, or wake it up again
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundle) {
            DispatchQueue.global(qos: .utility).async {
                if on { SelectionReader.prepare(app) } else { SelectionReader.release(app) }
            }
        }
    }

    func forget(_ bundle: String) {
        db?.exec("DELETE FROM apps WHERE bundle = ?", [bundle])
        reload()
    }

    private func reload() {
        let rows = db?.query("SELECT * FROM apps ORDER BY last_used DESC") ?? []
        let list = rows.map { r in
            AppRecord(bundle: r["bundle"] as? String ?? "", name: r["name"] as? String ?? "",
                      lookups: r["lookups"] as? Int ?? 0, placed: r["placed"] as? Int ?? 0,
                      lastUsed: Date(timeIntervalSince1970: r["last_used"] as? Double ?? 0),
                      highlight: (r["highlight"] as? Int ?? 1) == 1, deep: (r["deep"] as? Int ?? 0) == 1)
        }
        lock.lock()
        cache = Dictionary(list.map { ($0.bundle, $0) }, uniquingKeysWith: { a, _ in a })
        lock.unlock()
        if Thread.isMainThread { apps = list } else { DispatchQueue.main.async { self.apps = list } }
    }
}
