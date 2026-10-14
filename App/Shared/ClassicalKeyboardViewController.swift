import ClassicalKeyboardEngine
import os
import UIKit

/// Shared controller for both keyboards; subclasses only name the language.
///
/// Text model: we keep `shadow`, our own copy of the text before the cursor,
/// updated synchronously with every edit we make. The proxy's
/// documentContextBeforeInput is updated *asynchronously* and lags behind fast
/// typing; reading it mid-burst made us delete and rewrite the wrong letters.
/// We only resynchronise from the proxy when the document changes under us
/// (cursor moved, host cleared the field) and we are not in the middle of typing.
///
/// Prediction runs on a background queue so taps are never blocked by it; only
/// the newest result is shown.
class ClassicalKeyboardViewController: UIInputViewController, KeyboardViewDelegate {
    var language: Language { .latin }
    var lexiconName: String { "latin" }

    private var predictor: Predictor?            // background queue only (suggestions)
    /// Main thread only: confirming a word (space, punctuation) must never wait
    /// behind the background queue — while the main thread waits, taps are lost.
    /// Own SQLite connection; shares the (locked) user model.
    private var commitPredictor: Predictor?
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
    /// We just turned "word␣," into "word,␣": swallow the user's habitual next space.
    private var swallowSpace = false

    var inputController: UIInputViewController? { self }

    // shadow of the document + resync bookkeeping
    private var shadow = ""
    private var lastOwnEdit = Date.distantPast
    private var resyncWork: DispatchWorkItem?

