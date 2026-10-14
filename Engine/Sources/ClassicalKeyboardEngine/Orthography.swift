import Foundation

/// Output conventions. The lexicon stores one canonical spelling (Wiktionary's:
/// macrons, consonantal v, no j); these options re-spell it on the way out.
public struct LatinStyle: Sendable, Equatable {
    public var macrons = false         // rōsā vs rosa
    public var consonantalV = true     // vir vs uir   (true = keep v)
    public var consonantalJ = false    // iam vs jam   (Wiktionary has no j)
    public init(macrons: Bool = false, consonantalV: Bool = true, consonantalJ: Bool = false) {
        self.macrons = macrons; self.consonantalV = consonantalV; self.consonantalJ = consonantalJ
    }

    public func apply(_ w: String) -> String {
        // breves never: short is the unmarked default
        var s = String(String.UnicodeScalarView(w.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { $0 != "\u{0306}" })).precomposedStringWithCanonicalMapping
        if !macrons {
            s = String(String.UnicodeScalarView(s.decomposedStringWithCanonicalMapping.unicodeScalars
                .filter { $0 != "\u{0304}" && $0 != "\u{0306}" })).precomposedStringWithCanonicalMapping
        }
        if !consonantalV {
            s = s.replacingOccurrences(of: "v", with: "u").replacingOccurrences(of: "V", with: "U")
        }
        if consonantalJ {
            // word-initial i before a vowel, and intervocalic i: iam→jam, maior→major
            s = s.replacingOccurrences(of: #"(?<![a-zāēīōū])i(?=[aeouāēōū])"#, with: "j", options: .regularExpression)
                 .replacingOccurrences(of: #"(?<=[aeouāēōū])i(?=[aeouāēōū])"#, with: "j", options: .regularExpression)
                 .replacingOccurrences(of: #"^I(?=[aeouāēōū])"#, with: "J", options: .regularExpression)
        }
        return s
    }
}

public struct GreekStyle: Sendable, Equatable {
    /// Macrons on long α ι υ (χώρᾱ, πρᾱ́ττω). Wiktionary marks them; the
    /// corpus does not, so corpus-only words simply come without.
    public var quantities = true
    public init(quantities: Bool = true) { self.quantities = quantities }
}

/// Diacritic bookkeeping shared by both languages.
public enum Marks {
    static let macron: Unicode.Scalar = "\u{0304}"

    public static func hasMarks(_ s: String) -> Bool {
        s.decomposedStringWithCanonicalMapping.unicodeScalars.contains { $0.properties.generalCategory == .nonspacingMark }
    }

    public static func hasMacron(_ s: String) -> Bool {
        s.decomposedStringWithCanonicalMapping.unicodeScalars.contains(macron)
    }

    public static func stripMacrons(_ s: String) -> String {
        String(String.UnicodeScalarView(s.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { $0 != macron && $0 != "\u{0306}" })).precomposedStringWithCanonicalMapping
    }

    /// Letter-by-letter clusters: base letter + its set of marks (grave counted as acute).
    static func clusters(_ s: String) -> [(Character, Set<Unicode.Scalar>)] {
        var out: [(Character, Set<Unicode.Scalar>)] = []
        for u in s.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            if u == "\u{0306}" { continue }        // a typed breve just means "short" = unmarked
            if u.properties.generalCategory == .nonspacingMark, !out.isEmpty {
                out[out.count - 1].1.insert(u == "\u{0300}" ? "\u{0301}" : u)
            } else {
                out.append((Character(u), []))
            }
        }
        return out
    }

    /// Does `candidate` carry every mark the user typed, on the same letter?
    /// (Only the typed span is compared, so completions qualify too.)
    /// Once the user types any macron, they are marking quantity themselves,
    /// so an unmarked vowel in the typed span means short: rosā ≠ rōsā.
    public static func consistent(typed: String, candidate: String) -> Bool {
        let t = clusters(typed), c = clusters(candidate)
        guard c.count >= t.count else { return false }
        let quantityTyped = t.contains { $0.1.contains(macron) }
        for (i, (_, marks)) in t.enumerated() {
            if !marks.isSubset(of: c[i].1) { return false }
            if quantityTyped && c[i].1.contains(macron) != marks.contains(macron) { return false }
        }
        return true
    }
}

public enum Greek {
    static let vowels: Set<Character> = ["α", "ε", "η", "ι", "ο", "υ", "ω"]
    /// Interrogatives never take the grave.
    static let alwaysAcute: Set<String> = ["τίς", "τί"]

    /// Oxytone → barytone when another word follows: καλός → καλὸς.
    /// Applied when a word is committed with a space; undone by `toAcute`
    /// if punctuation turns out to follow instead.
    public static func toGrave(_ w: String) -> String {
        guard !alwaysAcute.contains(w.lowercased()) else { return w }
        var u = Array(w.decomposedStringWithCanonicalMapping.unicodeScalars)
        guard let i = u.lastIndex(of: "\u{0301}") else { return w }
        // the acute must sit on the last vowel: nothing vowel-like after it
        // (scalar-wise: ᾳ is one Character but contains the vowel α)
        if u[(i + 1)...].contains(where: { vowels.contains(Character($0).lowercased().first!) }) { return w }
        u[i] = "\u{0300}"
        return String(String.UnicodeScalarView(u)).precomposedStringWithCanonicalMapping
    }

    public static func toAcute(_ w: String) -> String {
        String(String.UnicodeScalarView(w.decomposedStringWithCanonicalMapping.unicodeScalars
            .map { $0 == "\u{0300}" ? "\u{0301}" : $0 })).precomposedStringWithCanonicalMapping
    }

    /// Lexicon lookup form for a committed word (bigram `prev` side).
    public static func normalise(_ w: String) -> String {
        Marks.stripMacrons(toAcute(w)).lowercased()
    }

    /// σ at the end of a word becomes ς (for literal, unknown words).
    public static func finalSigma(_ w: String) -> String {
        guard w.hasSuffix("σ") else { return w }
        return String(w.dropLast()) + "ς"
    }
}

/// Manual diacritic entry: the keyboard's mark keys apply to the letter just
/// typed (postfix, like a combining character), toggling it on and off.
public enum MarkKey: String, CaseIterable, Sendable {
    case macron = "\u{0304}", breve = "\u{0306}", diaeresis = "\u{0308}"
    case acute = "\u{0301}", grave = "\u{0300}", circumflex = "\u{0342}"
    case smooth = "\u{0313}", rough = "\u{0314}", iotaSubscript = "\u{0345}"

    var scalar: Unicode.Scalar { rawValue.unicodeScalars.first! }

    /// Marks that cannot coexist on one letter (setting one clears the others).
    var rivals: Set<Unicode.Scalar> {
        switch self {
        case .acute, .grave, .circumflex: return ["\u{0301}", "\u{0300}", "\u{0342}"]
        case .smooth, .rough: return ["\u{0313}", "\u{0314}"]
        case .macron, .breve: return ["\u{0304}", "\u{0306}"]
        default: return [scalar]
        }
    }

    /// Spacing glyph for the key cap.
    public var label: String {
        switch self {
        case .macron: return "¯"; case .breve: return "˘"; case .diaeresis: return "¨"
        case .acute: return "´"; case .grave: return "`"; case .circumflex: return "῀"
        case .smooth: return "᾿"; case .rough: return "῾"; case .iotaSubscript: return "ͺ"
        }
    }

    /// Toggle this mark on `ch`. Returns nil if `ch` is not a letter.
    public func toggle(on ch: Character) -> Character? {
        guard ch.isLetter else { return nil }
        var u = Array(String(ch).decomposedStringWithCanonicalMapping.unicodeScalars)
        let base = u.removeFirst()
        if u.contains(scalar) {
            u.removeAll { $0 == scalar }
        } else {
            u.removeAll { rivals.contains($0) }
            // quantity sits closest to the letter, then breathing, then accent
            let order: [Unicode.Scalar] = ["\u{0304}", "\u{0306}", "\u{0308}", "\u{0313}", "\u{0314}",
                                           "\u{0301}", "\u{0300}", "\u{0342}", "\u{0345}"]
            u.append(scalar)
            u.sort { (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99) }
        }
        let s = String(String.UnicodeScalarView([base] + u)).precomposedStringWithCanonicalMapping
        return s.count == 1 ? s.first : nil
    }
}
