import Foundation

public struct Suggestion: Hashable, CustomStringConvertible {
    public enum Kind: String { case exact, completion, correction, next, learned }
    public let text: String
    public let kind: Kind
    public let score: Double
    public var description: String { "\(text)[\(kind.rawValue) \(String(format: "%.2f", score))]" }
}

public struct Prediction {
    /// Ranked suggestions for the bar (best first, deduplicated).
    public let suggestions: [Suggestion]
    /// What a space should insert instead of the literal input, if anything.
    /// Greek: usually the accent restoration (ανθρωπος → ἄνθρωπος).
    public let autocorrect: Suggestion?
}

/// The whole keyboard brain: stateless per call, cheap enough for every keystroke.
public final class Predictor {
    public let lexicon: Lexicon
    public let language: Language
    public var latinStyle = LatinStyle()
    public var greekStyle = GreekStyle()
    public var autocorrectEnabled = true
    /// How many ranked suggestions to return (bar + "more" pages).
    public var maxSuggestions = 27
    public let user: UserModel
    private let layout: Layout

    // Scoring weights (log10 units). Tuned by eye on the demo sentences; the
    // blueprint's evaluation harness is where these should really be fitted.
    private let completionPenalty = 0.6     // + 0.1 per untyped letter
    private let bigramWeight = 1.2
    private let adjacentSub = 1.2, otherSub = 2.4, transpose = 1.3, indel = 1.8
    private let autocorrectMargin = 0.0     // correction must beat literal by this

    public init(lexicon: Lexicon, user: UserModel = UserModel()) {
        self.lexicon = lexicon
        self.language = lexicon.language
        self.user = user
        self.layout = .for(lexicon.language)
    }

    private func logf(_ f: Int) -> Double { log10(Double(f) / 100 + 1) }

    /// Re-spell a lexicon form in the user's chosen style. A macron typed by
    /// hand overrides "macrons off" for that word.
    private func display(_ w: String, typed: String) -> String {
        let forced = Marks.hasMacron(typed)
        switch language {
        case .latin:
            var st = latinStyle
            if forced { st.macrons = true }
            return st.apply(w)
        case .greek:
            return greekStyle.quantities || forced ? w : Marks.stripMacrons(w)
        }
    }

    /// Bigram counts after `prev`, keyed the way lexicon rows are matched:
    /// Latin by key, Greek by exact form.
    private func context(_ prev: String?) -> [String: Int] {
        guard let prev, !prev.isEmpty else { return [:] }
        let p = language == .latin ? Folding.latinKey(prev) : Greek.normalise(prev)
        var m: [String: Int] = [:]
        for (n, c) in lexicon.following(p) { m[n] = c }
        return m
    }

    private func bigramBonus(_ e: Lexicon.Entry, _ ctx: [String: Int], prev: String?) -> Double {
        let c = language == .latin ? ctx[e.key] : ctx[Greek.normalise(e.word)]
        var b = c.map { bigramWeight * log10(Double($0) + 1) } ?? 0
        if let prev { b += 0.8 * log10(Double(user.pairCount(prev, e.word, language)) + 1) }
        return b
    }

    private func userBonus(_ w: String) -> Double { 0.7 * log10(Double(user.count(w)) + 1) }

    /// `previous`: the last committed word (nil at start of text / after . ; ·)
    /// `typed`: the current partial word exactly as typed.
    public func predict(previous: String?, typed: String) -> Prediction {
        let key = Folding.key(typed, language)
        let ctx = context(previous)
        var best: [String: Suggestion] = [:]
        let typedMarks = Marks.hasMarks(typed)
        // elision: δ’ only matches elided forms; bare δ never auto-becomes δ’
        let elided = typed.hasSuffix("’")

        func add(_ e: Lexicon.Entry, _ kindIn: Suggestion.Kind, _ penalty: Double) {
            let isElided = e.word.hasSuffix("’")
            if elided && !isElided { return }
            let kind: Suggestion.Kind = !elided && isElided && kindIn == .exact ? .completion : kindIn
            // marks typed by hand (ā, ᾱ, ά, ἁ…) must be present in the candidate
            let clash = typedMarks && !Marks.consistent(typed: typed, candidate: e.word) ? 4.0 : 0
            let s = logf(e.freq) + bigramBonus(e, ctx, prev: previous) + userBonus(e.word) - penalty - clash
            let text = recase(display(e.word, typed: typed), like: typed)
            if (best[text]?.score ?? -.infinity) < s { best[text] = Suggestion(text: text, kind: kind, score: s) }
        }

        // 1. empty word: pure next-word prediction
        if key.isEmpty {
            for (n, _) in ctx.sorted(by: { $0.value > $1.value }).prefix(maxSuggestions) {
                let k = language == .latin ? n : Folding.greekKey(n)
                if let e = resolve(n, key: k) { add(e, .next, 0) }
            }
            return Prediction(suggestions: ranked(best), autocorrect: nil)
        }

        // 2. the key itself: accent / macron restorations
        var exact = lexicon.exact(key)
        if exact.isEmpty && language == .latin { exact = enclitic(key) }
        for e in exact { add(e, .exact, 0) }

        // 3. completions (lexicon + bigram-predicted + learned words)
        for e in lexicon.complete(key) where e.key != key {
            add(e, .completion, completionPenalty + 0.1 * Double(e.key.count - key.count))
        }
        for (n, _) in ctx {
            let k = language == .latin ? n : Folding.greekKey(n)
            if k.hasPrefix(key), k != key, let e = resolve(n, key: k) {
                add(e, .completion, completionPenalty + 0.1 * Double(k.count - key.count))
            }
        }
        for w in user.words(withKeyPrefix: key, language) {
            let k = Folding.key(w, language)
            add(Lexicon.Entry(key: k, word: w, freq: 100), .learned, k == key ? 0 : completionPenalty)
        }

        // 4. corrections, only when the input is not already a decent word
        let literalScore = exact.first { $0.word.hasSuffix("’") == elided }.map { logf($0.freq) } ?? -1.0
        if key.count >= 2 && literalScore < 1.5 {
            let candidates = edits(key)
            let found = lexicon.exactMany(candidates.map(\.0))
            for (k, cost) in candidates {
                for e in found[k] ?? [] { add(e, .correction, cost) }
            }
        }

        let list = ranked(best)
        return Prediction(suggestions: list, autocorrect: chooseAutocorrect(list, typed: typed, exact: exact, literalScore: literalScore))
    }

