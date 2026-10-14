#!/usr/bin/env python3
"""Build the keyboard lexicons (latin.lex / greek.lex, plain SQLite files).

Inputs
  * two dictionary indexes (every inflected form, with macrons / polytonic
    accents, from Wiktionary via kaikki.org); paths from the environment:
        LATIN_DB   (default ~/Downloads/latin-dictionary/data/latin.db)
        GREEK_DB   (default ~/Downloads/greek-dictionary/data/greek.db)
    Each is a SQLite file with an `entries(id, data JSON, …)` table built from a
    kaikki.org JSONL dump; see README.md → "Data".
  * frequency corpora (cloned into ../corpora):
        latin_library/   The Latin Library plain text (no macrons)
        greekLit/        Perseus canonical-greekLit TEI, *grc*.xml only

Output schema (identical for both languages)
  lex(key, word, freq)      key = what the user's fingers produce (folded),
                            word = what we insert. PRIMARY KEY(key, word).
  top(prefix, words)        precomputed completions for 1–3 letter prefixes
  bi(prev, next, n)         bigrams. Latin: both sides are keys.
                            Greek: both sides are exact forms (acute-normalised, no macrons),
                            because ἡ / ἤ / ἥ / ἦ share a key and context is
                            precisely what tells them apart.
  meta(k, v)

usage:  python3 build_lexicon.py [latin|greek|all]
"""
import json
import math
import os
import re
import sqlite3
import sys
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

HOME = Path.home()
ROOT = Path(__file__).resolve().parent.parent
CORPORA = ROOT / "corpora"
OUT = ROOT / "out"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from grc_keys import gkey  # noqa: E402

LATIN_DB = Path(os.environ.get("LATIN_DB", HOME / "Downloads/latin-dictionary/data/latin.db"))
GREEK_DB = Path(os.environ.get("GREEK_DB", HOME / "Downloads/greek-dictionary/data/greek.db"))

MIN_CORPUS_ONLY = 3       # corpus words absent from the dictionary need this many hits
MIN_BIGRAM = 3
BIGRAMS_PER_PREV = 64
TOP_PER_PREFIX = 12


# ---- Latin -----------------------------------------------------------------

def lkey(s):
    """Latin typing key: no macrons/breves, lowercase, j→i, v→u, æ→ae."""
    s = unicodedata.normalize("NFD", s.lower())
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.replace("æ", "ae").replace("œ", "oe").replace("j", "i").replace("v", "u")
    return s if re.fullmatch(r"[a-z]+", s) else ""


def latin_corpus():
    uni, cap, bi = Counter(), Counter(), Counter()
    surf = defaultdict(Counter)        # key → lowercase surface spellings (vir / uir)
    files = sorted((CORPORA / "latin_library").rglob("*.txt"))
    for f in files:
        text = f.read_text(encoding="utf-8", errors="ignore")
        for sent in re.split(r"[.;:?!]+", text):
            prev = None
            for tok in re.findall(r"[A-Za-zÀ-ÿāēīōūȳĀĒĪŌŪæœ]+", sent):
                k = lkey(tok)
                if not k:
                    prev = None
                    continue
                uni[k] += 1
                surf[k][tok.lower()] += 1
                if tok[0].isupper():
                    cap[k] += 1
                if prev:
                    bi[(prev, k)] += 1
                prev = k
    print(f"  latin corpus: {len(files)} files, {sum(uni.values()):,} tokens, {len(uni):,} types")
    return uni, cap, bi, surf


AFFIX_POS = {"suffix", "prefix", "infix", "interfix", "circumfix", "affix", "combining form"}


def is_affix(d):
    """-tris lists 'tres' as a form; affix entries are not words you type."""
    w = d.get("w", "")
    return d.get("pos") in AFFIX_POS or w.startswith("-") or w.endswith("-")


