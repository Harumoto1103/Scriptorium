# Scriptorium

Latin and Ancient Greek keyboards with **prediction, autocorrect, automatic
polytonic accents and macrons**, for iPhone (keyboard extensions) and macOS
(input method). Everything runs on-device; nothing leaves the phone or Mac.

| | Latin | Greek |
|---|---|---|
| Type bare letters | `diuisa` → **dīvīsa**, `partes tres` → **partēs trēs** | `ανθρωπος` → **ἄνθρωπος**, `ζωον` → **ζῷον** |
| Context | bigrams from 13 M words of Latin | bigrams pick the form: `εν αρχη` → **ἐν ἀρχῇ** |
| Accent rules | — | grave before a following word, enclitics (**ἄνθρωπός τις**, **καλός ἐστι**), final ς |
| Macrons | from Wiktionary (toggle) | long α ι υ: **χώρᾱ, πρᾱ́ττω** (toggle) |
| Typing marks yourself | long-press (iOS); `` ` `` + vowel = ā (macOS, Māori-style) | long-press / mark keys (iOS); Apple Polytonic dead keys or Beta Code (macOS) |

See [`BLUEPRINT.md`](BLUEPRINT.md) for the design and roadmap.

## Layout

```
tools/   build_lexicon.py (dictionaries + corpora → out/*.lex), mac-install.sh, tis.swift
Engine/  Swift package: lexicon, predictor, accent rules, composer (+ tests, `kbdemo` CLI)
App/     iOS app + Latin / Greek keyboard extensions (XcodeGen)
Mac/     macOS input method, one bundle with Latin and Greek modes (XcodeGen)
design/  icon generators and rendered icons
```

## Building

Requirements: Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), Python 3.

### 1. Data
The lexicons are generated, not committed. You need:

- **Dictionary databases**: SQLite indexes built from the kaikki.org Wiktionary
  dumps for Latin and Ancient Greek (`entries(id, word, data JSON, …)`). Point
  `LATIN_DB` and `GREEK_DB` at them.
- **Corpora**, cloned into `corpora/`:
  ```sh
  git clone --depth 1 https://github.com/cltk/lat_text_latin_library corpora/latin_library
  git clone --depth 1 --filter=blob:none --no-checkout https://github.com/PerseusDL/canonical-greekLit corpora/greekLit
  (cd corpora/greekLit && git sparse-checkout set --no-cone '/data/**/*grc*.xml' && git checkout)
  ```

```sh
LATIN_DB=… GREEK_DB=… python3 tools/build_lexicon.py all     # ≈2 min → out/latin.lex, out/greek.lex
```

### 2. Engine
```sh
cd Engine && swift test
swift run -c release kbdemo greek "εν αρχη ην ο λογος"
```

### 3. iPhone
```sh
cp App/Local.xcconfig.example App/Local.xcconfig     # set DEVELOPMENT_TEAM
cd App && xcodegen generate && open Scriptorium.xcodeproj
```
A free Apple ID works; builds expire after 7 days. Free teams can't use App Groups,
so each keyboard keeps its own settings (long-press the space bar).

### 4. macOS
```sh
tools/mac-install.sh      # builds, installs to ~/Library/Input Methods, registers
```
Then add **Latin** / **Greek (Scriptorium)** in System Settings → Keyboard → Input Sources.

## Licence
Code: MIT ([`LICENSE`](LICENSE)). Lexicon data: CC BY-SA 4.0, adapted from
Wiktionary (kaikki.org) and the Perseus Digital Library, with frequencies from
The Latin Library. Full attribution is in [`CREDITS.md`](CREDITS.md).
