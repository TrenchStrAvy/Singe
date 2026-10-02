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
    var pos: String = ""      // Wiktionary part of speech ("name" for proper names)

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
        candidates.append(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Singe/terms.sqlite").path)
        candidates.append(fm.currentDirectoryPath + "/build/terms.sqlite")
        return candidates.first { fm.fileExists(atPath: $0) }
    }

    /// Candidates for a selection. Slash- or comma-joined terms ("RTS/ITS") are looked up
    /// whole first, then per part, and the parts are interleaved.
    /// True when the whole selection is a known term or phrase (not only its parts).
    func knowsWhole(_ selection: String) -> Bool {
        let whole = Self.normalize(selection)
        return !(glossary[whole.lowercased()] ?? []).isEmpty || !wiktionarySenses(whole).isEmpty
    }

    func candidates(for selection: String, profile: [String: Double] = [:]) -> [Sense] {
        let whole = Self.normalize(selection)
        guard !whole.isEmpty else { return [] }
        let multiWord = whole.contains(" ")
        var found = multiWord && !knowsWhole(whole) ? [] : lookup(whole)
        // A phrase no index knows ("original packaging", "third-party ICT risk"): explain its
        // parts. Longest known pieces first, one best meaning each, ranked by your history.
        if found.isEmpty && multiWord {
            found = phraseParts(whole).compactMap { Ranker.rank($0, profile: profile).first }.map { s in
                // title each row by its part; abbreviations keep their expansion
                let isAbbrev = s.name.caseInsensitiveCompare(s.term) != .orderedSame && s.source == .wiktionary
                    && s.gloss.hasPrefix("Stands for")
                return Sense(id: s.id, term: s.term, name: isAbbrev || s.source == .glossary ? s.name : s.term,
                             gloss: s.gloss, label: s.label, topics: s.topics, rank: s.rank, source: s.source)
            }
            if !found.isEmpty { return found }
        }
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

    private static let phraseStopwords: Set<String> = [
        "a", "an", "the", "of", "and", "or", "to", "in", "on", "for", "by", "with", "at", "as", "from",
        "your", "my", "our", "their", "its", "his", "her", "this", "that", "these", "those", "is", "are",
        "be", "was", "were", "it", "into", "not", "no", "do", "you", "we", "they", "i",
    ]

    /// Greedy left-to-right split into the longest pieces the index knows (up to four words).
    func phraseParts(_ phrase: String) -> [[Sense]] {
        let words = phrase.split(separator: " ").map(String.init)
        var parts: [[Sense]] = []
        var i = 0
        while i < words.count {
            var matched = false
            for n in stride(from: min(4, words.count - i), through: 1, by: -1) {
                let piece = words[i..<(i + n)].joined(separator: " ")
                if n == 1 && Self.phraseStopwords.contains(piece.lowercased()) { break }
                if piece.rangeOfCharacter(from: .alphanumerics) == nil { break }   // "·", "–", "/"…
                var senses = (glossary[piece.lowercased()] ?? []) + wiktionarySenses(piece)
                if senses.isEmpty {
                    for stem in Self.stems(piece) {
                        senses = (glossary[stem.lowercased()] ?? []) + wiktionarySenses(stem)
                        if !senses.isEmpty { break }
                    }
                }
                if senses.isEmpty, n == 1 {
                    // "third-party" unknown? try its halves; then the macOS dictionary
                    if piece.contains("-") {
                        parts += phraseParts(piece.replacingOccurrences(of: "-", with: " "))
                        matched = true; i += 1; break
                    }
                    if let d = dictionarySense(piece) { senses = [d] }
                }
                if !senses.isEmpty {
                    parts.append(senses)
                    i += n
                    matched = true
                    break
                }
            }
            if !matched { i += 1 }
        }
        // the same piece twice ("Sorph … Sorph") shows once
        var seen = Set<String>()
        return parts.filter { seen.insert($0.first?.term.lowercased() ?? "").inserted }
    }

    private func lookup(_ term: String) -> [Sense] {
        var out = glossary[term.lowercased()] ?? []
        out += wiktionarySenses(term)
        // "walked" only matches the surname "Walked": the verb lives under "walk"
        let onlyNames = !out.isEmpty && term.first?.isLowercase == true
            && out.allSatisfy { $0.pos == "name" && $0.term != term }
        if out.isEmpty || onlyNames {
            for stem in Self.stems(term) {
                let base = (glossary[stem.lowercased()] ?? []) + wiktionarySenses(stem).filter { $0.pos != "name" }
                if !base.isEmpty { out = base + out; break }
            }
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
        // and, for a lowercase selection, ordinary senses before proper names ("running", not "Running")
        let lower = term.first?.isLowercase == true
        let sorted = rows.enumerated().sorted { a, b in
            let ea = (a.element["word"] as? String) == term, eb = (b.element["word"] as? String) == term
            if ea != eb { return ea }
            if lower {
                let na = (a.element["pos"] as? String) == "name", nb = (b.element["pos"] as? String) == "name"
                if na != nb { return nb }
            }
            return a.offset < b.offset
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
            let name = expansion.map { Self.titleCase(Self.short($0)) } ?? Self.gist(gloss)
            let label = topics.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces).capitalized }
                ?? Self.posLabel(pos)
            return Sense(id: "w:\(word):\(row["rank"] as? Int ?? i)", term: word, name: name, gloss: gloss,
                         label: label, topics: topics, rank: i, source: .wiktionary, pos: pos)
        }
    }

    /// The built-in macOS dictionary, for ordinary words the index lacks.
    private func dictionarySense(_ term: String) -> Sense? {
        let range = CFRange(location: 0, length: (term as NSString).length)
        guard let def = DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue() as String? else { return nil }
        // The dictionary answers with the nearest headword ("hand" for "hand-on"): only accept
        // the word itself or a simple inflection of it.
        let parts = def.components(separatedBy: "|")
        let head = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "-' ")).inverted).joined()
        let t = term.lowercased()
        guard head == t || (t.hasPrefix(head) && t.count - head.count <= 3 && !t.dropFirst(head.count).contains("-"))
        else { return nil }
        // keep the first definition: after the part of speech, up to the example or next sense
        var text = parts.count > 1 ? parts[1...].joined(separator: "|") : def
        text = text.replacingOccurrences(of: "\n", with: " ")
        if let r = text.range(of: #"^\s*[a-z ]+?\s+(1\s+)?"#, options: .regularExpression) { text.removeSubrange(r) }
        for stop in [":", " | ", " 2 ", " • "] {
            if let r = text.range(of: stop) { text = String(text[..<r.lowerBound]) }
        }
        text = text.trimmingCharacters(in: .whitespaces)
        guard text.count > 3 else { return nil }
        if text.count > 240 { text = String(text.prefix(239)) + "…" }
        text = text.prefix(1).uppercased() + text.dropFirst()
        if !text.hasSuffix(".") && !text.hasSuffix("…") { text += "." }
        return Sense(id: "d:\(term)", term: term, name: term, gloss: text, label: "Dictionary",
                     topics: "", rank: 0, source: .dictionary)
    }

    /// Likely base forms of an inflected word: studies → study, walked → walk, running → run.
    static func stems(_ word: String) -> [String] {
        let w = word
        guard w.count > 3, !w.contains(" ") else { return [] }
        var out: [String] = []
        func drop(_ n: Int) -> String { String(w.dropLast(n)) }
        let l = w.lowercased()
        if l.hasSuffix("ies") { out.append(drop(3) + "y") }
        if l.hasSuffix("es") { out.append(drop(2)) }
        if l.hasSuffix("s") && !l.hasSuffix("ss") { out.append(drop(1)) }
        if l.hasSuffix("ied") { out.append(drop(3) + "y") }
        if l.hasSuffix("ed") { out += [drop(2), drop(1)] }
        if l.hasSuffix("ing") && w.count > 5 { out += [drop(3), drop(3) + "e"] }
        // doubled consonant: running → run, stopped → stop
        for suffix in ["ing", "ed"] where l.hasSuffix(suffix) {
            let base = drop(suffix.count)
            if base.count > 2, let a = base.last, let b = base.dropLast().last, a == b { out.append(String(base.dropLast())) }
        }
        if l.hasSuffix("ly") && w.count > 5 { out.append(drop(2)) }
        return out.filter { $0.count >= 2 }
    }

    static func normalize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "/&+-"))))
        return trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "Transmission Control Protocol/Internet Protocol, a standard for …" → the part before the comma.
    static func short(_ expansion: String) -> String {
        var e = expansion
        if e.count > 40, let colon = e.range(of: ": ") { e = String(e[..<colon.lowerBound]) }
        if e.count > 48, let comma = e.range(of: ", ") { e = String(e[..<comma.lowerBound]) }
        if e.count > 64, let paren = e.range(of: " (") { e = String(e[..<paren.lowerBound]) }
        return e
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
