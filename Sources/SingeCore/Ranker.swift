import Foundation

/// Orders candidate meanings by how close they are to what you have looked up before.
/// Each meaning becomes a bag of words (headline, definition, topics); your history is a
/// weighted bag of the words of meanings you chose. No page context is read.
enum Ranker {
    static let stopwords: Set<String> = [
        "a", "an", "the", "of", "and", "or", "to", "in", "on", "for", "by", "with", "as", "at", "is",
        "are", "be", "it", "its", "that", "this", "from", "which", "such", "used", "use", "any", "one",
        "other", "set", "into", "their", "they", "when", "can", "may", "has", "have", "how", "what",
        "who", "also", "than", "more", "most", "not", "all", "some", "each", "out", "up", "stands",
        "initialism", "acronym", "abbreviation", "noun", "verb",
    ]

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopwords.contains($0) }
    }

    static func tokens(of sense: Sense) -> [String] {
        tokens(sense.name + " " + sense.gloss + " " + sense.topics + " " + sense.topics)
    }

    static func rank(_ senses: [Sense], profile: [String: Double]) -> [Sense] {
        let scored = senses.enumerated().map { i, s -> (Sense, Double) in
            // the curated glossary keeps a small edge: it exists for the professional reading
            let prior = 1.0 / (1.0 + 0.35 * Double(i)) + (s.source == .glossary ? 0.35 : 0)
            let toks = Set(tokens(of: s))
            var affinity = 0.0
            for t in toks { affinity += log1p(profile[t] ?? 0) }
            affinity /= sqrt(Double(max(toks.count, 1)))
            return (s, prior + 1.2 * affinity)
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }
}
