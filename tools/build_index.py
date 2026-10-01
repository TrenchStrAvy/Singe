#!/usr/bin/env python3
"""Build Singe's term index from the English Wiktionary extract (kaikki.org).

Streams the 3.3 GB JSONL once and keeps only what Singe shows: a short gloss
per sense, its topic labels, and the expansion for abbreviations. Inflected
forms ("plural of …") are dropped. The result is one SQLite file.

    curl -sL https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl \
      | python3 tools/build_index.py build/terms.sqlite

Wiktionary content is CC BY-SA 4.0; see NOTICE.
"""

import json
import re
import sqlite3
import sys

MAX_SENSES = 6          # per word and part of speech
MAX_GLOSS = 240         # characters

SKIP_TAGS = {"form-of", "alt-of", "obsolete", "archaic", "misspelling", "nonstandard"}
ABBREV_TAGS = {"abbreviation", "initialism", "acronym", "clipping"}
EXPANSION = re.compile(
    r"^(?:\([^)]*\)\s*)?(?:initialism|acronym|abbreviation|clipping|contraction)s? of (.+?)\.?$",
    re.I)


def clean(text):
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= MAX_GLOSS else text[:MAX_GLOSS - 1].rsplit(" ", 1)[0] + "…"


def senses_of(entry):
    out = []
    for sense in entry.get("senses", []):
        tags = set(sense.get("tags", []))
        glosses = sense.get("glosses") or []
        if not glosses:
            continue
        gloss = glosses[-1]
        expansion = None
        m = EXPANSION.match(gloss)
        if m:
            expansion = m.group(1).strip()
        elif tags & SKIP_TAGS or sense.get("form_of"):
            continue
        if sense.get("alt_of") and not (tags & ABBREV_TAGS):
            continue
        topics = list(dict.fromkeys(
            sense.get("topics", []) +
            [c["name"] for c in sense.get("categories", [])
             if isinstance(c, dict) and c.get("kind") == "topical"][:4]))
        out.append({
            "gloss": clean(gloss),
            "expansion": expansion,
            "abbrev": bool(tags & ABBREV_TAGS) or bool(expansion),
            "topics": ", ".join(t.replace("-", " ") for t in topics[:4]),
        })
        if len(out) >= MAX_SENSES:
            break
    return out


def main(path):
    db = sqlite3.connect(path)
    db.executescript("""
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        DROP TABLE IF EXISTS senses;
        CREATE TABLE senses (
            term TEXT NOT NULL,       -- lowercased lookup key
            word TEXT NOT NULL,       -- as written in Wiktionary
            pos TEXT NOT NULL,
            rank INTEGER NOT NULL,    -- order within the word (Wiktionary's own ranking)
            gloss TEXT NOT NULL,
            expansion TEXT,           -- for abbreviations: what it stands for
            abbrev INTEGER NOT NULL,
            topics TEXT NOT NULL
        );
    """)
    first_gloss = {}
    rows = []
    seen = 0
    rank = {}
    for line in sys.stdin:
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        word = entry.get("word")
        if not word or entry.get("lang_code") != "en":
            continue
        seen += 1
        for s in senses_of(entry):
            key = word.lower()
            r = rank.get(key, 0)
            rank[key] = r + 1
            if r >= MAX_SENSES * 3:
                continue
            rows.append((key, word, entry.get("pos", ""), r, s["gloss"], s["expansion"],
                         int(s["abbrev"]), s["topics"]))
            if not s["expansion"] and key not in first_gloss:
                first_gloss[key] = s["gloss"]
        if len(rows) >= 50000:
            db.executemany("INSERT INTO senses VALUES (?,?,?,?,?,?,?,?)", rows)
            rows.clear()
        if seen % 200000 == 0:
            print(f"… {seen:,} entries", file=sys.stderr, flush=True)
    db.executemany("INSERT INTO senses VALUES (?,?,?,?,?,?,?,?)", rows)

    # For "Initialism of real-time strategy." keep the expansion's own definition,
    # so the popover can say what the thing is, not only what the letters mean.
    db.create_function("lookup_gloss", 1,
                       lambda e: first_gloss.get(e.lower()) if e else None)
    db.execute("""
        UPDATE senses SET gloss = COALESCE(lookup_gloss(expansion), gloss)
        WHERE expansion IS NOT NULL
    """)
    db.executescript("""
        CREATE INDEX senses_term ON senses(term, rank);
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        INSERT INTO meta VALUES ('source', 'English Wiktionary via kaikki.org (CC BY-SA 4.0)');
        INSERT INTO meta VALUES ('built', date('now'));
        VACUUM;
    """)
    db.commit()
    n = db.execute("SELECT COUNT(*), COUNT(DISTINCT term) FROM senses").fetchone()
    print(f"✓ {n[0]:,} senses for {n[1]:,} terms → {path}", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1])
