import Foundation

/// Last resort when no index knows the term: ask the local Ollama model (the same
/// gemma3:4b Sorph uses) for up to three short meanings. Results are labelled as
/// model output in the popover. Nothing leaves the Mac.
enum LocalModel {
    static let model = UserDefaults.standard.string(forKey: "ollamaModel") ?? "gemma3:4b"
    static let endpoint = URL(string: "http://127.0.0.1:11434/api/generate")!

    static func meanings(for term: String, profileHint: [String]) async -> [Sense] {
        let hint = profileHint.isEmpty ? "" :
            " The reader often looks up terms about: \(profileHint.prefix(6).joined(separator: ", ")). List the meaning in that field first if one exists."
        let prompt = """
        Give up to 3 distinct common meanings of the term "\(term)".\(hint) \
        Only include meanings you are confident are real. Answer as JSON: \
        {"meanings":[{"name":"full name or expansion","field":"one or two words","definition":"one sentence"}]}
        """
        var req = URLRequest(url: endpoint, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "prompt": prompt, "stream": false, "format": "json",
                                   "options": ["temperature": 0.1, "num_predict": 260]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = outer["response"] as? String,
              let inner = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let list = inner["meanings"] as? [[String: Any]] else { return [] }
        return list.prefix(3).enumerated().compactMap { i, m in
            guard let name = m["name"] as? String, let def = m["definition"] as? String, !def.isEmpty else { return nil }
            let field = (m["field"] as? String ?? "").capitalized
            return Sense(id: "m:\(term):\(i)", term: term, name: name, gloss: def,
                         label: field.isEmpty ? "Local model" : field, topics: field.lowercased(),
                         rank: i, source: .model)
        }
    }
}
