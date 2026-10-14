import ClassicalKeyboardEngine
import UIKit

enum KeyKind: Equatable {
    case char(String)
    case shift, backspace, space, enter, globe
    case layer(Layer)
    case mark(MarkKey)            // postfix diacritic on the previous letter
}

enum Layer: Equatable { case letters, symbols }

struct KeySpec {
    let kind: KeyKind
    var width: CGFloat = 1        // in letter-key units
    var label: String? = nil
    /// Long-press alternatives (first one is preselected).
    var variants: [String] = []

    var isFunction: Bool {
        if case .char = kind { return false }
        if case .mark = kind { return false }
        return true
    }
}

enum KeyLayouts {
    // Long-press menus. Latin: the macron first; no breves (short is unmarked).
    static let latinVariants: [String: [String]] = [
        "a": ["ā", "æ", "ä"], "e": ["ē", "ë"], "i": ["ī", "ï", "j"],
        "o": ["ō", "œ", "ö"], "u": ["ū", "ü", "v"], "y": ["ȳ", "ÿ"],
    ]
    // Greek: the dichrona get macron/breve first; every vowel offers breathings and accents.
    static let greekVariants: [String: [String]] = [
        "α": ["ᾱ", "ᾰ", "ἀ", "ἁ", "ά", "ᾶ", "ᾳ"],
        "ι": ["ῑ", "ῐ", "ἰ", "ἱ", "ί", "ῖ", "ϊ"],
        "υ": ["ῡ", "ῠ", "ὐ", "ὑ", "ύ", "ῦ", "ϋ"],
        "ε": ["ἐ", "ἑ", "έ"], "ο": ["ὀ", "ὁ", "ό"],
        "η": ["ἠ", "ἡ", "ή", "ῆ", "ῃ"], "ω": ["ὠ", "ὡ", "ώ", "ῶ", "ῳ"],
        "ρ": ["ῥ", "ῤ"], "σ": ["ς", "ϲ"], ";": ["·", "’"],
    ]

    static func rows(_ lang: Language, _ layer: Layer, globe: Bool) -> [[KeySpec]] {
        if layer == .symbols { return symbols(lang, globe: globe) }
        let v = lang == .latin ? latinVariants : greekVariants
        func letters(_ s: String) -> [KeySpec] {
            s.map { KeySpec(kind: .char(String($0)), variants: v[String($0)] ?? []) }
        }
        var bottom: [KeySpec] = [KeySpec(kind: .layer(.symbols), width: 1.25, label: "123")]
        if globe { bottom.append(KeySpec(kind: .globe, width: 1.25, label: "🌐")) }
        switch lang {
        case .latin:
            bottom += [KeySpec(kind: .mark(.macron), width: 1, label: "¯",
                               variants: ["◌\u{0308}"]),
                       KeySpec(kind: .space, width: globe ? 4.0 : 5.25, label: "spatium"),
                       KeySpec(kind: .char("."), width: 1, variants: [",", ";", ":", "?", "!"]),
                       KeySpec(kind: .enter, width: 1.75, label: "⏎")]
            return [letters("qwertyuiop"),
                    letters("asdfghjkl"),
                    [KeySpec(kind: .shift, width: 1.5, label: "⇧")] + letters("zxcvbnm")
                        + [KeySpec(kind: .backspace, width: 1.5, label: "⌫")],
                    bottom]
        case .greek:
            // macron key + a diacritics key whose long-press menu holds the rest
            bottom += [KeySpec(kind: .mark(.macron), width: 1, label: "¯"),
                       KeySpec(kind: .mark(.acute), width: 1, label: "´",
                               variants: [MarkKey.grave, .circumflex, .smooth, .rough, .iotaSubscript, .breve, .diaeresis]
                                   .map { "◌" + $0.rawValue }),
                       KeySpec(kind: .space, width: globe ? 3.0 : 4.25, label: "διάστημα"),
                       KeySpec(kind: .char("."), width: 1, variants: [",", "·", ";", "’", "!"]),
                       KeySpec(kind: .enter, width: 1.5, label: "⏎")]
            return [letters(";ςερτυθιοπ"),
                    letters("ασδφγηξκλ"),
                    [KeySpec(kind: .shift, width: 1.5, label: "⇧")] + letters("ζχψωβνμ")
                        + [KeySpec(kind: .backspace, width: 1.5, label: "⌫")],
                    bottom]
        }
    }

    static func symbols(_ lang: Language, globe: Bool) -> [[KeySpec]] {
        func chars(_ s: [String]) -> [KeySpec] { s.map { KeySpec(kind: .char($0)) } }
        let mid = lang == .greek
            ? ["-", "/", ":", "·", "(", ")", "«", "»", "—", "\""]
            : ["-", "/", ":", ";", "(", ")", "«", "»", "—", "\""]
        var bottom: [KeySpec] = [KeySpec(kind: .layer(.letters), width: 1.25, label: lang == .latin ? "ABC" : "ΑΒΓ")]
        if globe { bottom.append(KeySpec(kind: .globe, width: 1.25, label: "🌐")) }
        bottom += [KeySpec(kind: .space, width: globe ? 5.0 : 6.25, label: " "),
                   KeySpec(kind: .enter, width: 1.75, label: "⏎")]
        return [chars(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]),
                chars(mid),
                chars([".", ",", "?", "!", "’", "†", "§", "&"]) + [KeySpec(kind: .backspace, width: 1.5, label: "⌫")],
                bottom]
    }
}
