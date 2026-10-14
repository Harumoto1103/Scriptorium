import ClassicalKeyboardEngine
import UIKit

/// Shared controller for both keyboards; subclasses only name the language.
///
/// Text model: the "current word" is whatever run of letters sits right before
/// the cursor (read from documentContextBeforeInput). Nothing is held in a
/// buffer, so moving the cursor or editing elsewhere never desynchronises us.
class ClassicalKeyboardViewController: UIInputViewController, KeyboardViewDelegate {
    var language: Language { .latin }
    var lexiconName: String { "latin" }

    private var predictor: Predictor?
    private var settings = KeyboardSettings.load()
    private let kv = KeyboardView()
    private var heightConstraint: NSLayoutConstraint?
    private var layer: Layer = .letters
    private var shiftLocked = false
    private var shiftOnce = false

    private var slots: [String] = []            // what the bar currently shows
    private var autocorrectSlot: Int?
    /// After a space-autocorrect: backspace restores the literal (iOS behaviour).
    private var lastCorrection: (original: String, inserted: String)?
    /// The word we inserted last, while it is still followed by exactly one space:
    /// Greek accents between it and the next word are settled when that word is committed.
    private var lastCommitted: String?

    var inputController: UIInputViewController? { self }

    // MARK: life cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        kv.delegate = self
        kv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(kv)
        NSLayoutConstraint.activate([
            kv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            kv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            kv.topAnchor.constraint(equalTo: view.topAnchor),
            kv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        if let path = Bundle.main.path(forResource: lexiconName, ofType: "lex"),
           let lex = try? Lexicon(path: path) {
            predictor = Predictor(lexicon: lex,
                                  user: UserModel.load(from: KeyboardSettings.userModelURL(language.rawValue)))
        }
        applySettings()
        rebuildKeys()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        settings = KeyboardSettings.load()      // may have changed in the app
        applySettings()
        updateShift()
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The system's screen-edge gestures delay touches near the edges (a, q, p, l…),
        // and quick taps there get lost. Let touches through immediately.
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
        view.superview?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        try? predictor?.user.save(to: KeyboardSettings.userModelURL(language.rawValue))
    }

    override func textDidChange(_ textInput: UITextInput?) {
        updateShift()
        refresh()
    }

    private func applySettings() {
        guard let p = predictor else { return }
        p.autocorrectEnabled = settings.autocorrect
        p.latinStyle = LatinStyle(macrons: settings.latinMacrons, consonantalV: settings.latinConsonantalV,
                                  consonantalJ: settings.latinJ)
        p.greekStyle = GreekStyle(quantities: settings.greekQuantities)
    }

    private func rebuildKeys() {
        kv.rows = KeyLayouts.rows(language, layer, globe: needsInputModeSwitchKey)
        let h = kv.preferredHeight
        if let c = heightConstraint { c.constant = h } else {
            heightConstraint = view.heightAnchor.constraint(equalToConstant: h)
            heightConstraint?.priority = .defaultHigh
            heightConstraint?.isActive = true
        }
    }

    // MARK: reading the document

    private var before: String { textDocumentProxy.documentContextBeforeInput ?? "" }

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter }
    private static let sentenceEnd: Set<Character> = [".", ";", "·", "?", "!", ":", "\n", "\u{037E}"]

    /// (previous committed word, current partial word)
    private func context() -> (String?, String) {
        let b = before
        let word = String(b.reversed().prefix { Self.isWordChar($0) }.reversed())
        var rest = b.dropLast(word.count)
        while rest.last == " " { rest = rest.dropLast() }
        if let last = rest.last, Self.sentenceEnd.contains(last) { return (nil, word) }
        let prev = String(rest.reversed().prefix { Self.isWordChar($0) }.reversed())
        return (prev.isEmpty ? nil : prev, word)
    }

    // MARK: suggestions

    private func refresh() {
        guard let p = predictor else { return }
        let (prev, word) = context()
        let pred = p.predict(previous: prev, typed: word)
        var s = pred.suggestions.map(\.text)
        autocorrectSlot = nil
        if word.isEmpty {
            slots = Array(s.prefix(3))
        } else if let ac = pred.autocorrect?.text {
            // [ "literal" ] [ **autocorrect** ] [ next best ]
            s.removeAll { $0 == ac || $0 == word }
            slots = ["\u{201C}\(word)\u{201D}", ac] + s.prefix(1)
            autocorrectSlot = 1
        } else {
            s.removeAll { $0 == word }
            slots = [word] + s.prefix(2)
        }
        kv.setSuggestions(slots, highlight: autocorrectSlot)
    }

    // MARK: key handling