    // the predictor (SQLite, not thread-safe) is only touched on this queue
    private let engineQ = DispatchQueue(label: "scriptorium.engine", qos: .userInitiated)
    private let latestRequest = OSAllocatedUnfairLock(initialState: 0)
    private var requestID = 0
    /// last finished prediction, reused by space if it is for the same input
    private var cached: (prev: String?, word: String, prediction: Prediction)?

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
            let user = UserModel.load(from: KeyboardSettings.userModelURL(language.rawValue))
            predictor = Predictor(lexicon: lex, user: user)
            if let lex2 = try? Lexicon(path: path) { commitPredictor = Predictor(lexicon: lex2, user: user) }
        }
        applySettings()
        rebuildKeys()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        settings = KeyboardSettings.load()      // may have changed in the app
        applySettings()
        resync()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The system's screen-edge gestures delay touches near the edges (a, q, p, l…),
        // and quick taps there get lost. Let touches through immediately.
        kv.relaxSystemGates()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let url = KeyboardSettings.userModelURL(language.rawValue)
        let user = predictor?.user
        engineQ.async { try? user?.save(to: url) }
    }

    // The document changed. If it is our own typing echoing back, ignore it; if we
    // have been idle, it changed under us (cursor moved, field cleared): resync.
    override func textDidChange(_ textInput: UITextInput?) { documentMayHaveChanged() }
    override func selectionDidChange(_ textInput: UITextInput?) { documentMayHaveChanged() }

    private func documentMayHaveChanged() {
        resyncWork?.cancel()
        if Date().timeIntervalSince(lastOwnEdit) > 0.6 {
            resync()
        } else {
            let w = DispatchWorkItem { [weak self] in self?.documentMayHaveChanged() }
            resyncWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: w)
        }
    }

    private func resync() {
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        if !(shadow.hasSuffix(ctx) || ctx.hasSuffix(shadow)) || ctx.isEmpty != shadow.isEmpty {
            shadow = ctx
            lastCommitted = nil
            lastCorrection = nil
        }
        updateShift()
        refresh()
    }

    private func applySettings() {
        kv.showDiagnostics = settings.diagnostics
        let s = settings
        if let c = commitPredictor {
            c.autocorrectEnabled = s.autocorrect
            c.latinStyle = LatinStyle(macrons: s.latinMacrons, consonantalV: s.latinConsonantalV, consonantalJ: s.latinJ)
            c.greekStyle = GreekStyle(quantities: s.greekQuantities)
        }
        guard let p = predictor else { return }
        engineQ.async {
            p.autocorrectEnabled = s.autocorrect
            p.latinStyle = LatinStyle(macrons: s.latinMacrons, consonantalV: s.latinConsonantalV,
                                      consonantalJ: s.latinJ)
            p.greekStyle = GreekStyle(quantities: s.greekQuantities)
        }
        cached = nil
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

    // MARK: reading and editing the document (always through the shadow)

    private var before: String { shadow }

    private func ins(_ s: String) {
        guard !s.isEmpty else { return }
        textDocumentProxy.insertText(s)
        if kv.showDiagnostics { kv.counters.typed += s.count }
        scheduleVerify()
        shadow += s
        if shadow.count > 400 { shadow = String(shadow.suffix(300)) }
        lastOwnEdit = Date()
    }

    /// After a pause, check the document really contains what we think we typed.
    /// If the host dropped something, follow the document (and count it).
    private var verifyWork: DispatchWorkItem?
    private func scheduleVerify() {
        verifyWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.verify() }
        verifyWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    private func verify() {
        guard Date().timeIntervalSince(lastOwnEdit) >= 0.75 else { scheduleVerify(); return }
        let ctx = textDocumentProxy.documentContextBeforeInput ?? ""
        let n = min(ctx.count, shadow.count, 60)
        guard n > 0, String(ctx.suffix(n)) != String(shadow.suffix(n)) else { return }
        if kv.showDiagnostics {
            kv.counters.mismatch += 1
            kv.mismatchSample = "kbd:…\(shadow.suffix(14)) doc:…\(ctx.suffix(14))"
        }
        shadow = ctx
        lastCommitted = nil
        lastCorrection = nil
    }

    private func del(_ n: Int) {
        for _ in 0..<max(0, n) {
            textDocumentProxy.deleteBackward()
            if !shadow.isEmpty { shadow.removeLast() }
        }
        lastOwnEdit = Date()
    }

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

    /// Ask for suggestions in the background; show them only if still current.
    private func refresh() {
        guard let p = predictor else { return }
        let (prev, word) = context()
        requestID += 1
        let id = requestID
        latestRequest.withLock { $0 = id }
        engineQ.async { [weak self] in
            // a newer keystroke already asked again: skip this one
            guard let self, self.latestRequest.withLock({ $0 }) == id else { return }
            let pred = p.predict(previous: prev, typed: word)
            DispatchQueue.main.async {
                guard id == self.requestID else { return }
                self.cached = (prev, word, pred)
                self.show(pred, word: word)
            }
        }
    }

    /// Prediction for the current input, right now (space / punctuation need it).
    /// Never waits for the background queue: uses the main-thread predictor.
    private func predictNow(_ prev: String?, _ word: String) -> Prediction? {
        if let c = cached, c.prev == prev, c.word == word { return c.prediction }
        return commitPredictor?.predict(previous: prev, typed: word)
    }

    private func show(_ pred: Prediction, word: String) {
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
        let shown = Set(slots) .union([word])
        kv.setMore(pred.suggestions.map(\.text).filter { !shown.contains($0) })
    }

    func moreSuggestionChosen(_ text: String) {
        let (_, word) = context()
        replaceWord(word, with: text, trailing: " ")
    }

    // MARK: key handling

    func keyTapped(_ key: KeySpec) {
        if swallowSpace {
            swallowSpace = false
            if key.kind == .space && context().1.isEmpty { return }
        }
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
            let w = word
            engineQ.async { [weak self] in self?.predictor?.user.protect(w) }
        }
        replaceWord(word, with: text, trailing: " ")
    }

    private func insert(_ s: String) {
        lastCorrection = nil
        // "verbum␣" + "," → "verbum, " : punctuation goes in front of the space we just added
        if lastCommitted != nil, before.hasSuffix(" "), let c = s.first, Composer.attaching.contains(c),
           context().1.isEmpty {
            del(1)
            ins(s + " ")
            lastCommitted = nil
            swallowSpace = true
            updateShift()
            refresh()
            return
        }
        if let c = s.first, !c.isLetter, !context().1.isEmpty {
            // punctuation ends a word too: restore accents
            commitWord(trailing: "")
        }
        if let c = s.first, !c.isLetter { lastCommitted = nil }
        ins(s)
        if shiftOnce { shiftOnce = false; kv.shifted = shiftLocked }
        updateShift()
        refresh()
    }

    private func applyMark(_ m: MarkKey) {
        guard let last = before.last, let marked = m.toggle(on: last) else { return }
        del(1)
        ins(String(marked))
        refresh()
    }

    private func commitWord(trailing: String) {
        let (prev, word) = context()
        guard !word.isEmpty, let pred = predictNow(prev, word) else {
            lastCommitted = nil
            ins(trailing)
            updateShift()
            refresh()
            return
        }
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
            rewrite(prev + " " + word, as: p + " " + n + trailing)
            out = n
        } else {
            rewrite(word, as: out + trailing)
        }
        lastCommitted = trailing == " " ? out : nil
        let learned = text, after = context().0, lang = language
        engineQ.async { [weak self] in self?.predictor?.user.learn(learned, after: after, language: lang) }
        lastCorrection = nil
        updateShift()
        refresh()
    }

    /// Replace `old` (the text just before the cursor) with `new`, touching only
    /// what differs: unchanged words cost one insert (the space), "nos" → "nōs"
    /// deletes 2 not 3. Host apps can drop keystrokes during bursts of
    /// deletes + inserts, so the fewer proxy calls the better.
    private func rewrite(_ old: String, as new: String) {
        let o = Array(old), n = Array(new)
        var k = 0
        while k < o.count, k < n.count, o[k] == n[k] { k += 1 }
        del(o.count - k)
        ins(String(n[k...]))
    }

    private func backspace() {
        if let lc = lastCorrection, before.hasSuffix(lc.inserted) {
            del(lc.inserted.count)
            ins(lc.original)
            let o = lc.original
            engineQ.async { [weak self] in self?.predictor?.user.protect(o) }
            lastCorrection = nil
        } else {
            del(1)
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
