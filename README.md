# Singe

**A smarter Look Up for macOS.** Highlight a term anywhere, hold **Left Control**,
and a bar of glass settles over it while the three most relevant meanings appear.
Let go and it is gone.

Everything runs on your Mac. No account, no cloud, no API key: nothing you look up
ever leaves the machine.

```
highlight a term → hold Left ⌃ (≈0.35 s)
    → the selection becomes a bar of Sorph glass, ribbons turning inside
    → popover: the 3 most relevant meanings, ranked by what you looked up before
    → release ⌃ → closed
```

## Install

macOS 13 or later and the Xcode Command Line Tools. The repository is private, so
the one command goes through the GitHub CLI (`gh auth login` once):

```sh
zsh <(gh api -H "Accept: application/vnd.github.raw" repos/TrenchStrAvy/singe/contents/install.sh)
```

Or from a clone: `./install.sh`. The installer builds Singe (native Swift), downloads
the term index (about 53 MB, 130 MB on disk), installs **Singe** in `/Applications`, and
opens it. A splash shows the loading progress, like Sorph's.

**Once per Mac:** turn on Singe in **System Settings → Privacy & Security → Accessibility**.
macOS never lets an app grant itself this. Updates keep the permission: `Singe.app` is a
tiny launcher that stays the same, and the app itself (`libSingeCore.dylib` in
`~/Library/Application Support/Singe`) is what updates replace. On managed Macs, IT can
pre-approve it with a PPPC device-management profile.

| Flag | What it does |
|---|---|
| `--with-model` | pull `gemma3:4b` into Ollama, the fallback for terms no index knows |
| `--uninstall` | remove Singe, its index and its history |

## Use

- **Hold Left ⌃ with text highlighted.** Holding Control with nothing highlighted does nothing.
- **While holding, clicks inside work:** ★ saves the term; clicking a meaning expands it
  and teaches the ranking which reading you meant.
- **Click "Ask a follow-up"** and the popover stays open after you let go (follow-up
  questions are coming soon). `Esc` or a click outside closes it.
- **⌃-shortcuts and ⌃-click keep working.** Another key or a click during the hold cancels Singe.

The glass-bar icon in the menu bar holds your **History** (by day, with the app you were
in), **Saved** terms, and **Lists**. A list has a colour, and the colour is its mark: right-click
a term to put it in one or more lists. Sort by recent, A–Z or most looked up, search, and
**Export to Obsidian** as Markdown.

## Works in any app

Singe reads the highlighted text through the Accessibility API: native text (TextEdit,
Notes, Mail, Pages), web text markers (Safari, Chrome, Electron apps such as VS Code,
Cursor, Obsidian, Slack), and, when an app exposes neither, a ⌘C copy from a private event
source (so the Control key you are holding is not added) with your clipboard restored.
`tools/test_apps.py` checks the whole flow in TextEdit, Safari, Chrome, VS Code and Cursor.

## How it finds meanings

1. **Curated glossary**: a few dozen professional terms Wiktionary lacks or under-ranks
   (EU regulation, DORA, ICT risk, security).
2. **Term index**: English Wiktionary, condensed to 1 M senses for 735 k terms.
   Abbreviations show what they stand for.
3. **macOS Dictionary**: for ordinary words the index lacks.
4. **Local model**: `gemma3:4b` via Ollama, only when nothing above knows the term;
   its answers are labelled as such.

Meanings are ranked by **your history**, not by reading the page: each meaning you see or
choose adds its words to a small local profile, so after a few DORA terms, "RTS" means
*Regulatory Technical Standards* before *real-time strategy*.

## Works with Sorph

Sorph uses Right-Option and Singe uses Left-Control, so they never clash. Both share the
same local `gemma3:4b` and the same ribbon glass.

## Build from source

```sh
swift build -c release                    # the binary
./scripts/bundle.sh                       # build/Singe.app with its icon
.build/release/Singe --lookup "RTS/ITS"   # try the lookup in the terminal
.build/release/Singe --read-selection 2    # what Singe reads as the selection, after 2 s
.build/release/Singe --snapshot out.png "RTS/ITS" --dark   # render highlight + popover
```

The term index is built once from the Wiktionary extract on kaikki.org:

```sh
curl -sL https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl \
  | python3 tools/build_index.py build/terms.sqlite
```

`mockups/singe-design.html` is the design reference (glass, popover, menu, logo).
`docs/SPEC.md` holds the v1 decisions.

## Licence

Code: MIT (see `LICENSE`). Definitions: Wiktionary, CC BY-SA 4.0 (see `NOTICE`).
