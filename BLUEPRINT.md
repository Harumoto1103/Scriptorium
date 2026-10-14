# Scriptorium — Latin & Ancient Greek keyboards with prediction

iOS keyboards and a macOS input method for Latin and polytonic Ancient Greek,
with word prediction, autocorrect, **automatic accents/breathings** for Greek,
and **macrons for both languages**. Everything runs offline, on-device.

Status 2026-10-14: engine and lexicons are working and tested; the iOS app compiles for the
simulator but has not been run on a device yet; the macOS input method builds, installs and launches.

---

## 1. What it does

| | Latin keyboard | Greek keyboard |
|---|---|---|
| Type bare letters, get… | `diuisa` → **dīvīsa**, `tres` → **trēs** | `ανθρωπος` → **ἄνθρωπος**, `ζωον` → **ζῷον** |
| Long vowels | macrons from Wiktionary forms (toggle) | macrons on long α ι υ: **χώρᾱ, πρᾱ́ττω, κᾱλός** (toggle) |
| Context | bigrams: `senatus` → *consulto, consultum…* | bigrams pick the case: `ἐν αρχη` → **ἀρχῇ** |
| Accent rules | — | oxytone → grave before the next word (**καλὸς ἀνήρ**), reverted if punctuation follows; final σ → ς; τίς/τί exempt |
| Autocorrect | keyboard-aware edit distance: `amivus` → amicus | same: typos and missing accents together |
| Clitics | `-que / -ne / -ve` split generically: `regnaue` → rēgnave | enclitics left unaccented (`μοι`) |
| Manual marks | long-press vowels (ā æ ä…; no breves), `¯` key toggles a macron on the last letter | long-press (ᾱ ἀ ἁ ά ᾶ ᾳ…), `¯` key, `´` key + menu for every mark |
| Your words | learned; backspace after a correction restores and remembers the literal | same |
| Orthography | u/v and i/j options | — |

The rule for marks you type yourself: they always win. If you type *any* macron in a word,
your unmarked vowels count as short: `rosā` stays rosā, not rōsā.

## 2. Architecture

```
 corpora (Latin Library 13.3M tokens,          dictionaries you already run
 Perseus canonical-greekLit 10.6M tokens)      (latin.db 889k lemmas·forms, greek.db 68k lemmas)
                 \                               /
                  tools/build_lexicon.py  (Python, ~2 min)
                                 |
              out/latin.lex (40 MB)   out/greek.lex (56 MB)      ← SQLite, read-only, mmapped
                                 |
              Engine/  (Swift package, no dependencies: libsqlite3 only)
                Folding · Lexicon · Predictor · Orthography/Marks · UserModel · Composer
                 /                                   \
   App/  iOS: container app + 2 keyboard          Mac/  macOS: InputMethodKit app with
   extensions (UIInputViewController)             2 input modes, candidate bar, Beta-Code marks
```

### 2.1 Lexicon format (`*.lex`)
- `lex(key, word, freq)`: **key** is what the fingers produce (Latin: no marks, j→i, v→u;
  Greek: bare lowercase letters, ς→σ); **word** is what gets inserted. PRIMARY KEY(key, word), WITHOUT ROWID.
  Lookups by key return every restoration (ἤ ἡ ἥ ᾗ ἦ ᾖ …) ranked by frequency.
- `top(prefix, words)`: precomputed completions for 1–3 letter prefixes (these ranges are too big to scan per keystroke).
- `bi(prev, next, n)`: up to 64 continuations per word. Latin is keyed by key; Greek by the exact
  form (macrons stripped, grave→acute), because ἡ/ἤ/ἥ share a key and context is what separates them.
- Frequencies: Greek counts exact polytonic forms in Perseus. Latin text has no macrons, so each
  key's count is split among its macron variants by **lemma frequency**, estimated with two rounds of a small EM.
- Junk control: affix entries (-tris → "tres") are skipped. Unmarked page titles are only used when
  no marked inflection-table form covers them. Greek numerals (ηʹ) and stray marks are dropped. Corpus-only
  words need ≥3 hits and keep their commonest surface spelling and capitalisation.

### 2.2 Prediction (per keystroke, 0–16 ms on an M-series Mac)
score = log₁₀(freq) + 1.2·log₁₀(bigram) + user bonus − penalty. The candidates are:
1. **exact**: rows with the typed key (accent/macron restorations), no penalty;
2. **completions**: 0.6 + 0.1 per untyped letter, from the lexicon, from bigram continuations, and from learned words;
3. **corrections**: Damerau edit-1 with key-adjacency costs (neighbour 1.2, other 2.4, swap 1.3,
   indel 1.8). Only tried when the input is not already a reasonably common word.

Autocorrect policy: a **real word is never swapped** for another word, only re-spelled
(accents, macrons). A non-word is corrected only if it is ≥3 letters and the correction scores above
the literal. A word the user has protected is left alone.

### 2.3 Memory and privacy (iOS)
- Keyboard extensions get about 48–70 MB of RAM. The lexicon is opened `immutable=1` and mmapped, so its pages are
  clean file-backed memory that iOS can drop. Nothing is loaded wholesale.
- `RequestsOpenAccess = false`: no network and no clipboard, and nothing leaves the phone. Settings and
  the learned-word file go through an App Group (`group.uk.harukita.scriptorium`).

## 3. Layout of the repo

