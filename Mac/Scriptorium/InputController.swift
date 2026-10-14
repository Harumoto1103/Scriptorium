import Carbon
import ClassicalKeyboardEngine
import Cocoa
import InputMethodKit

/// Engines are shared by every client (one mmapped lexicon each, one user model).
enum Engines {
    static let latin: Predictor? = load("latin", .latin)
    static let greek: Predictor? = load("greek", .greek)

    static func load(_ name: String, _ lang: Language) -> Predictor? {
        guard let path = Bundle.main.path(forResource: name, ofType: "lex"),
              let lex = try? Lexicon(path: path) else { return nil }
        return Predictor(lexicon: lex, user: UserModel.load(from: userURL(lang)))
    }

    static func userURL(_ lang: Language) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scriptorium", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user-\(lang.rawValue).json")
    }

    static func save() {
        if let p = latin { try? p.user.save(to: userURL(.latin)) }
        if let p = greek { try? p.user.save(to: userURL(.greek)) }
    }

    static func applySettings() {
        let d = UserDefaults.standard
        func flag(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
        for p in [latin, greek].compactMap({ $0 }) {
            p.autocorrectEnabled = flag("autocorrect", true)
            p.latinStyle = LatinStyle(macrons: flag("latinMacrons", true),
                                      consonantalV: flag("latinConsonantalV", true),
                                      consonantalJ: flag("latinJ", false))
            p.greekStyle = GreekStyle(quantities: flag("greekQuantities", true))
        }
    }
}

/// Apple's Greek layout on a US keyboard: u → θ, j → ξ, c → ψ, v → ω, w → ς, q → ;
private let greekKeys: [Character: Character] = [
    "a": "α", "b": "β", "c": "ψ", "d": "δ", "e": "ε", "f": "φ", "g": "γ", "h": "η", "i": "ι",
    "j": "ξ", "k": "κ", "l": "λ", "m": "μ", "n": "ν", "o": "ο", "p": "π", "r": "ρ", "s": "σ",
    "t": "τ", "u": "θ", "v": "ω", "w": "ς", "x": "χ", "y": "υ", "z": "ζ",
]

/// Apple's Greek Polytonic layout: dead keys typed *before* the vowel
/// (read from com.apple.keylayout.GreekPolytonic with UCKeyTranslate).
private let applePolytonic: [Character: [MarkKey]] = [
    ";": [.acute], "]": [.grave], "}": [.grave], "[": [.circumflex], "{": [.iotaSubscript],
    "'": [.smooth], "\"": [.rough],
    "/": [.smooth, .acute], "?": [.rough, .acute],
    "=": [.smooth, .grave], "+": [.rough, .grave],
    "-": [.smooth, .circumflex], "_": [.rough, .circumflex],
    ":": [.diaeresis], "W": [.diaeresis, .acute],
]

/// Beta-Code postfix marks, typed *after* the letter (menu option for Greek).
private let betaCode: [Character: MarkKey] = [
    "/": .acute, "\\": .grave, "=": .circumflex, ")": .smooth, "(": .rough,
    "|": .iotaSubscript, "_": .macron, "^": .breve, "+": .diaeresis,
]
/// Latin postfix marks: macron and diaeresis only (no breves).
private let latinMarks: [Character: MarkKey] = ["_": .macron, "+": .diaeresis]

