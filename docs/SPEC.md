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
  Always dark glass with white text, on dark and white pages alike (chosen from the four
  pairings in `mockups/highlight-contrast`). Ribbons run calmer behind a term (55 %).
- Drawn in a click-through window; the original app is untouched. No Screen Recording
  permission is needed.
- Drawn only where the app says where the selection is (one line, under 60 pt tall) and
  the app's Highlight switch is on; otherwise the popover points at the text field or the
  pointer.

## Apps (menu bar, Apps tab)
- Every app Singe is used in is listed with its icon, lookups, how many placed the
  highlight, and a **Highlight** switch (on by default).
- On: Singe asks the app for positions. Electron answers `AXManualAccessibility`. If a
  lookup comes back without a position, Singe turns on the app's full accessibility mode
  (`AXEnhancedUserInterface`, VoiceOver's switch) once per launch, waits up to 2 s, and
  keeps it if the app then reports positions (checked again after 5 s for slow builders
  such as Chrome 155, which ignores `AXManualAccessibility`). Kept apps get the mode each
  time they come to the front. Apps that still give nothing go back to normal.
- Off: meanings only; Singe never changes that app's accessibility settings and turns them
  back off if it had.
- The full mode is not sent to apps that do not need it: it can change how an app
  animates its windows (window managers notice).
- No app is special-cased in code; the switch is the user's control.

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

## History and collections (menu bar)
- History grouped by day, with the source app and time; search; sort by Recent, A–Z,
  Most looked up.
- Saved = terms with a saved meaning (or starred in History).
- Collections have no colour. They hold meanings, not just words: the star next to a
  meaning in the popover files that meaning into one or more collections, or a new one.
  Opening a collection shows each saved meaning with its definition.
- Export to Obsidian (Markdown).
- Open at login (on by default), hold delay, quit.
- Apps: see above.

## Platform
Native Swift (AppKit + SwiftUI + Metal), macOS 13+, Intel and Apple Silicon (built on
the machine). Needs Accessibility access, granted once per Mac. `Singe.app` is a launcher
that stays unchanged (it holds the permission) and loads `libSingeCore.dylib` from
Application Support, which updates replace. A startup card shows loading progress: white, rounded like a macOS window ("About This
Mac" style), 410 × 202 pt, the live glass bar on top, name, caption and progress bar in
black. Sorph uses the same card with its orb.

## Later
- Follow-up questions (typed, or dictated with Sorph's Right-Option).
- Hold ⌃ and drag over words with nothing selected: the glass stretches over the drag.
- Website: sentences cycling, the glass bar gliding onto key words with the popover.
