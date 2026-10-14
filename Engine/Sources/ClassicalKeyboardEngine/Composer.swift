import Foundation

/// Composition state machine for desktop input methods (macOS IMK).
///
/// Unlike the iOS keyboard, which re-reads the document on every keystroke, a
/// desktop IME owns a *marked* buffer: letters accumulate in `buffer`, the
/// candidate bar shows `candidates`, and committing produces an `Edit` that the
/// host applies to the text just before the cursor.
///
/// Marks can be typed two ways:
///  * dead keys, *before* the letter (Apple Polytonic layout, Māori-style ` for
///    the macron): `.dead` keys pile up in `pending` and land on the next letter;
///  * Beta-Code postfix, *after* the letter: `.mark`.
public final class Composer {
    public enum Key: Equatable {
        case letter(Character)          // already mapped (Greek mode: u → θ)
        case mark(MarkKey)              // postfix: a/ → ά, a_ → ā
        case dead([MarkKey], raw: String)  // prefix: ; a → ά ,  ` a → ā   (raw = the key's own character)
        case apostrophe                 // elision: δ' → δ’
        case space, enter, escape, backspace, tab
        case previous                   // ← ↑ ⇧⇥ (tab / → ↓ = next)
        case punctuation(String)
        case choose(Int)                // 1-based number on the current page
        case nextPage, previousPage     // ↓ ↑ PgDn PgUp
    }

    /// Replace `replace` (committed text right before the cursor, after any marked
    /// text is removed; "" = nothing) with `with`.
    public struct Edit: Equatable {
        public var replace = ""
        public var with = ""
    }

    public struct Response: Equatable {
        public var edit: Edit? = nil
        /// true: the host app should also process the original key event.
        public var passThrough = false
    }

    public let predictor: Predictor
    /// Greek: grave / enclitic accent adjustments between words.
    public var autoGrave = true
    public private(set) var buffer = ""
    /// candidates[0] is what space commits; `selected` moves with tab / arrows.
    public private(set) var candidates: [String] = []
    public private(set) var selected = 0
    /// Candidates are shown nine at a time; the page follows the selection.
    public static let pageSize = 9
    public var page: Int { selected / Self.pageSize }
    public var pageCount: Int { (candidates.count + Self.pageSize - 1) / Self.pageSize }
    public var pageCandidates: [String] {
        guard !candidates.isEmpty else { return [] }
        let start = page * Self.pageSize
        return Array(candidates[start..<min(start + Self.pageSize, candidates.count)])
    }
    /// dead keys typed but not yet attached to a letter
    public private(set) var pending: [MarkKey] = []
    private var pendingRaw = ""

    /// The word we inserted last, if it is still followed by exactly one space.
    private var lastWord: String?
    private var previous: String?
    private var lastCorrection: (original: String, inserted: String)?
    /// We just turned "word␣," into "word,␣": the user's habitual next space is swallowed.
    private var swallowSpace = false

    public init(predictor: Predictor) { self.predictor = predictor }

    private var language: Language { predictor.language }

    public var isComposing: Bool { !buffer.isEmpty || !pending.isEmpty }
    /// What to show as marked text: the buffer plus spacing glyphs of pending dead keys.
    public var display: String { buffer + pending.map(\.label).joined() }

    /// Forget context (cursor moved, focus changed). Returns the buffer so the
    /// host can commit it verbatim.
    @discardableResult
    public func reset() -> String {
        let b = buffer + pendingRaw
        buffer = ""; candidates = []; selected = 0
        pending = []; pendingRaw = ""
        previous = nil; lastWord = nil; lastCorrection = nil
        return b
    }