def latin_forms():
    """{key: {display_form: set(lemma_id)}} from the dictionary."""
    db = sqlite3.connect(LATIN_DB)
    out = defaultdict(lambda: defaultdict(set))
    for eid, data in db.execute("SELECT id, data FROM entries"):
        d = json.loads(data)
        if is_affix(d):
            continue
        words = {f["f"] for f in d.get("forms", [])}
        # the page title is unmarked (tres); use it only if no marked form covers it (trēs)
        if lkey(d["w"]) not in {lkey(w) for w in words}:
            words.add(d["w"])
        for w in words:
            w = clean_quantity(w.strip())
            if not w or " " in w or "-" in w:
                continue
            k = lkey(w)
            if k:
                out[k][w].add(eid)
    return out


def build_latin():
    print("latin:")
    uni, cap, bi, surf = latin_corpus()
    forms = latin_forms()
    print(f"  dictionary: {len(forms):,} keys")

    # The corpus has no macrons, so a key's count must be shared among its
    # macron variants (rosa / rosā). Split by lemma frequency, which is itself
    # estimated from the corpus: two rounds of a tiny EM.
    lemma_f = defaultdict(lambda: 1.0)
    for _ in range(2):
        new = defaultdict(float)
        for k, variants in forms.items():
            n = uni.get(k, 0)
            if not n:
                continue
            lemmas = set().union(*variants.values())
            z = sum(lemma_f[l] for l in lemmas)
            for l in lemmas:
                new[l] += n * lemma_f[l] / z
        lemma_f = defaultdict(lambda: 1.0, {l: v + 1.0 for l, v in new.items()})

    rows = []
    for k, variants in forms.items():
        n = uni.get(k, 0)
        mass = {w: sum(lemma_f[l] for l in ls) for w, ls in variants.items()}
        z = sum(mass.values())
        for w, m in mass.items():
            f = n * m / z
            if cap.get(k, 0) > 0.8 * n and n >= MIN_CORPUS_ONLY:
                w = w[:1].upper() + w[1:]
            rows.append((k, w, f))
    known = set(forms)
    extra = 0
    for k, n in uni.items():
        if k not in known and n >= MIN_CORPUS_ONLY and len(k) > 1:
            w = surf[k].most_common(1)[0][0]
            w = w[:1].upper() + w[1:] if cap.get(k, 0) > 0.8 * n else w
            rows.append((k, w, float(n)))
            extra += 1
    print(f"  + {extra:,} corpus-only words (names, medieval spellings…)")
    write_db(OUT / "latin.lex", rows, bi, "la")


# ---- Greek -----------------------------------------------------------------

STRIP_QUANTITY = {"̄", "̆"}   # macron, breve: dictionary-only marks
GREEK_TOKEN = re.compile(r"[Ͱ-Ͽἀ-῿̀-ͯ]+[’'᾽ʼ]?")


GREEK_VOWELS = set("αεηιουω")
GREEK_FINALS = GREEK_VOWELS | set("νρςσξψ")          # letters a Greek word may end in
FINAL_EXCEPTIONS = {"ουκ", "ουχ", "εκ"}
_ELISION_END = re.compile("(?<=[βγδζθκλμνξπρστφχψϝ])[\u0313\u0314]$|['\u1FBD\u1FBF\u02BC\u2019]$")


def fix_elision(s):
    """Every way texts mark elision (δ᾿, δ̓, δ', δʼ) → δ’ (U+2019)."""
    return _ELISION_END.sub("’", unicodedata.normalize("NFD", s))


def greek_ok(nfc):
    """Plausible Greek word: Greek letters + marks only, and a legal final letter
    (vowel, ν ρ ς ξ ψ; οὐκ/οὐχ/ἐκ) unless elided."""
    base = "".join(c for c in unicodedata.normalize("NFD", nfc.lower())
                   if not unicodedata.combining(c))
    if base.endswith("’"):
        return bool(base[:-1]) and all("α" <= c <= "ω" or c in "ϝς" for c in base[:-1])
    if not base or not all("α" <= c <= "ω" or c in "ϝς" for c in base):
        return False
    return base[-1] in GREEK_FINALS or base in FINAL_EXCEPTIONS or len(base) == 1 and base in GREEK_VOWELS


