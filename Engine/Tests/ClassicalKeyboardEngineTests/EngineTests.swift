import XCTest
@testable import ClassicalKeyboardEngine

private let out = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("../../../out").standardized

final class FoldingTests: XCTestCase {
    func testLatinKey() {
        XCTAssertEqual(Folding.latinKey("Rōsā"), "rosa")
        XCTAssertEqual(Folding.latinKey("vīvō"), "uiuo")
        XCTAssertEqual(Folding.latinKey("jūs"), "ius")
        XCTAssertEqual(Folding.latinKey("cælum"), "caelum")
        XCTAssertEqual(Folding.latinKey("abc1"), "")
    }

    func testGreekKey() {
        XCTAssertEqual(Folding.greekKey("ἄνθρωπος"), "ανθρωποσ")
        XCTAssertEqual(Folding.greekKey("ΑΝΘΡΩΠΟΣ"), "ανθρωποσ")
        XCTAssertEqual(Folding.greekKey("ζῷον"), "ζωον")
        XCTAssertEqual(Folding.greekKey("δ’"), "δ")
    }

    func testGrave() {
        XCTAssertEqual(Greek.toGrave("καλός"), "καλὸς")
        XCTAssertEqual(Greek.toGrave("λόγος"), "λόγος")       // paroxytone: unchanged
        XCTAssertEqual(Greek.toGrave("αὐτοί"), "αὐτοὶ")
        XCTAssertEqual(Greek.toGrave("τοῖς"), "τοῖς")         // circumflex: unchanged
        XCTAssertEqual(Greek.toGrave("τίς"), "τίς")           // interrogative
        XCTAssertEqual(Greek.toGrave("χώρᾳ"), "χώρᾳ")         // ᾳ still holds a vowel
        XCTAssertEqual(Greek.toGrave("θεᾱ́"), "θεᾱ̀")            // macron + accent
        XCTAssertEqual(Greek.toAcute("καλὸς"), "καλός")
        XCTAssertEqual(Greek.finalSigma("λογοσ"), "λογος")
    }

    func testAccentJoin() {
        XCTAssertEqual(Greek.join("καλός", "ἀνήρ").prev, "καλὸς")
        XCTAssertEqual(Greek.join("καλός", "ἐστί").prev, "καλός")
        XCTAssertEqual(Greek.join("καλός", "ἐστί").next, "ἐστι")
        XCTAssertEqual(Greek.join("ἄνθρωπος", "τις").prev, "ἄνθρωπός")
        XCTAssertEqual(Greek.join("δῶρον", "τι").prev, "δῶρόν")
        XCTAssertEqual(Greek.join("ἄνθρωποι", "τινες").prev, "ἄνθρωποί")
        XCTAssertEqual(Greek.join("λόγος", "ἐστί").next, "ἐστί")      // paroxytone + disyllable
        XCTAssertEqual(Greek.join("λόγος", "τις").prev, "λόγος")
        XCTAssertEqual(Greek.join("ὁ", "ἀνήρ").prev, "ὁ")              // proclitic: nothing
        XCTAssertEqual(Greek.join("τίς", "ἀνήρ").prev, "τίς")          // interrogative keeps acute
        XCTAssertEqual(Greek.accent("ἀΐδιος")?.fromEnd, 3)             // diaeresis splits αι
    }

    func testTypedMarks() {
        XCTAssertTrue(Marks.consistent(typed: "rosā", candidate: "rosā"))
        XCTAssertFalse(Marks.consistent(typed: "rosā", candidate: "rōsā"))   // typed o is short
        XCTAssertTrue(Marks.consistent(typed: "ἀν", candidate: "ἄνθρωπος"))  // breathing only
        XCTAssertTrue(Marks.consistent(typed: "ᾰνηρ", candidate: "ἀνήρ"))    // breve = unmarked
        XCTAssertEqual(Marks.stripMacrons("πρᾱ́ττω"), "πράττω")
    }

    func testMarkKeys() {
        XCTAssertEqual(MarkKey.macron.toggle(on: "a"), "ā")
        XCTAssertEqual(MarkKey.macron.toggle(on: "ā"), "a")              // toggles off
        XCTAssertEqual(MarkKey.macron.toggle(on: "α"), "ᾱ")
        XCTAssertEqual(MarkKey.acute.toggle(on: "ᾱ").map(String.init), "ᾱ́")
        XCTAssertEqual(MarkKey.rough.toggle(on: "ἀ"), "ἁ")               // breathing replaces breathing
        XCTAssertEqual(MarkKey.circumflex.toggle(on: "ά"), "ᾶ")          // accent replaces accent
        XCTAssertEqual(MarkKey.iotaSubscript.toggle(on: "ῶ"), "ῷ")
        XCTAssertNil(MarkKey.acute.toggle(on: "1"))
    }

