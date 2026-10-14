import Foundation

public enum Language: String, Sendable {
    case latin = "la"
    case greek = "grc"
}

/// Typing keys. Must stay byte-for-byte compatible with `lkey` / `gkey` in
/// tools/build_lexicon.py (and grc.py), or lookups silently miss.
public enum Folding {
    /// NFD, then drop every nonspacing mark (accents, breathings, macrons,
    /// iota subscript, diaeresis).
    static func stripMarks(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.decomposedStringWithCanonicalMapping.unicodeScalars
        where u.properties.generalCategory != .nonspacingMark {
            out.append(u)
        }
        return String(out)
    }

    /// rōsā / Rosa / ROSA → rosa ;  vīvō → uiuo ;  jūs → ius ;  cælum → caelum
    public static func latinKey(_ s: String) -> String {
        var out = ""
        for ch in stripMarks(s.lowercased()) {
            switch ch {
            case "æ": out += "ae"
            case "œ": out += "oe"
            case "j": out.append("i")
            case "v": out.append("u")
            case "a"..."z": out.append(ch)
            default: return ""
            }
        }
        return out
    }

    /// ἄνθρωπος / ΑΝΘΡΩΠΟΣ / ανθρωπος → ανθρωποσ  (final sigma folded to σ)
    public static func greekKey(_ s: String) -> String {
        var out = ""
        for ch in stripMarks(s.lowercased()) {
            switch ch {
            case "ς", "ϲ": out.append("σ")
            case "α"..."ω", "ϝ", "ϟ", "ϡ": out.append(ch)
            default: continue          // elision mark, apostrophes, etc.
            }
        }
        return out
    }

    public static func key(_ s: String, _ lang: Language) -> String {
        lang == .latin ? latinKey(s) : greekKey(s)
    }

    /// Letters the corrector may insert / substitute.
    static func alphabet(_ lang: Language) -> [Character] {
        switch lang {
        case .latin: return Array("abcdefghiklmnopqrstuxyz")      // j, v fold away; w is rare
        case .greek: return Array("αβγδεζηθικλμνξοπρστυφχψω")
        }
    }
}
