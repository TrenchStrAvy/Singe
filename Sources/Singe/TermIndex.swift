import Foundation
import CoreServices

/// One possible meaning of a looked-up term.
struct Sense: Identifiable, Hashable {
    let id: String
    let term: String          // the part of the selection it explains, e.g. "RTS"
    let name: String          // headline: the expansion for abbreviations, else the word
    let gloss: String
    let label: String         // short chip: topic or part of speech
    let topics: String
    let rank: Int             // position in its source
    let source: Source

    enum Source: String { case glossary, wiktionary, dictionary, model }
}

/// Finds candidate meanings: the curated glossary, the Wiktionary index, the macOS
/// dictionary, and finally the local model. Every source is on this Mac.
final class TermIndex {
    private let wiktionary: SQLiteDB?
    private let glossary: [String: [Sense]]

    init() {
        wiktionary = Self.indexPath().flatMap { SQLiteDB(path: $0, readOnly: true) }
        glossary = Glossary.load()
    }

    var hasIndex: Bool { wiktionary != nil }

    static func indexPath() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["SINGE_INDEX"] { candidates.append(env) }
        if let res = Bundle.main.resourcePath { candidates.append(res + "/terms.sqlite") }
        candidates.append(Store.supportDir.appendingPathComponent("terms.sqlite").path)
        candidates.append(fm.currentDirectoryPath + "/build/terms.sqlite")
        return candidates.first { fm.fileExists(atPath: $0) }
    }

    /// Candidates for a selection. Slash- or comma-joined terms ("RTS/ITS") are looked up
    /// whole first, then per part, and the parts are interleaved.
    func candidates(for selection: String) -> [Sense] {
        let whole = Self.normalize(selection)
        guard !whole.isEmpty else { return [] }
        var found = lookup(whole)
        if found.count < 3 || found.allSatisfy({ $0.source == .dictionary }) {
            let parts = whole.split(whereSeparator: { "/,;&+".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count > 1 {
                let lists = parts.map { lookup($0) }
                var merged: [Sense] = []
                for i in 0..<(lists.map(\.count).max() ?? 0) {
                    for list in lists where i < list.count { merged.append(list[i]) }
                }
                if !merged.isEmpty {
                    found = found.filter { $0.source != .dictionary } + merged
                }
            }
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.name.lowercased()).inserted }
    }

    private func lookup(_ term: String) -> [Sense] {
        var out = glossary[term.lowercased()] ?? []
        out += wiktionarySenses(term)
        if out.isEmpty, term.lowercased().hasSuffix("s"), term.count > 3 {
            let singular = String(term.dropLast())
            out = (glossary[singular.lowercased()] ?? []) + wiktionarySenses(singular)
        }
        if out.isEmpty, let d = dictionarySense(term) { out = [d] }
        return out
    }

    private func wiktionarySenses(_ term: String) -> [Sense] {
        guard let db = wiktionary else { return [] }
        let rows = db.query("""
            SELECT word, pos, rank, gloss, expansion, abbrev, topics FROM senses
            WHERE term = ? ORDER BY rank LIMIT 24
            """, [term.lowercased()])
        // Prefer the exact capitalisation the user selected ("ITS" before "its").
        let sorted = rows.enumerated().sorted { a, b in
            let ea = (a.element["word"] as? String) == term, eb = (b.element["word"] as? String) == term
            return ea != eb ? ea : a.offset < b.offset
        }.map(\.element)
        return sorted.enumerated().map { i, row in
            let word = row["word"] as? String ?? term
            let pos = row["pos"] as? String ?? ""
            let expansion = row["expansion"] as? String
            var gloss = row["gloss"] as? String ?? ""
            let topics = row["topics"] as? String ?? ""
            if let e = expansion, gloss.lowercased().contains("of \(e.lowercased())") {
                gloss = "Stands for “\(e)”."
            }
            // Abbreviations show what they stand for; words show the gist of each sense,
            // since the term itself is already the popover's title.
            let name = expansion.map(Self.titleCase) ?? Self.gist(gloss)
            let label = topics.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces).capitalized }
                ?? Self.posLabel(pos)
            return Sense(id: "w:\(word):\(row["rank"] as? Int ?? i)", term: word, name: name, gloss: gloss,
                         label: label, topics: topics, rank: i, source: .wiktionary)
        }
    }

    /// The built-in macOS dictionary, for ordinary words the index lacks.
    private func dictionarySense(_ term: String) -> Sense? {
        let range = CFRange(location: 0, length: (term as NSString).length)
        guard let def = DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue() as String? else { return nil }
        var text = def.replacingOccurrences(of: "\n", with: " ")
        if let bar = text.range(of: "|") { text = String(text[bar.upperBound...]) }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.count > 260 { text = String(text.prefix(259)) + "…" }
        return Sense(id: "d:\(term)", term: term, name: term, gloss: text, label: "Dictionary",
                     topics: "", rank: 0, source: .dictionary)
    }

    static func normalize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "/&+-"))))
        return trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func gist(_ gloss: String) -> String {
        var g = gloss
        while g.hasPrefix("("), let close = g.firstIndex(of: ")") {
            g = String(g[g.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        if let cut = g.firstIndex(where: { ";:".contains($0) }) { g = String(g[..<cut]) }
        g = g.trimmingCharacters(in: CharacterSet(charactersIn: " .,"))
        if g.count > 64 {
            let words = g.prefix(64).split(separator: " ").dropLast()
            g = words.joined(separator: " ") + "…"
        }
        return g.isEmpty ? gloss : g.prefix(1).uppercased() + g.dropFirst()
    }

    static func titleCase(_ s: String) -> String {
        let small: Set<String> = ["of", "and", "the", "to", "for", "in", "on", "a", "an", "or", "by", "with"]
        let words = s.split(separator: " ").map { w in
            small.contains(w.lowercased()) ? String(w) : w.prefix(1).uppercased() + w.dropFirst()
        }
        let joined = words.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    static func posLabel(_ pos: String) -> String {
        switch pos {
        case "noun": return "Noun"
        case "verb": return "Verb"
        case "adj": return "Adjective"
        case "adv": return "Adverb"
        case "name": return "Name"
        case "phrase": return "Phrase"
        default: return pos.capitalized
        }
    }
}