def gnorm(w):
    """Canonical stored form: NFC, no quantity marks, grave→acute, ’ for elision."""
    s = fix_elision(w)
    s = "".join(c for c in s if c not in STRIP_QUANTITY)
    s = s.replace("\u0300", "\u0301")
    s = unicodedata.normalize("NFC", s)
    # numerals (ηʹ, ͵α), stray marks, Latin junk, impossible endings (ἀλλ, δ) are not words
    if not s[:1].isalpha() or any(c in s for c in "\u0374\u0375\u0384\u0385\u00B4\u02B9"):
        return ""
    return s if greek_ok(s) else ""


def clean_quantity(s):
    """Keep only certain long marks: a vowel marked both long and short
    (ē̆: quantity varies) gets neither, and lone breves are dropped
    (short is the unmarked default)."""
    s = unicodedata.normalize("NFD", s)
    s = re.sub("\u0304([\u0300-\u036F]*?)\u0306|\u0306([\u0300-\u036F]*?)\u0304", r"\1\2", s)
    return unicodedata.normalize("NFC", s.replace("\u0306", ""))


def gfull(w):
    """Display form: like gnorm but keeps macrons on long dichrona (ᾱ ῑ ῡ).
    Breves are dropped (short is the unmarked default); a vowel marked both
    long and short (λῡ̆́ω: quantity varies) gets neither."""
    s = clean_quantity(fix_elision(w))
    return unicodedata.normalize("NFC", unicodedata.normalize("NFD", s).replace("\u0300", "\u0301"))


def macrons(w):
    return unicodedata.normalize("NFD", w).count("\u0304")


def greek_corpus():
    uni, bi = Counter(), Counter()
    files = sorted((CORPORA / "greekLit").rglob("*grc*.xml"))
    for f in files:
        x = f.read_text(encoding="utf-8", errors="ignore")
        x = x[x.find("<text"):]
        x = re.sub(r"<note\b.*?</note>|<bibl\b.*?</bibl>|<head\b.*?</head>", " ", x, flags=re.S)
        x = re.sub(r"<[^>]+>", " ", x)
        for sent in re.split(r"[.;·:!?·;]+", x):
            prev = None
            for tok in GREEK_TOKEN.findall(sent):
                w = gnorm(tok)
                if not w or not gkey(w):
                    prev = None
                    continue
                uni[w] += 1
                if prev:
                    bi[(prev, w)] += 1
                prev = w
    print(f"  greek corpus: {len(files)} files, {sum(uni.values()):,} tokens, {len(uni):,} types")
    return uni, bi


def greek_forms():
    db = sqlite3.connect(GREEK_DB)
    out = {}
    for eid, data, weight in db.execute("SELECT id, data, weight FROM entries"):
        d = json.loads(data)
        if is_affix(d):
            continue
        for raw in {d["w"]} | {f["f"] for f in d.get("forms", [])}:
            w = gnorm(raw.strip())
            if not w or " " in w or "-" in w or "/" in w:
                continue
            k = gkey(w).replace(" ", "")
            if not k:
                continue
            full = gfull(raw.strip())
            # Several entries may list the same unmarked form with different quantities:
            # noun ψῡχῇ vs verb ψῠχῇ (→ ψυχῇ), particle ἄν vs contracted ᾱ̓́ν. Keep each
            # spelling with the weight of its heaviest entry; the corpus count (which
            # cannot tell them apart) is split by those weights in build_greek.
            k0, variants = out.get(w, (k, {}))
            variants[full] = max(variants.get(full, 0), weight or 0)
            out[w] = (k0, variants)
    # the same entry may list one form with and without macrons: keep the marked one
    for w, (k, variants) in out.items():
        for v in list(variants):
            stripped = unicodedata.normalize("NFC", unicodedata.normalize("NFD", v).replace("\u0304", ""))
            if v != stripped and stripped in variants and variants[stripped] <= variants[v]:
                del variants[stripped]
    return out