@objc(InputController)
final class InputController: IMKInputController {
    private var language: Language = .latin
    private var composer: Composer?
    private static let panel = CandidatePanel()

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        Engines.applySettings()
        detectMode()
    }

    // MARK: modes

    private func detectMode() {
        if let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let raw = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
            setLanguage(id.hasSuffix(".Greek") ? .greek : .latin)
        } else {
            setLanguage(.latin)
        }
    }

    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        if tag == kTextServiceInputModePropertyTag, let id = value as? String {
            commitLiteral(sender)
            setLanguage(id.hasSuffix(".Greek") ? .greek : .latin)
        }
    }

    private func setLanguage(_ l: Language) {
        guard composer == nil || l != language else { return }
        language = l
        if let p = (l == .latin ? Engines.latin : Engines.greek) {
            composer = Composer(predictor: p)
            composer?.autoGrave = UserDefaults.standard.object(forKey: "greekAutoGrave") as? Bool ?? true
        }
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        Engines.applySettings()
        detectMode()
    }

    override func deactivateServer(_ sender: Any!) {
        commitLiteral(sender)
        Self.panel.orderOut(nil)
        Engines.save()
        super.deactivateServer(sender)
    }

    /// Focus moved / mouse click: keep what was typed, verbatim.
    override func commitComposition(_ sender: Any!) { commitLiteral(sender) }

    private func commitLiteral(_ sender: Any!) {
        guard let c = composer, c.isComposing, let client = sender as? IMKTextInput else {
            composer?.reset(); return
        }
        var lit = c.reset()
        if language == .greek { lit = Greek.finalSigma(lit) }
        client.insertText(lit, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
        Self.panel.orderOut(nil)
    }

    // MARK: keys

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard event.type == .keyDown, let client = sender as? IMKTextInput, let c = composer else { return false }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        let composing = c.isComposing
        let betaMode = UserDefaults.standard.bool(forKey: "greekBetaCode")

        // while composing, arrows walk the candidate bar (→ ↓ next, ← ↑ previous)
        if composing && mods.isEmpty {
            switch event.keyCode {
            case 124, 125: apply(c.handle(.tab), client); return true
            case 123, 126: apply(c.handle(.previous), client); return true
            case 48 where event.modifierFlags.contains(.shift): apply(c.handle(.previous), client); return true
            default: break
            }
        }

        // Option keys that are marks on Apple's Polytonic layout: ⌥⇧L macron, ⌥L breve, ⌥I iota subscript;
        // ⌥; ano teleia
        if mods == .option, language == .greek, !betaMode {
            let shift = event.modifierFlags.contains(.shift)
            switch event.keyCode {
            case 37: apply(c.handle(.dead(shift ? [.macron] : [.breve], raw: shift ? "¯" : "˘")), client); return true
            case 34: apply(c.handle(.dead([.iotaSubscript], raw: "ͺ")), client); return true
            case 41: apply(c.handle(.punctuation("·")), client); return true
            default: break
            }
        }

        // shortcuts, option-characters, arrows, Home/End/PgUp/PgDn: settle the word, let the app have the key
        if !mods.isEmpty || [123, 124, 125, 126, 115, 119, 116, 121, 117].contains(event.keyCode) {
            if composing { commitLiteral(client) } else { c.reset() }
            return false
        }

        let key: Composer.Key
        switch event.keyCode {
        case 36, 76: key = .enter
        case 48: key = .tab
        case 51: key = .backspace
        case 53: key = .escape
        case 49: key = .space
        default:
            guard let ch = event.characters?.first else { return false }
            let lower = Character(ch.lowercased())
            let greekDead = language == .greek && !betaMode ? applePolytonic[ch] : nil
            let postfix = language == .greek ? (betaMode ? betaCode : [:]) : latinMarks
            if ch == "`" {
                key = .dead([.macron], raw: "`")         // Māori-style macron, both languages
            } else if let marks = greekDead {
                key = .dead(marks, raw: String(ch))
            } else if language == .greek, ch == "'" || ch == "’" {
                key = .apostrophe                       // Beta-Code mode: elision
            } else if !c.buffer.isEmpty, let m = postfix[ch] {
                key = .mark(m)
            } else if composing, let n = ch.wholeNumberValue, (1...9).contains(n) {
                key = .choose(n)
            } else if language == .greek, ch.isASCII, lower == "q" {
                key = .punctuation(ch.isUppercase ? ":" : ";")
            } else if language == .greek, ch.isASCII, let g = greekKeys[lower] {
                key = .letter(ch.isUppercase ? Character(g.uppercased()) : g)
            } else if ch.isLetter {
                key = .letter(ch)
            } else if ch.isNumber && !composing {
                return false
            } else if language == .greek && ch == ";" {
                key = .punctuation("·")              // Beta-Code mode: ; is the ano teleia
            } else if !ch.isWhitespace && !ch.isNewline && ch.unicodeScalars.first!.value >= 0x20 {
                key = .punctuation(String(ch))
            } else {
                return false
            }
        }

        let r = c.handle(key)
        apply(r, client)
        return !r.passThrough           // enter: we committed, the app still gets its newline
    }

    private func apply(_ r: Composer.Response, _ client: IMKTextInput) {
        if let e = r.edit {
            if e.replace.isEmpty {
                client.insertText(e.with, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
            } else {
                // the new word is still marked text: drop it first, then rewrite the
                // previous word + the new one in one go (accent join, undo)
                client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
                let sel = client.selectedRange()
                let len = (e.replace as NSString).length
                if sel.location != NSNotFound, sel.location >= len {
                    client.insertText(e.with, replacementRange: NSRange(location: sel.location - len, length: len))
                }
            }
        }
        showComposition(client)
    }

    private func showComposition(_ client: IMKTextInput) {
        guard let c = composer else { return }
        let notFound = NSRange(location: NSNotFound, length: NSNotFound)
        if !c.isComposing {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: notFound)
            Self.panel.orderOut(nil)
            return
        }
        let marked = NSAttributedString(string: c.display, attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .markedClauseSegment: 0,
        ])
        client.setMarkedText(marked, selectionRange: NSRange(location: (c.display as NSString).length, length: 0),
                             replacementRange: notFound)
        var rect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        Self.panel.onSelect = { [weak self] i in
            guard let self, let c = self.composer else { return }
            self.apply(c.handle(.choose(i + 1)), client)      // clicked a candidate
        }
        Self.panel.show(c.candidates, selected: c.selected, below: rect)
    }

    // MARK: menu (input-source menu in the menu bar)

    override func menu() -> NSMenu! {
        let m = NSMenu(title: "Scriptorium")
        func item(_ title: String, _ key: String, _ def: Bool) {
            let i = NSMenuItem(title: title, action: #selector(toggleSetting(_:)), keyEquivalent: "")
            i.representedObject = key
            i.state = (UserDefaults.standard.object(forKey: key) as? Bool ?? def) ? .on : .off
            m.addItem(i)
        }
        item("Autocorrect & accent restoration", "autocorrect", true)
        m.addItem(.separator())
        item("Latin: macrons (rōsā)", "latinMacrons", true)
        item("Latin: consonantal v (vir)", "latinConsonantalV", true)
        item("Latin: consonantal j (jam)", "latinJ", false)
        m.addItem(.separator())
        item("Greek: macrons on long α ι υ (χώρᾱ)", "greekQuantities", true)
        item("Greek: grave & enclitic accents between words", "greekAutoGrave", true)
        item("Greek: Beta Code marks after the letter (instead of Apple Polytonic keys)", "greekBetaCode", false)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Credits…", action: #selector(showCredits(_:)), keyEquivalent: ""))
        return m
    }

    @objc func showCredits(_ sender: Any?) {
        let a = NSAlert()
        a.messageText = "Scriptorium"
        a.informativeText = """
        Word forms, macrons and accents: Wiktionary, via kaikki.org (wiktextract, T. Ylonen).
        Greek frequencies: Perseus Digital Library, Tufts University.
        Both CC BY-SA 4.0; the lexicons are adapted from them and shared under CC BY-SA 4.0.
        Latin frequencies: The Latin Library (public domain), packaged by the Classical Language Toolkit.

        Code: MIT licence.
        """
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// IMK hands menu actions a dictionary whose kIMKCommandMenuItemName is the item.
    @objc func toggleSetting(_ sender: Any?) {
        let item = (sender as? [String: Any])?[kIMKCommandMenuItemName] as? NSMenuItem ?? sender as? NSMenuItem
        guard let key = item?.representedObject as? String else { return }
        let defaults: [String: Bool] = ["latinJ": false, "greekBetaCode": false]
        let cur = UserDefaults.standard.object(forKey: key) as? Bool ?? defaults[key] ?? true
        UserDefaults.standard.set(!cur, forKey: key)
        Engines.applySettings()
        composer?.autoGrave = UserDefaults.standard.object(forKey: "greekAutoGrave") as? Bool ?? true
    }
}
