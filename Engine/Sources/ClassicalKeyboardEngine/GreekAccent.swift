import Foundation

/// Accent changes between two adjacent Greek words, applied when the second
/// word is committed (never earlier: whether a grave is right depends on
/// what follows).
///
///   καλός + ἀνήρ   → καλὸς ἀνήρ        oxytone before a word: grave
///   καλός + ,      → καλός,             (no next word: nothing happens)
///   καλός + ἐστί   → καλός ἐστι         oxytone keeps acute before an enclitic,
///                                       the enclitic loses its accent
///   ἄνθρωπος + τις → ἄνθρωπός τις       proparoxytone: second acute on the last syllable
///   δῶρον + τι     → δῶρόν τι           properispomenon: same
///   λόγος + ἐστί   → λόγος ἐστί         paroxytone + disyllabic enclitic: enclitic keeps it
extension Greek {
    public enum AccentKind { case acute, grave, circumflex }

    static let acute: Unicode.Scalar = "\u{0301}", grave: Unicode.Scalar = "\u{0300}", circ: Unicode.Scalar = "\u{0342}"
    static let diaeresis: Unicode.Scalar = "\u{0308}"
    static let diphthongs: Set<String> = ["αι", "ει", "οι", "υι", "αυ", "ευ", "ηυ", "ου", "ωυ"]

    /// Letters + marks, one entry per base letter.
    private static func letters(_ w: String) -> [(base: Character, marks: [Unicode.Scalar])] {
        var out: [(Character, [Unicode.Scalar])] = []
        for u in w.decomposedStringWithCanonicalMapping.unicodeScalars {
            if u.properties.generalCategory == .nonspacingMark, !out.isEmpty { out[out.count - 1].1.append(u) }
            else { out.append((Character(String(u)), [])) }
        }
        return out
    }

    /// Syllable nuclei as index ranges into `letters`, last syllable last.
    private static func nuclei(_ ls: [(base: Character, marks: [Unicode.Scalar])]) -> [[Int]] {
        var out: [[Int]] = []
        var i = 0
        while i < ls.count {
            let c = Character(ls[i].base.lowercased())
            guard vowels.contains(c) else { i += 1; continue }
            if i + 1 < ls.count {
                let d = Character(ls[i + 1].base.lowercased())
                // a diphthong unless the first vowel carries the accent/breathing or the second a diaeresis
                let firstBare = ls[i].marks.allSatisfy { $0 == "\u{0304}" }
                if diphthongs.contains(String([c, d])) && firstBare && !ls[i + 1].marks.contains(diaeresis) {
                    out.append([i, i + 1]); i += 2; continue
                }
            }
            out.append([i]); i += 1
        }
        return out
    }

    /// Accent position counted from the end (1 = ultima) and its kind.
    public static func accent(_ w: String) -> (fromEnd: Int, kind: AccentKind)? {
        let ls = letters(w), ns = nuclei(ls)
        for (k, n) in ns.enumerated().reversed() {
            for i in n {
                if ls[i].marks.contains(acute) { return (ns.count - k, .acute) }
                if ls[i].marks.contains(grave) { return (ns.count - k, .grave) }
                if ls[i].marks.contains(circ) { return (ns.count - k, .circumflex) }
            }
        }
        return nil
    }

    static func syllableCount(_ w: String) -> Int { nuclei(letters(w)).count }

    private static func rebuild(_ ls: [(base: Character, marks: [Unicode.Scalar])]) -> String {
        var s = String.UnicodeScalarView()
        for (b, m) in ls { s.append(contentsOf: String(b).unicodeScalars); s.append(contentsOf: m) }
        return String(s).precomposedStringWithCanonicalMapping
    }

    /// ἄνθρωπος → ἄνθρωπός : acute on the last vowel of the final syllable.
    static func addFinalAcute(_ w: String) -> String {
        var ls = letters(w)
        guard let last = nuclei(ls).last?.last else { return w }
        if !ls[last].marks.contains(acute) { ls[last].marks.append(acute) }
        return rebuild(ls)
    }

    static func stripAccents(_ w: String) -> String {
        var ls = letters(w)
        for i in ls.indices { ls[i].marks.removeAll { $0 == acute || $0 == grave || $0 == circ } }
        return rebuild(ls)
    }

    // Unaccented enclitics (pronouns, indefinites, particles), by key.
    static let enclitics: Set<String> = [
        "μου", "μοι", "με", "σου", "σοι", "σε", "του", "τω", "τισ", "τι", "τινοσ", "τινι", "τινα",
        "τινεσ", "τινων", "τισι", "τισιν", "τινασ", "πωσ", "που", "ποι", "ποθεν", "ποτε", "πη", "πω",
        "τε", "γε", "τοι", "περ", "νυν", "θην", "κε", "κεν", "ρα", "νυ", "μιν", "νιν", "σφισι", "σφισιν",
    ]
    // Present indicative of εἰμί / φημί: enclitic when accented on the ultima (ἐστί), or not at all.
    static let encliticVerbs: Set<String> = [
        "ειμι", "εστι", "εστιν", "εστον", "εσμεν", "εστε", "εισι", "εισιν",
        "φημι", "φησι", "φησιν", "φατον", "φαμεν", "φατε", "φασι", "φασιν",
    ]

    public static func isEnclitic(_ w: String) -> Bool {
        let k = Folding.greekKey(w)
        let a = accent(w)
        if encliticVerbs.contains(k) { return a == nil || a!.fromEnd == 1 }
        return enclitics.contains(k) && a == nil
    }

    /// Adjust the accents of `prev` (already in the text, acute form) and `next`
    /// (being committed) for each other.
    public static func join(_ prev: String, _ next: String) -> (prev: String, next: String) {
        guard let pa = accent(prev) else { return (prev, next) }    // proclitic / unaccented
        if isEnclitic(next) {
            switch (pa.fromEnd, pa.kind) {
            case (1, .acute), (1, .grave):                         // καλός ἐστι
                return (toAcute(prev), stripAccents(next))
            case (1, .circumflex):                                 // τιμῶν ἐστι
                return (prev, stripAccents(next))
            case (3, .acute), (2, .circumflex):                    // ἄνθρωπός τις, δῶρόν ἐστι
                return (addFinalAcute(prev), stripAccents(next))
            default:                                               // λόγος τις / λόγος ἐστί
                return (prev, syllableCount(next) >= 2 ? next : stripAccents(next))
            }
        }
        return (toGrave(prev), next)
    }
}
