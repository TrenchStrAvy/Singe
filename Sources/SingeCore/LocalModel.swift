import Foundation

/// Last resort when no index knows the term: ask the local Ollama model (the same
/// gemma3:4b Sorph uses) for up to three short meanings. Results are labelled as
/// model output in the popover. Nothing leaves the Mac.
enum LocalModel {
    static let model = UserDefaults.standard.string(forKey: "ollamaModel") ?? "gemma3:4b"
    static let endpoint = URL(string: "http://127.0.0.1:11434/api/generate")!

    /// Is Ollama running with the model pulled? Quick check, never blocks for long.
    static func isAvailable() -> Bool {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/tags")!, timeoutInterval: 1)
        req.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data, let s = String(data: data, encoding: .utf8) { ok = s.contains("\"\(model)\"") || s.contains(model) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 1.5)
        return ok
    }

    /// Loads the model into memory in the background so the first fallback answer is quick.
    static func warmUp() {
        var req = URLRequest(url: endpoint, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": "30m"])
        URLSession.shared.dataTask(with: req).resume()
    }

    /// One short sentence explaining a whole phrase: quick enough on a CPU (~40 tokens).
    static func explain(_ phrase: String, interests: [String]) async -> Sense? {
        let hint = interests.isEmpty ? "" : " The reader often reads about: \(interests.prefix(4).joined(separator: ", "))."
        let prompt = "In one plain sentence of at most 28 words, explain what \"\(phrase)\" means.\(hint) Answer with the sentence only."
        var req = URLRequest(url: endpoint, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "prompt": prompt, "stream": false, "keep_alive": "30m",
                                   "options": ["temperature": 0.1, "num_predict": 60]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let outer = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var text = (outer["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"*"))
        return Sense(id: "m:\(phrase)", term: phrase, name: TermIndex.titleCase(phrase), gloss: text,
                     label: "Local model", topics: "", rank: 0, source: .model)
    }

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
        let body: [String: Any] = ["model": model, "prompt": prompt, "stream": false, "format": "json", "keep_alive": "30m",
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