def build_greek():
    print("greek:")
    uni, bi = greek_corpus()
    forms = greek_forms()
    print(f"  dictionary: {len(forms):,} accented forms")
    # Corpus capitalises sentence/verse starts, so fold case before matching,
    # then keep a capital only for words that are (almost) always capitalised.
    low = Counter()
    capn = Counter()
    for w, n in uni.items():
        lw = w.lower()
        low[lw] += n
        if w != lw:
            capn[lw] += n
    rows = []
    seen = set()
    for w, (k, variants) in forms.items():
        lw = w.lower()
        z = sum(variants.values()) or 1.0
        for full, weight in variants.items():
            share = weight / z if sum(variants.values()) else 1 / len(variants)
            f = low.get(lw, 0) * share + 0.01 * weight      # tiny prior orders unattested forms
            rows.append((k, full, f))
        seen.add(lw)
    extra = 0
    for lw, n in low.items():
        if lw in seen or n < MIN_CORPUS_ONLY:
            continue
        k = gkey(lw).replace(" ", "")
        if not k:
            continue
        w = lw[:1].upper() + lw[1:] if capn[lw] > 0.8 * n else lw
        rows.append((k, w, float(n)))
        extra += 1
    print(f"  + {extra:,} corpus-only forms")
    bi_low = Counter()
    for (a, b), n in bi.items():
        bi_low[(a.lower(), b.lower())] += n
    write_db(OUT / "greek.lex", rows, bi_low, "grc")


# ---- shared writer -----------------------------------------------------------

def write_db(path, rows, bi, lang):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        path.unlink()
    db = sqlite3.connect(path)
    db.executescript("""
        PRAGMA page_size = 4096;
        CREATE TABLE lex(key TEXT NOT NULL, word TEXT NOT NULL, freq INTEGER NOT NULL,
                         PRIMARY KEY(key, word)) WITHOUT ROWID;
        CREATE TABLE top(prefix TEXT PRIMARY KEY, words TEXT NOT NULL) WITHOUT ROWID;
        CREATE TABLE bi(prev TEXT NOT NULL, next TEXT NOT NULL, n INTEGER NOT NULL,
                        PRIMARY KEY(prev, next)) WITHOUT ROWID;
        CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT);
    """)
    # Store log-ish integer scores: keeps the file small and ordering intact.
    merged = {}
    for k, w, f in rows:
        merged[(k, w)] = max(merged.get((k, w), 0.0), f)
    db.executemany("INSERT INTO lex VALUES(?,?,?)",
                   ((k, w, int(round(f * 100))) for (k, w), f in sorted(merged.items())))
    best = defaultdict(list)
    for (k, w), f in merged.items():
        for i in (1, 2, 3):
            if len(k) >= i:
                best[k[:i]].append((f, w))
    db.executemany("INSERT INTO top VALUES(?,?)",
                   ((p, "\t".join(w for _, w in sorted(c, reverse=True)[:TOP_PER_PREFIX]))
                    for p, c in best.items()))
    per_prev = defaultdict(list)
    for (a, b), n in bi.items():
        if n >= MIN_BIGRAM:
            per_prev[a].append((n, b))
    db.executemany("INSERT INTO bi VALUES(?,?,?)",
                   ((a, b, n) for a, c in per_prev.items()
                    for n, b in sorted(c, reverse=True)[:BIGRAMS_PER_PREV]))
    db.executemany("INSERT INTO meta VALUES(?,?)",
                   [("lang", lang), ("schema", "1"), ("rows", str(len(merged)))])
    db.commit()
    db.execute("VACUUM")
    nbi = db.execute("SELECT count(*) FROM bi").fetchone()[0]
    db.close()
    print(f"  wrote {path.name}: {len(merged):,} words, {nbi:,} bigrams, "
          f"{path.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which in ("latin", "all"):
        build_latin()
    if which in ("greek", "all"):
        build_greek()