    /// Lexicon row for a bigram's `next` side (Latin: a key; Greek: an exact
    /// lowercase form — prefer the lowercase row over a capitalised twin).
    private func resolve(_ n: String, key k: String) -> Lexicon.Entry? {
        let rows = lexicon.exact(k)
        if language == .latin { return rows.first }
        return rows.first { Greek.normalise($0.word) == n && $0.word == $0.word.lowercased() }
            ?? rows.first { Greek.normalise($0.word) == n }
    }

    /// virumque / arma-ne / plus-ve: the dictionary lists no enclitic forms and
    /// the corpus only covers common ones, so split -que / -ne / -ve generically.
    private func enclitic(_ key: String) -> [Lexicon.Entry] {
        for clitic in ["que", "ne", "ue"] where key.hasSuffix(clitic) && key.count >= clitic.count + 2 {
            let stem = String(key.dropLast(clitic.count))
            let surface = clitic == "ue" ? "ve" : clitic
            let rows = lexicon.exact(stem).prefix(3)
            if !rows.isEmpty {
                // enclitics are rarer than the bare word: one order of magnitude
                return rows.map { Lexicon.Entry(key: key, word: $0.word + surface, freq: $0.freq / 10) }
            }
        }
        return []
    }

    private func chooseAutocorrect(_ list: [Suggestion], typed: String, exact: [Lexicon.Entry], literalScore: Double) -> Suggestion? {
        guard autocorrectEnabled else { return nil }
        // the literal was learned by the user → leave it alone
        if user.count(typed) > 0 { return nil }
        // A real word: only re-spell it (accents, macrons), never swap the word.
        if exact.contains(where: { $0.word.hasSuffix("’") == typed.hasSuffix("’") }) {
            guard let top = list.first(where: { $0.kind == .exact }), top.text != typed else { return nil }
            // the user spelled marks out and nothing in the lexicon agrees: trust them
            if Marks.hasMarks(typed) && !Marks.consistent(typed: typed, candidate: top.text) { return nil }
            return top
        }
        // Not a word: best correction, if there is a convincing one.
        guard Folding.key(typed, language).count >= 3,
              let c = list.first(where: { $0.kind == .correction }),
              c.score > literalScore + autocorrectMargin else { return nil }
        return c
    }

    private func ranked(_ m: [String: Suggestion]) -> [Suggestion] {
        Array(m.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.text < $1.text }.prefix(maxSuggestions))
    }

    private func recase(_ w: String, like typed: String) -> String {
        guard let f = typed.first, f.isUppercase else { return w }
        if typed.count > 1 && typed == typed.uppercased() { return w.uppercased() }
        return w.prefix(1).uppercased() + w.dropFirst()
    }

    /// Damerau edit-1 neighbours of `key` with keyboard-aware costs.
    func edits(_ key: String) -> [(String, Double)] {
        let a = Array(key), alpha = Folding.alphabet(language)
        var out: [String: Double] = [:]
        func put(_ c: [Character], _ cost: Double) {
            let s = String(c)
            if s != key && !s.isEmpty { out[s] = min(out[s] ?? .infinity, cost) }
        }
        for i in a.indices {
            var d = a; d.remove(at: i); put(d, indel)                           // extra letter typed
            if i + 1 < a.count { var t = a; t.swapAt(i, i + 1); put(t, transpose) }
            for ch in alpha where ch != a[i] {
                var s = a; s[i] = ch
                put(s, layout.adjacent(a[i], ch) ? adjacentSub : otherSub)
            }
        }
        for i in 0...a.count {
            for ch in alpha { var s = a; s.insert(ch, at: i); put(s, indel) }  // letter missed
        }
        return out.map { ($0.key, $0.value) }
    }
}