```
Scriptorium/
  BLUEPRINT.md              this file
  tools/build_lexicon.py    corpora + dictionaries → out/*.lex
  tools/mac-install.sh      build + install + enable the macOS input method
  tools/tis.swift           list / enable / select input sources
  corpora/                  Latin Library, Perseus Greek (downloaded, not edited)
  out/                      latin.lex, greek.lex
  Engine/                   Swift package + 19 tests + `kbdemo` CLI
  App/                      iOS (XcodeGen: project.yml)
  Mac/                      macOS IME (XcodeGen: project.yml)
```

### Commands
```sh
python3 tools/build_lexicon.py all                  # rebuild lexicons (~2 min)
cd Engine && swift test                             # 19 tests
swift run -c release kbdemo greek "εν αρχη ην ο λογος"
swift run -c release kbdemo latin --macrons "arma uirumque cano"
cd App && xcodegen generate && open Scriptorium.xcodeproj   # set your Team, run on iPhone
tools/mac-install.sh                                # macOS
```

## 4. macOS input method
- One bundle (`~/Library/Input Methods/Scriptorium.app`) with two modes: **Latin** and **Greek**.
  Greek uses Apple's Greek key positions on a US keyboard (u→θ, j→ξ, c→ψ, v→ω, w→ς, q→;, physical ; → ·).
- Letters go into an underlined composition, with a candidate bar under the cursor.
  **Space** commits the highlighted candidate (accents, macrons and grave included). **Tab** cycles the candidates,
  **1–9** picks one, **Esc** keeps exactly what you typed (and remembers it), **Return** commits and then
  inserts a newline. **Backspace** right after a correction undoes it.
- Postfix marks while composing, in Beta-Code style: `/` acute, `\` grave, `=` circumflex, `)` smooth,
  `(` rough, `|` iota subscript, `_` macron, `^` breve, `+` diaeresis. Latin uses only `_ +`:
  short vowels are never marked, and dictionary *ancipitia* (ē̆) are output unmarked.
  Examples: `a_` → ā, `a_/` → ᾱ́, `w=|` → ῷ.
- The settings menu (macrons, u/v, j, grave) is under the input-source menu in the menu bar.

## 5. Signing and installing on iPhone
- **Free Apple ID**: works, but the app must be re-installed from Xcode every 7 days. App Groups may
  not be available on a free team. If so, the settings fall back to defaults and each keyboard learns
  separately; everything else works.
- **Paid developer account ($99/yr)**: one-year builds, TestFlight, and App Groups.
- After installing: Settings → General → Keyboard → Keyboards → Add New Keyboard → Latīna / Ἑλληνική.

## 6. Roadmap
**Phase 1 (done, prototype)**: lexicons, engine, tests, iOS app (compiles), macOS input method (builds and installs).

**Phase 2: first real use**
- [ ] Run on a device. Tune key sizes and long-press timing, and measure memory with Instruments (budget 48 MB).
- [ ] Test the macOS input method in real apps (TextEdit, Pages, browsers, VS Code).
- [ ] Evaluation harness: replay held-out Perseus/Latin Library sentences with bare keys and measure
  restoration accuracy, keystroke savings and false autocorrections. Then fit the scoring weights in §2.2 instead of tuning by eye.
- [ ] iOS: double-space → full stop, caps lock, landscape layout, keyboard click sound.

**Phase 3: better linguistics**
- [ ] **Latin macronizer for ambiguous forms**: rosa / rosā / rōsa share a key and the
  Latin Library has no macrons. Use a context model, either a trigram over (lemma, case) or a small
  tagger trained on a macronized corpus such as Hyginus, Dickinson College Commentaries or LLT texts, to choose the quantity.
- [ ] **Enclitic accent rules**: ἄνθρωπός τις, δῶρόν τι (an extra acute on the host word), proclitics.
- [ ] Agreement-aware prediction (adjective ↔ noun case/number/gender) using the dictionary's form tags.
- [ ] Dialect switch: Attic vs Homeric/Ionic (πρᾱ́ττω/πρήσσω, θάλαττα/θάλασσα), and Koine.
- [ ] Optional **transliteration input** on the Latin-letter keyboard (`psyche` → ψυχή), reusing `tkey` from the dictionary site.
- [ ] Crasis and elision suggestions (κἀγώ, δ’, ἀλλ’).

**Phase 4: polish**
- [ ] A lookup button that opens the current word on latina.harukita.uk / hellenika.harukita.uk.
  This needs Full Access only to open a URL; alternatively, copy the word and open the app.
- [ ] Swipe typing; a user dictionary editor in the app; sync of learned words between the Mac and iPhone (iCloud key-value).
- [ ] Smaller lexicons: drop medieval-only forms, or use a FST/DAWG instead of SQLite (could be ~15 MB).

## 7. Known limitations (honest list)
- Latin macron choice between same-spelled forms (rosa/rosā) is frequency-based, not contextual.
- Words that appear only in the corpus have no macrons (no marked source).
- Bigram coverage is good for prose and Homer, and weaker for Koine, medieval Latin and inscriptions.
- `deleteBackward` on iOS deletes one grapheme. Words with stacked marks are one grapheme per letter after NFC,
  but apps that store decomposed text could misbehave. This needs device testing.
- Corpus licences: Perseus is CC BY-SA 4.0 (credit it if this is ever distributed). The Latin Library texts
  are public-domain texts with unclear collection rights; that's fine for personal use.
