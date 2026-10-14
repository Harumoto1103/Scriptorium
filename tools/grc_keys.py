"""Greek typing key, shared with the keyboard engine (Folding.greekKey in Swift).

Taken from the author's own Ancient Greek dictionary project (grc.py), trimmed
to the one function the lexicon builder needs.

    gkey("λῡ́ω") == gkey("ΛΥΩ") == gkey("λύω") == "λυω"
"""
import re
import unicodedata

# Greek letters we keep: α–ω plus the archaic digamma / koppa / sampi.
_GREEK_OK = "α-ωϝϟϡ"
_GREEK_RE = re.compile(f"[^{_GREEK_OK} ]")
_HAS_GREEK = re.compile(f"[{_GREEK_OK}Ά-ώἀ-῿Α-Ω]")

# final / lunate / archaic sigma -> σ
_SIGMA = {"ς": "σ", "ϲ": "σ", "Ϲ": "σ"}


def _strip_marks(s):
    s = unicodedata.normalize("NFD", s)
    return "".join(c for c in s if not unicodedata.combining(c))


def is_greek(s):
    return bool(_HAS_GREEK.search(s or ""))


def gkey(s):
    """Greek-script key: lowercase, no diacritics, no final sigma."""
    if not s:
        return ""
    s = _strip_marks(s.strip().lower()).lower()
    for k, v in _SIGMA.items():
        s = s.replace(k, v)
    return _GREEK_RE.sub("", s).strip()


# ---- transliteration --------------------------------------------------------
# Aspirates/affricates go through single-char placeholders so that the later