    func testLatinStyle() {
        XCTAssertEqual(LatinStyle(macrons: false).apply("prīmus"), "primus")
        XCTAssertEqual(LatinStyle(macrons: true).apply("prīmus"), "prīmus")
        XCTAssertEqual(LatinStyle(consonantalV: false).apply("virtūs"), "uirtus")
        XCTAssertEqual(LatinStyle(consonantalJ: true).apply("iam"), "jam")
        XCTAssertEqual(LatinStyle(consonantalJ: true).apply("maior"), "major")
    }

    func testAdjacency() {
        XCTAssertTrue(Layout.latin.adjacent("v", "c"))
        XCTAssertFalse(Layout.latin.adjacent("q", "p"))
        XCTAssertTrue(Layout.greek.adjacent("ο", "π"))
    }
}

final class PredictorTests: XCTestCase {
    var latin: Predictor!
    var greek: Predictor!

    override func setUpWithError() throws {
        let l = out.appendingPathComponent("latin.lex").path, g = out.appendingPathComponent("greek.lex").path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: l) && FileManager.default.fileExists(atPath: g),
                          "run tools/build_lexicon.py first")
        latin = Predictor(lexicon: try Lexicon(path: l))
        greek = Predictor(lexicon: try Lexicon(path: g))
    }

    private func ac(_ p: Predictor, _ prev: String?, _ typed: String) -> String {
        p.predict(previous: prev, typed: typed).autocorrect?.text ?? typed
    }

    func testGreekAccentRestoration() {
        XCTAssertEqual(ac(greek, nil, "ανθρωπος"), "ἄνθρωπος")
        XCTAssertEqual(ac(greek, nil, "λογοσ"), "λόγος")
        XCTAssertEqual(ac(greek, nil, "ζωον"), "ζῷον")
        XCTAssertEqual(ac(greek, "ἐν", "αρχη"), "ἀρχῇ")             // bigram picks the dative
    }

    func testGreekMacrons() {
        XCTAssertEqual(ac(greek, nil, "πραττειν"), "πρᾱ́ττειν")
        greek.greekStyle.quantities = false
        XCTAssertEqual(ac(greek, nil, "πραττειν"), "πράττειν")
        XCTAssertEqual(ac(greek, nil, "πρᾱττειν"), "πρᾱ́ττειν")    // a typed macron wins
    }

    func testGreekDoesNotTouchEnclitic() {
        XCTAssertEqual(ac(greek, "ἄνδρα", "μοι"), "μοι")
    }

    func testLatinCorrection() {
        XCTAssertEqual(ac(latin, nil, "amivus"), "amicus")
        XCTAssertEqual(ac(latin, nil, "virtitem"), "virtutem")
        XCTAssertEqual(ac(latin, nil, "est"), "est")                // valid words are left alone
    }

    func testLatinMacronsAndEnclitics() {
        latin.latinStyle.macrons = true
        XCTAssertEqual(ac(latin, nil, "primus"), "prīmus")
        let enc = ac(latin, nil, "regnaue")                           // rēgna+ve or regnā+ve: both real
        XCTAssertTrue(enc.hasSuffix("ve") && Folding.latinKey(enc) == "regnaue", enc)
        XCTAssertEqual(ac(latin, nil, "partes"), "partēs")
        XCTAssertEqual(ac(latin, nil, "tres"), "trēs")
        XCTAssertEqual(ac(latin, nil, "rosā"), "rosā")                 // not rōsā
    }

    func testNextWord() {
        let s = greek.predict(previous: "καί", typed: "").suggestions.map(\.text)
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(s.allSatisfy { $0 == $0.lowercased() }, "\(s)")
    }

    func testUserLearning() {
        XCTAssertEqual(ac(latin, nil, "Harumotus"), "Harumotus")       // nothing close: left alone
        XCTAssertEqual(ac(latin, nil, "amivus"), "amicus")
        latin.user.protect("amivus")                                   // user undid the correction
        XCTAssertEqual(ac(latin, nil, "amivus"), "amivus")
    }
}
