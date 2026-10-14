import XCTest
@testable import ClassicalKeyboardEngine

private let out = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("../../../out").standardized

/// Plays keystrokes through a Composer into a fake text buffer.
final class ComposerTests: XCTestCase {
    private func lexicon(_ name: String) throws -> Lexicon {
        let p = out.appendingPathComponent(name).path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: p))
        return try Lexicon(path: p)
    }

    /// Greek keys use Beta-Code style: letters as Greek, / \ = ( ) | _ as marks.
    private func type(_ c: Composer, _ s: String) -> String {
        var doc = ""
        let marks: [Character: MarkKey] = ["/": .acute, "\\": .grave, "=": .circumflex, "(": .rough,
                                           ")": .smooth, "|": .iotaSubscript, "_": .macron, "^": .breve, "+": .diaeresis]
        for ch in s {
            let key: Composer.Key
            switch ch {
            case " ": key = .space
            case "⌫": key = .backspace
            case "⎋": key = .escape
            case "⇥": key = .tab
            case ",", ".", "·", ";", "?": key = .punctuation(String(ch))
            // dead keys (prefix), written as their spacing glyphs; "~" = the Māori-style ` key
            case "´": key = .dead([.acute], raw: ";")
            case "῾": key = .dead([.rough], raw: "\"")
            case "᾿": key = .dead([.smooth], raw: "'")
            case "῀": key = .dead([.circumflex], raw: "[")
            case "ͺ": key = .dead([.iotaSubscript], raw: "{")
            case "~": key = .dead([.macron], raw: "`")
            case "’": key = .apostrophe
            default: key = marks[ch].map { .mark($0) } ?? .letter(ch)
            }
            if let e = c.handle(key).edit {
                XCTAssertTrue(doc.hasSuffix(e.replace), "expected …\(e.replace) in \(doc)")
                doc = String(doc.dropLast(e.replace.count)) + e.with
            }
        }
        return doc + c.buffer
    }

    func testGreekSentence() throws {
        let c = Composer(predictor: Predictor(lexicon: try lexicon("greek.lex")))
        XCTAssertEqual(type(c, "εν αρχη ην ο λογος."), "ἐν ἀρχῇ ἦν ὁ λόγος.")
    }

    func testGraveRevertedByPunctuation() throws {
        let c = Composer(predictor: Predictor(lexicon: try lexicon("greek.lex")))
        XCTAssertEqual(type(c, "καλος ανηρ."), "κᾱλὸς ἀνήρ.")   // Attic κᾱλός: long alpha
        c.reset()
        XCTAssertEqual(type(c, "καλος."), "κᾱλός.")                 // last word: stays acute
        c.reset()
        XCTAssertEqual(type(c, "ψυχη "), "ψῡχή ")                   // nothing follows yet: acute
    }

    func testBetaCodeMarks() throws {
        let c = Composer(predictor: Predictor(lexicon: try lexicon("greek.lex")))
        XCTAssertEqual(type(c, "α_"), "ᾱ")
        c.reset()
        XCTAssertEqual(type(c, "ω=|⎋"), "ῷ")
    }

    func testLatinMacronsAndUndo() throws {
        let p = Predictor(lexicon: try lexicon("latin.lex"))
        p.latinStyle.macrons = true
        let c = Composer(predictor: p)
        XCTAssertEqual(type(c, "arma virumque cano troiae "), "arma virumque canō Trōiae ")
        c.reset()
        XCTAssertEqual(type(c, "amivus ⌫"), "amivus")             // backspace undoes the correction
        c.reset()
        XCTAssertEqual(type(c, "ro_sa_ "), "rōsā ")                  // typed macrons are kept as typed
    }

    func testEncliticAccents() throws {
        let c = Composer(predictor: Predictor(lexicon: try lexicon("greek.lex")))
        XCTAssertEqual(type(c, "ανθρωπος τις."), "ἄνθρωπός τις.")
        c.reset()
        XCTAssertEqual(type(c, "λογος τις."), "λόγος τις.")
    }

    func testDeadKeysAndElision() throws {
        let c = Composer(predictor: Predictor(lexicon: try lexicon("greek.lex")))
        XCTAssertEqual(type(c, "῾´ο⎋"), "ὅ")                        // rough + acute before the vowel
        c.reset()
        XCTAssertEqual(type(c, "ͺ῀ω⎋"), "ῷ")
        c.reset()
        XCTAssertEqual(type(c, "δ᾿ αν."), "δ’ ἄν.")                // smooth dead key + space = elision
        c.reset()
        XCTAssertEqual(type(c, "αλλ’ "), "ἀλλ’ ")
        c.reset()
        XCTAssertEqual(type(c, "´ "), ";")                          // dead key + space = its own character
    }

    func testMaoriMacron() throws {
        let p = Predictor(lexicon: try lexicon("latin.lex"))
        p.latinStyle.macrons = true
        let c = Composer(predictor: p)
        XCTAssertEqual(type(c, "ros~a "), "rosā ")
        c.reset()
        XCTAssertEqual(type(c, "~~"), "`")                          // pressed twice: the backtick itself
    }

    func testPunctuationAfterSpace() throws {
        let p = Predictor(lexicon: try lexicon("latin.lex"))
        let c = Composer(predictor: p)
        XCTAssertEqual(type(c, "arma , virumque ."), "arma, virumque. ")
        c.reset()
        XCTAssertEqual(type(c, "arma,"), "arma,")                    // typed directly: unchanged
    }

    func testPaging() throws {
        let c = Composer(predictor: Predictor(lexicon: try lexicon("greek.lex")))
        _ = type(c, "λογ")
        XCTAssertGreaterThan(c.pageCount, 1, "\(c.candidates)")
        XCTAssertEqual(c.pageCandidates.count, Composer.pageSize)
        _ = c.handle(.nextPage)
        XCTAssertEqual(c.page, 1)
        let first = c.pageCandidates[0]
        let e = c.handle(.choose(1)).edit                               // number = position on this page
        XCTAssertEqual(e?.with, Greek.finalSigma(first) + " ")
    }

    func testTabCyclesCandidates() throws {
        let c = Composer(predictor: Predictor(lexicon: try lexicon("greek.lex")))
        _ = type(c, "η")
        XCTAssertGreaterThan(c.candidates.count, 2)
        let second = c.candidates[1]
        XCTAssertEqual(type(c, "⇥ ").trimmingCharacters(in: .whitespaces), Greek.toGrave(second))
    }
}