    public func handle(_ key: Key) -> Response {
        if swallowSpace {
            swallowSpace = false
            if key == .space && !isComposing { return Response() }
        }
        switch key {
        case .letter(let c):
            lastCorrection = nil
            if !pending.isEmpty {
                let marked = applyPending(to: c)
                buffer += marked
            } else {
                buffer.append(c)
            }
            update()
            return Response()

        case .dead(let marks, let raw):
            // the same dead key twice = its own character (`` → `)
            if pendingRaw == raw {
                pending = []; pendingRaw = ""
                return literal(raw)
            }
            pending += marks
            pendingRaw += raw
            return Response()

        case .mark(let m):
            guard let last = buffer.last, let marked = m.toggle(on: last) else {
                return punctuation(m.label)
            }
            buffer.removeLast(); buffer.append(marked)
            update()
            return Response()

        case .apostrophe:
            pending = []; pendingRaw = ""
            guard !buffer.isEmpty else { return punctuation("’") }
            buffer += "’"
            update()
            return Response()

        case .space:
            if !pending.isEmpty {
                // smooth breathing typed after a word = elision (δ' → δ’), as in print
                if !buffer.isEmpty && pending == [.smooth] {
                    pending = []; pendingRaw = ""
                    buffer += "’"
                    update()
                } else {
                    // dead key + space = the key's own character, like Apple's layouts
                    let raw = pendingRaw
                    pending = []; pendingRaw = ""
                    return literal(raw)
                }
            }
            guard !buffer.isEmpty else {
                lastWord = nil; lastCorrection = nil
                return Response(edit: Edit(with: " "))
            }
            return Response(edit: commit(candidates[selected], trailing: " "))

        case .tab:
            guard !candidates.isEmpty else { return Response(passThrough: true) }
            selected = (selected + 1) % candidates.count
            return Response()

        case .previous:
            guard !candidates.isEmpty else { return Response(passThrough: true) }
            selected = (selected + candidates.count - 1) % candidates.count
            return Response()

        case .nextPage, .previousPage:
            guard pageCount > 1 else { return Response(passThrough: !isComposing) }
            let p = (page + (key == .nextPage ? 1 : pageCount - 1)) % pageCount
            selected = p * Self.pageSize
            return Response()

        case .choose(let k):
            let n = page * Self.pageSize + k
            guard k >= 1, k <= Self.pageSize, n <= candidates.count else {
                return buffer.isEmpty ? Response(passThrough: true) : punctuation(String(k))
            }
            return Response(edit: commit(candidates[n - 1], trailing: " ", chosen: true))

        case .enter:
            flushPending()
            guard !buffer.isEmpty else { lastWord = nil; return Response(passThrough: true) }
            var r = Response(edit: commit(candidates[selected], trailing: ""))
            r.passThrough = true
            lastWord = nil
            return r

        case .escape:
            flushPending()
            guard !buffer.isEmpty else { return Response(passThrough: true) }
            let lit = literalWord()
            predictor.user.protect(lit)
            return Response(edit: commit(lit, trailing: "", chosen: true))

        case .backspace:
            if !pending.isEmpty {
                pending.removeLast(); pendingRaw = String(pendingRaw.dropLast())
                if pending.isEmpty { pendingRaw = "" }
                return Response()
            }
            if !buffer.isEmpty {
                buffer.removeLast()
                update()
                return Response()
            }
            lastWord = nil
            if let lc = lastCorrection {
                lastCorrection = nil
                predictor.user.protect(lc.original)
                return Response(edit: Edit(replace: lc.inserted, with: lc.original))
            }
            return Response(passThrough: true)

        case .punctuation(let p):
            let raw = pendingRaw
            pending = []; pendingRaw = ""
            return punctuation(raw + p)
        }
    }

    /// Dead keys go onto the letter if they can (vowels; breathing on ρ), else are typed out.
    private func applyPending(to c: Character) -> String {
        defer { pending = []; pendingRaw = "" }
        let lower = Character(c.lowercased())
        let isVowel = language == .greek ? Greek.vowels.contains(lower) : "aeiouy".contains(lower)
        let rhoBreathing = language == .greek && lower == "ρ" && pending.allSatisfy { $0 == .smooth || $0 == .rough }
        guard isVowel || rhoBreathing else { return pendingRaw + String(c) }
        var out = c
        for m in pending { out = m.toggle(on: out) ?? out }
        return String(out)
    }

    private func flushPending() {
        if !pending.isEmpty { buffer += pendingRaw; pending = []; pendingRaw = "" }
    }

    /// Punctuation that belongs to the word before it: typed right after
    /// "word␣", it goes in front of the space ("word, "), as on Apple's keyboards.
    public static let attaching: Set<Character> = [",", ".", ";", ":", "·", "!", "?", "’", ")", "»", "]", "\u{037E}"]

    private func punctuation(_ p: String) -> Response {
        lastCorrection = nil
        if buffer.isEmpty, lastWord != nil, let c = p.first, Self.attaching.contains(c) {
            lastWord = nil
            previous = nil
            swallowSpace = true
            return Response(edit: Edit(replace: " ", with: p + " "))
        }
        if buffer.isEmpty { lastWord = nil; return Response(edit: Edit(with: p)) }
        var e = commit(candidates[selected], trailing: "")
        e.with += p
        previous = nil; lastWord = nil
        return Response(edit: e)
    }

    /// Insert a character that is not part of a word (e.g. a dead key's own glyph).
    private func literal(_ s: String) -> Response {
        if buffer.isEmpty { lastWord = nil; return Response(edit: Edit(with: s)) }
        buffer += s
        update()
        return Response()
    }

    private func literalWord() -> String {
        language == .greek ? Greek.finalSigma(buffer) : buffer
    }

    private func commit(_ chosen: String, trailing: String, chosen explicit: Bool = false) -> Edit {
        let typed = buffer
        var word = chosen
        if language == .greek { word = Greek.finalSigma(word) }
        predictor.user.learn(word, after: previous, language: language)
        var edit = Edit(with: word + trailing)
        // Greek: now that we know what follows the previous word, fix both accents
        if language == .greek, autoGrave, let prev = lastWord {
            let (p, n) = Greek.join(prev, word)
            if p != prev || n != word {
                edit = Edit(replace: prev + " ", with: p + " " + n + trailing)
                word = n
            }
        }
        lastCorrection = !explicit && word != literalWord() ? (typed, word + trailing) : nil
        previous = word
        lastWord = trailing == " " ? word : nil
        buffer = ""; candidates = []; selected = 0
        return edit
    }

    private func update() {
        selected = 0
        guard !buffer.isEmpty else { candidates = []; return }
        let pred = predictor.predict(previous: previous, typed: buffer)
        var list: [String] = []
        if let ac = pred.autocorrect?.text { list.append(ac) } else { list.append(literalWord()) }
        for s in pred.suggestions where !list.contains(s.text) && list.count < 26 { list.append(s.text) }
        if !list.contains(literalWord()) { list.append(literalWord()) }
        candidates = list
    }
}
