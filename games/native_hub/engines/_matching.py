"""Forgiving answer matching for typed guesses at a party.

People type fast on a phone while laughing: "ddlj", "bahubali", "the lion
king", "3 idiots!" should all count. Exact string equality made correct
guesses fail on a typo or an article.
"""

import difflib
import re

_PUNCT = re.compile(r"[^\w\s]")


def normalise(text) -> str:
    text = _PUNCT.sub(" ", str(text or "").lower())
    words = text.split()
    if words and words[0] in ("the", "a", "an"):
        words = words[1:]
    return " ".join(words)


def guess_matches(guess, answer, threshold: float = 0.85) -> bool:
    g, a = normalise(guess), normalise(answer)
    if not g or not a:
        return False
    if g == a or g.replace(" ", "") == a.replace(" ", ""):
        return True
    words = a.split()
    if len(words) >= 3 and g.replace(" ", "") == "".join(w[0] for w in words):
        return True                       # initials: "ddlj", "znmd"
    if len(a) >= 5 and difflib.SequenceMatcher(None, g, a).ratio() >= threshold:
        return True                       # small typos: "bahubali" / "baahubali"
    return False
