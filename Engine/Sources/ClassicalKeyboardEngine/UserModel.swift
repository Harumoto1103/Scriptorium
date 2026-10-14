import Foundation

/// What this user actually writes: committed-word counts plus words they
/// insisted on (typed, autocorrect reverted, kept). Lives in the App Group
/// container so the host app can show / edit it.
public final class UserModel: Codable {
    private(set) var counts: [String: Int] = [:]      // word (as committed) → count
    private(set) var pairs: [String: Int] = [:]       // "prev\tnext" → count

    public init() {}

    public func learn(_ word: String, after prev: String?, language: Language) {
        guard !word.isEmpty else { return }
        counts[word, default: 0] += 1
        if let prev { pairs[norm(prev, language) + "\t" + word, default: 0] += 1 }
    }

    /// The user rejected an autocorrection: treat the literal as a real word.
    public func protect(_ word: String) { counts[word, default: 0] += 3 }

    public func count(_ word: String) -> Int { counts[word] ?? 0 }

    public func pairCount(_ prev: String, _ next: String, _ language: Language) -> Int {
        pairs[norm(prev, language) + "\t" + next] ?? 0
    }

    /// Learned words whose key starts with `prefix` (lexicon misses: names, neologisms).
    public func words(withKeyPrefix prefix: String, _ language: Language) -> [String] {
        counts.keys.filter { Folding.key($0, language).hasPrefix(prefix) }
    }

    private func norm(_ w: String, _ l: Language) -> String {
        l == .latin ? Folding.latinKey(w) : Greek.normalise(w)
    }

    public func save(to url: URL) throws { try JSONEncoder().encode(self).write(to: url, options: .atomic) }
    public static func load(from url: URL) -> UserModel {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(UserModel.self, from: $0) } ?? UserModel()
    }
}
