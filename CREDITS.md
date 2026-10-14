# Credits and licences

Scriptorium's **source code** is MIT-licensed (see `LICENSE`).
The **lexicon files** it builds and ships (`latin.lex`, `greek.lex`) are
derived from the sources below and are therefore distributed under
**CC BY-SA 4.0**. Any app or website that ships them must show this
attribution. The iOS app and the macOS input method both include it
(iOS: app → *Credits*; macOS: input menu → *Credits…*).

## Data

| Source | Used for | Licence |
|---|---|---|
| **Wiktionary**, via **kaikki.org / wiktextract** | Every inflected form with its macrons, accents and breathings (≈1.1 M Latin and ≈1 M Greek forms); lemma weights | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) (Wiktionary text is also GFDL) |
| **Perseus Digital Library**, *canonical-greekLit* (Tufts University) | Ancient Greek word and bigram frequencies (814 TEI texts, 10.6 M tokens) | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) |
| **The Latin Library** (thelatinlibrary.com), as packaged by the **Classical Language Toolkit** (`cltk/lat_text_latin_library`) | Latin word and bigram frequencies (2,141 files, 13.3 M tokens) | [Public Domain Mark 1.0](https://creativecommons.org/publicdomain/mark/1.0/) |

Only statistics are taken from the corpora: frequency counts and the most common
word pairs. No running text is redistributed. The corpora themselves are not
part of this repository; `tools/build_lexicon.py` reads local clones.

Citations:

- Tatu Ylonen. 2022. *Wiktextract: Wiktionary as Machine-Readable Structured
  Data.* In Proceedings of LREC 2022, pp. 1317–1325.
  Data: <https://kaikki.org/dictionary/>; Wiktionary: <https://www.wiktionary.org/>.
- Gregory R. Crane (ed.), *Perseus Digital Library*, Tufts University.
  <https://github.com/PerseusDL/canonical-greekLit>.
- William L. Carey (ed.), *The Latin Library*. <https://www.thelatinlibrary.com/>;
  CLTK packaging: <https://github.com/cltk/lat_text_latin_library>.

### What "adapted" means here
The lexicons are a transformation of the Wiktionary forms. Forms are normalised
(breves and doubtful quantities removed, elision marks unified, affix entries and
impossible word endings dropped), and each form gets a frequency score from the
corpora. Under CC BY-SA 4.0 that makes the lexicon an adaptation, so it is
shared under the same licence.

## Keyboard conventions
- The macOS Greek dead keys follow the key positions of Apple's **Greek –
  Polytonic** keyboard layout. The Māori-style macron key (`` ` `` before a
  vowel) follows Apple's **Māori** layout. These are key positions only, for
  familiarity; no Apple code or data is copied.
- The postfix diacritic option follows TLG **Beta Code** conventions.

## Fonts in the artwork
- App icons (`design/make_icons.swift`) are rendered with **Palatino**
  (Linotype), as installed with macOS. Only raster images are shipped, not
  the font.
- The input-source badges (`design/make_badges.swift`) contain the outline of
  one glyph each (ā, ἀ) from Apple's **SF Pro** system font, in a 16-pt
  PDF.
- **Before a public release** (App Store, website), re-render both with an
  OFL-licensed font that has polytonic Greek, such as Noto Serif, GFS Didot
  or Gentium Plus. Swap the font name in the two scripts and run them again.

## Tools and system libraries (not redistributed)
- **XcodeGen** (MIT): generates the Xcode projects from `project.yml`.
- **SQLite** (public domain): the system copy on iOS/macOS reads the lexicons.
- Apple frameworks: UIKit, AppKit, InputMethodKit, Carbon (Text Input Sources).

## Your own earlier work reused
- `tools/grc_keys.py` is copied from the author's Ancient Greek dictionary
  project (`grc.py`, same author).
