import AppKit
import Foundation

struct TermRecord: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let term: String
    let meaning: String
    let gloss: String
    let label: String
    let app: String
    let firstSeen: Date
    let lastSeen: Date
    let count: Int
    let starred: Bool
    let lists: [Int]
}

struct TermList: Identifiable, Hashable {
    let id: Int
    let name: String
    let color: String      // one of ListColor.all
    let count: Int
}

enum ListColor {
    static let all = ["red", "orange", "yellow", "green", "blue", "purple"]
    static func nsColor(_ name: String) -> NSColor {
        switch name {
        case "red": return .systemRed
        case "orange": return .systemOrange
        case "yellow": return .systemYellow
        case "green": return .systemGreen
        case "blue": return .systemBlue
        default: return .systemPurple
        }
    }
}

/// History, saved terms, coloured lists, and the ranking profile. One SQLite file in
/// ~/Library/Application Support/Singe.
final class Store: ObservableObject {
    static let supportDir: URL = {
        // SINGE_HOME keeps test runs away from your real history
        let dir = ProcessInfo.processInfo.environment["SINGE_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Singe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    @Published private(set) var records: [TermRecord] = []
    @Published private(set) var lists: [TermList] = []

    private let db: SQLiteDB

    init(path: String = Store.supportDir.appendingPathComponent("history.sqlite").path) {
        db = SQLiteDB(path: path)!
        db.script("""
            CREATE TABLE IF NOT EXISTS terms (
                key TEXT PRIMARY KEY, term TEXT NOT NULL, meaning TEXT NOT NULL, gloss TEXT NOT NULL,
                label TEXT NOT NULL, app TEXT NOT NULL, first_seen REAL NOT NULL, last_seen REAL NOT NULL,
                count INTEGER NOT NULL DEFAULT 1, starred INTEGER NOT NULL DEFAULT 0);
            CREATE TABLE IF NOT EXISTS lists (id INTEGER PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS list_items (list_id INTEGER NOT NULL, key TEXT NOT NULL,
                PRIMARY KEY (list_id, key));
            CREATE TABLE IF NOT EXISTS profile (token TEXT PRIMARY KEY, weight REAL NOT NULL);
            """)
        pruneProfile()
        refresh()
    }

    /// Drops filler words learned by earlier versions, so they no longer skew rankings.
    private func pruneProfile() {
        for word in Ranker.stopwords {
            db.exec("DELETE FROM profile WHERE token = ?", [word])
        }
        db.exec("DELETE FROM profile WHERE length(token) < 3")
    }

    // MARK: lookups

    /// Records a lookup with the meaning shown first. Re-looking up a term moves it to the top.
    func recordLookup(term: String, sense: Sense, app: String) {
        let key = term.lowercased(), now = Date().timeIntervalSince1970
        db.exec("""
            INSERT INTO terms (key, term, meaning, gloss, label, app, first_seen, last_seen)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET last_seen = excluded.last_seen, count = count + 1, app = excluded.app
            """, [key, term, sense.name, sense.gloss, sense.label, app, now, now])
        learn(sense, weight: 1)
        refresh()
    }

    /// The reader tapped a meaning: remember it for this term and weigh it in future rankings.
    func choose(term: String, sense: Sense) {
        db.exec("UPDATE terms SET meaning = ?, gloss = ?, label = ? WHERE key = ?",
                [sense.name, sense.gloss, sense.label, term.lowercased()])
        learn(sense, weight: 3)
        refresh()
    }

    /// Replaces the stored meaning without counting it as your choice (the phrase explanation).
    func updateMeaning(term: String, sense: Sense) {
        db.exec("UPDATE terms SET meaning = ?, gloss = ?, label = ? WHERE key = ?",
                [sense.name, sense.gloss, sense.label, term.lowercased()])
        refresh()
    }

    func chosenMeaning(for term: String) -> String? {
        db.query("SELECT meaning FROM terms WHERE key = ?", [term.lowercased()]).first?["meaning"] as? String
    }

    func isStarred(_ term: String) -> Bool {
        (db.query("SELECT starred FROM terms WHERE key = ?", [term.lowercased()]).first?["starred"] as? Int) == 1
    }

    func setStarred(_ term: String, _ on: Bool) {
        db.exec("UPDATE terms SET starred = ? WHERE key = ?", [on, term.lowercased()])
        refresh()
    }

    func delete(_ key: String) {
        db.exec("DELETE FROM terms WHERE key = ?", [key])
        db.exec("DELETE FROM list_items WHERE key = ?", [key])
        refresh()
    }

    // MARK: lists (a list has a colour, so marking a term means putting it in a list)

    @discardableResult
    func createList(name: String, color: String) -> Int {
        db.exec("INSERT INTO lists (name, color) VALUES (?, ?)", [name, color])
        let id = Int(db.lastInsertID)
        refresh()
        return id
    }

    func deleteList(_ id: Int) {
        db.exec("DELETE FROM lists WHERE id = ?", [id])
        db.exec("DELETE FROM list_items WHERE list_id = ?", [id])
        refresh()
    }

    func toggle(_ key: String, in list: Int) {
        if db.query("SELECT 1 FROM list_items WHERE list_id = ? AND key = ?", [list, key]).isEmpty {
            db.exec("INSERT INTO list_items VALUES (?, ?)", [list, key])
        } else {
            db.exec("DELETE FROM list_items WHERE list_id = ? AND key = ?", [list, key])
        }
        refresh()
    }

    // MARK: ranking profile

    func profile() -> [String: Double] {
        var out: [String: Double] = [:]
        for row in db.query("SELECT token, weight FROM profile") {
            if let t = row["token"] as? String, let w = row["weight"] as? Double { out[t] = w }
        }
        return out
    }

    func topInterests(_ n: Int) -> [String] {
        db.query("SELECT token FROM profile ORDER BY weight DESC LIMIT ?", [n]).compactMap { $0["token"] as? String }
    }

    private func learn(_ sense: Sense, weight: Double) {
        for token in Set(Ranker.tokens(of: sense)) {
            db.exec("""
                INSERT INTO profile (token, weight) VALUES (?, ?)
                ON CONFLICT(token) DO UPDATE SET weight = MIN(weight + excluded.weight, 60)
                """, [token, weight])
        }
    }

    // MARK: reading

    func refresh() {
        var membership: [String: [Int]] = [:]
        for row in db.query("SELECT list_id, key FROM list_items") {
            if let k = row["key"] as? String, let l = row["list_id"] as? Int { membership[k, default: []].append(l) }
        }
        records = db.query("SELECT * FROM terms ORDER BY last_seen DESC").map { r in
            let key = r["key"] as? String ?? ""
            return TermRecord(
                key: key, term: r["term"] as? String ?? "", meaning: r["meaning"] as? String ?? "",
                gloss: r["gloss"] as? String ?? "", label: r["label"] as? String ?? "",
                app: r["app"] as? String ?? "",
                firstSeen: Date(timeIntervalSince1970: r["first_seen"] as? Double ?? 0),
                lastSeen: Date(timeIntervalSince1970: r["last_seen"] as? Double ?? 0),
                count: r["count"] as? Int ?? 1, starred: (r["starred"] as? Int) == 1,
                lists: membership[key] ?? [])
        }
        lists = db.query("""
            SELECT l.id, l.name, l.color, COUNT(i.key) AS n FROM lists l
            LEFT JOIN list_items i ON i.list_id = l.id GROUP BY l.id ORDER BY l.name COLLATE NOCASE
            """).map { r in
            TermList(id: r["id"] as? Int ?? 0, name: r["name"] as? String ?? "",
                     color: r["color"] as? String ?? "blue", count: r["n"] as? Int ?? 0)
        }
    }

    // MARK: export

    func markdown() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        var md = "# Singe glossary\n\nExported \(fmt.string(from: Date())). \(records.count) terms.\n"
        func entry(_ r: TermRecord) -> String {
            let star = r.starred ? " ⭐" : ""
            return "- **\(r.term)**\(star): \(r.meaning). \(r.gloss) _(\(r.label), first looked up \(fmt.string(from: r.firstSeen)))_\n"
        }
        for list in lists {
            let members = records.filter { $0.lists.contains(list.id) }
            guard !members.isEmpty else { continue }
            md += "\n## \(list.name)\n\n" + members.map(entry).joined()
        }
        let saved = records.filter(\.starred)
        if !saved.isEmpty { md += "\n## Saved\n\n" + saved.map(entry).joined() }
        md += "\n## All terms\n\n" + records.map(entry).joined()
        return md
    }
}