    func keyTapped(_ key: KeySpec) {
        switch key.kind {
        case .char(let c):
            insert(kv.shifted ? c.uppercased() : c)
        case .mark(let m):
            applyMark(m)
        case .space:
            commitWord(trailing: " ")
        case .enter:
            commitWord(trailing: "\n")
        case .backspace:
            backspace()
        case .shift:
            if shiftOnce || shiftLocked { shiftOnce = false; shiftLocked = false } else { shiftOnce = true }
            kv.shifted = shiftOnce || shiftLocked
        case .layer(let l):
            layer = l; rebuildKeys()
        case .globe:
            break                           // handled by handleInputModeList
        }
    }

    func variantChosen(_ text: String, of key: KeySpec) {
        if text.hasPrefix("◌"), let m = MarkKey(rawValue: String(text.dropFirst())) {
            applyMark(m)
        } else {
            insert(text)
        }
    }

    private var overlay: SettingsOverlay?

    func spaceLongPressed() {
        guard overlay == nil else { return }
        let o = SettingsOverlay(language: language, settings: settings, onChange: { [weak self] s in
            guard let self else { return }
            self.settings = s
            s.save()
            self.applySettings()
            self.refresh()
        }, onClose: { [weak self] in
            self?.overlay?.removeFromSuperview()
            self?.overlay = nil
        })
        o.frame = kv.bounds
        o.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        kv.addSubview(o)
        overlay = o
    }

    func suggestionTapped(_ i: Int) {
        guard i < slots.count, !slots[i].isEmpty else { return }
        let (_, word) = context()
        var text = slots[i]
        if text.hasPrefix("\u{201C}") {                 // the literal: keep it and learn it
            text = word
            predictor?.user.protect(word)
        }
        replaceWord(word, with: text, trailing: " ")
    }

    private func insert(_ s: String) {
        lastCorrection = nil
        if let c = s.first, !c.isLetter, !context().1.isEmpty {
            // punctuation ends a word too: restore accents
            commitWord(trailing: "")
        }
        if let c = s.first, !c.isLetter { lastCommitted = nil }
        textDocumentProxy.insertText(s)
        if shiftOnce { shiftOnce = false; kv.shifted = shiftLocked }
        updateShift()
        refresh()
    }

    private func applyMark(_ m: MarkKey) {
        guard let last = before.last, let marked = m.toggle(on: last) else { return }
        textDocumentProxy.deleteBackward()
        textDocumentProxy.insertText(String(marked))
        refresh()
    }

    private func commitWord(trailing: String) {
        let (prev, word) = context()
        guard !word.isEmpty, let p = predictor else {
            lastCommitted = nil
            textDocumentProxy.insertText(trailing)
            refresh()
            return
        }
        let pred = p.predict(previous: prev, typed: word)
        var final = pred.autocorrect?.text ?? word
        if language == .greek { final = Greek.finalSigma(final) }
        replaceWord(word, with: final, trailing: trailing)
        if final != word { lastCorrection = (word, final + trailing) }
    }

    private func replaceWord(_ word: String, with text: String, trailing: String) {
        var out = text
        // Greek: now that the next word is known, settle grave / enclitic accents of both
        if language == .greek, settings.greekAutoGrave, let prev = lastCommitted,
           before.hasSuffix(prev + " " + word) {
            let (p, n) = Greek.join(prev, text)
            if p != prev {
                for _ in 0..<(word.count + 1 + prev.count) { textDocumentProxy.deleteBackward() }
                textDocumentProxy.insertText(p + " ")
            } else {
                for _ in 0..<word.count { textDocumentProxy.deleteBackward() }
            }
            out = n
        } else {
            for _ in 0..<word.count { textDocumentProxy.deleteBackward() }
        }
        textDocumentProxy.insertText(out + trailing)
        lastCommitted = trailing == " " ? out : nil
        predictor?.user.learn(text, after: context().0, language: language)
        lastCorrection = nil
        updateShift()
        refresh()
    }

    private func backspace() {
        if let lc = lastCorrection, before.hasSuffix(lc.inserted) {
            for _ in 0..<lc.inserted.count { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(lc.original)
            predictor?.user.protect(lc.original)
            lastCorrection = nil
        } else {
            textDocumentProxy.deleteBackward()
        }
        lastCommitted = nil
        updateShift()
        refresh()
    }

    /// Auto-shift at the start of a sentence.
    private func updateShift() {
        guard layer == .letters, !shiftLocked else { return }
        let t = before.trimmingCharacters(in: .whitespaces)
        let start = t.isEmpty || [".", "?", "!", "\n"].contains(t.last!)
        let wasAuto = kv.shifted
        if start != wasAuto && !shiftOnce { kv.shifted = start }
    }
}
