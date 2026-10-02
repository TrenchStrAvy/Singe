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
        // common words that say nothing about a field
        "based", "provides", "provide", "provided", "under", "person", "people", "real", "time", "usually",
        "often", "thing", "things", "something", "someone", "way", "ways", "part", "parts", "relating",
        "related", "relation", "being", "made", "make", "makes", "making", "given", "give", "gives", "using",
        "first", "second", "third", "new", "old", "good", "well", "very", "much", "many", "such", "same",
        "other", "another", "particular", "especially", "generally", "typically", "certain", "various",
        "within", "without", "between", "through", "during", "before", "after", "over", "about", "against",
        "where", "there", "here", "then", "them", "these", "those", "would", "could", "should", "will",
        "shall", "might", "must", "having", "does", "done", "doing", "act", "action", "state", "quality",
        "kind", "type", "form", "number", "group", "place", "point", "process", "system", "systems",
        "used", "uses", "able", "known", "called", "term", "terms", "word", "words", "meaning", "sense",
        "general", "specific", "small", "large", "high", "low", "long", "short", "whole", "each", "every",
        "natural", "sciences", "science", "one's", "oneself", "itself", "themselves", "upon", "via", "per", "etc", "e.g", "i.e",
    ]

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopwords.contains($0) }
    }

    /// What a meaning is about: its headline and topics count fully; its definition adds only
    /// the longer, specific words.
    static func tokens(of sense: Sense) -> [String] {
        tokens(sense.name + " " + sense.topics + " " + sense.topics)
            + tokens(sense.gloss).filter { $0.count >= 7 }
    }

    /// `query`: the selected text; a meaning of exactly that text outranks meanings of its parts.
    static func rank(_ senses: [Sense], profile: [String: Double], query: String? = nil) -> [Sense] {
        let scored = senses.enumerated().map { i, s -> (Sense, Double) in
            // the curated glossary keeps a small edge: it exists for the professional reading
            var prior = 1.0 / (1.0 + 0.35 * Double(i)) + (s.source == .glossary ? 0.35 : 0)
            if let q = query, q.contains(where: { "/,;&+".contains($0) }),
               s.term.caseInsensitiveCompare(q) == .orderedSame { prior += 1.0 }
            let toks = Set(tokens(of: s))
            var affinity = 0.0
            for t in toks { affinity += log1p(profile[t] ?? 0) }
            affinity /= sqrt(Double(max(toks.count, 1)))
            return (s, prior + 1.2 * affinity)
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }
}
