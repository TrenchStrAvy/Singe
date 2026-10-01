# Singe v1 spec

Decisions made while designing Singe (October 2026). The mock-up in
`mockups/singe-design.html` is the visual reference.

## Purpose
Quick insight on unfamiliar terms, not thorough research. It replaces macOS Look Up,
whose results are often outdated or wrong for professional terms (e.g. "RTS/ITS" in a
DORA text came back as "Religious Trauma Syndrome") and cannot be interacted with.

## Trigger
- Hold **Left Control** for 0.35 s (adjustable: 0.25 / 0.35 / 0.5 s) with text highlighted.
- Release closes everything. Nothing highlighted: nothing happens.
- Another key, another modifier, or a click outside Singe during the hold cancels it,
  so ⌃-shortcuts and ⌃-click (right-click) behave as before.
- While open, clicks inside the popover work; ⌃-clicks there lose the Control flag so
  they act as plain clicks.
- Clicking the follow-up box pins the popover open; `Esc` or a click outside closes it.
- No Services menu entry: the hold replaces the right-click path.

## Highlight
- A rounded glass bar laid over the selection, 9 pt beyond it horizontally and 3 pt
  vertically (picked with the mock-up's size slider: size 9).
- Same physics as Sorph's orb: refracting bevel, Fresnel rim in the ribbon hues, a
  specular glint, and three ribbons ray-marched through the slab so they turn in 3D.
  Sorph hues 236°, 184°, 290° at saturation 0.40.
- Opens with a small spring overshoot and a stir of the ribbons that settles in ~1 s.
- The term is redrawn clean on top: no refraction, outline or halo on the letters.
  White on dark glass, near-black on light glass, following the system appearance.
  Ribbons run calmer behind a term (55 % dark, 80 % light).
- Drawn in a click-through window; the original app is untouched. No Screen Recording
  permission is needed.

## Popover (variant B)
Native macOS popover material and system font; the highlight is the only Sorph element.
Contents: the term and a ★; up to three meanings (headline, chip, the first expanded);
"Ranked by your history · …"; "Ask a follow-up…" with a *Coming soon* tag; footer with
"Release ⌃ to close" and the source.

## Meanings (slim, local)
1. Curated glossary bundled in the app (KB).
2. Wiktionary term index, ~130 MB on disk (~53 MB download), one file.
3. macOS Dictionary Services for ordinary words.
4. Local model (Ollama `gemma3:4b`, shared with Sorph) only when nothing else knows
   the term; labelled as model output.
No page or surrounding-text scanning. No downloadable packs.

## Ranking
Each candidate is a bag of words (headline, definition, topics). A profile of weighted
words grows from meanings shown (+1) and meanings tapped (+3). Score = Wiktionary
order prior + affinity to the profile. A meaning chosen before for the same term comes
first again. Slash-joined terms ("RTS/ITS") are looked up whole and per part.

## History and lists (menu bar)
- History grouped by day, with the source app and time; search; sort by Recent, A–Z,
  Most looked up.
- Saved = starred terms.
- Lists have a colour; a list's colour is its mark (marks and lists are one system).
  A term can be in several lists. Filter by colour or by list.
- Export to Obsidian (Markdown).
- Open at login (on by default), hold delay, quit.

## Platform
Native Swift (AppKit + SwiftUI + Metal), macOS 13+, Intel and Apple Silicon (built on
the machine). Needs Accessibility access. Ad-hoc signed; after an update the
Accessibility switch has to be toggled again.

## Later
- Follow-up questions (typed, or dictated with Sorph's Right-Option).
- Hold ⌃ and drag over words with nothing selected: the glass stretches over the drag.
- Website: sentences cycling, the glass bar gliding onto key words with the popover.
