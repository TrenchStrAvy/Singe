#!/bin/zsh
# Singe installer: a smarter Look Up for macOS. Highlight a term, hold Left Control.
#
# One command (the repository is private, so it goes through the GitHub CLI):
#
#   zsh <(gh api -H "Accept: application/vnd.github.raw" repos/TrenchStrAvy/singe/contents/install.sh)
#
# or, from a clone:   ./install.sh
#
# What it does (all local; nothing you look up ever leaves the Mac):
#   1. checks macOS 13+ and the Swift toolchain (Xcode Command Line Tools)
#   2. fetches or updates the source in ~/.singe/src
#   3. builds Singe.app (native Swift, ~2 MB) with its glass-bar icon
#   4. downloads the term index (Wiktionary, ~53 MB compressed, ~130 MB on disk)
#   5. installs Singe in /Applications (or ~/Applications) and opens it
#
# Flags:
#   --with-model   also pull gemma3:4b into Ollama (the fallback for unknown terms)
#   --uninstall    remove Singe, its index and its history
#
# Re-running is safe: it updates the source, rebuilds, and keeps your history.

set -euo pipefail

repo=TrenchStrAvy/singe
index_tag=index-v1
src="$HOME/.singe/src"
support="$HOME/Library/Application Support/Singe"
with_model=false
uninstall=false

for arg in "$@"; do
  case $arg in
    --with-model) with_model=true ;;
    --uninstall)  uninstall=true ;;
    -h|--help)    sed -n '2,25p' "${0:A}" 2>/dev/null || true; exit 0 ;;
    *) print -u2 "unknown flag: $arg (see --help)"; exit 64 ;;
  esac
done

say()  { print -P "%F{cyan}▸%f $*"; }
ok()   { print -P "%F{green}✓%f $*"; }
warn() { print -P "%F{yellow}!%f $*"; }
die()  { print -u2 -P "%F{red}✗%f $*"; exit 1; }

installed_app() {
  for d in /Applications "$HOME/Applications"; do
    [[ -d "$d/Singe.app" ]] && { print "$d/Singe.app"; return 0; }
  done
  return 1
}

# uninstall --------------------------------------------------------------------
if $uninstall; then
  pkill -x Singe 2>/dev/null || true
  if app=$(installed_app); then rm -rf "$app"; ok "removed $app"; fi
  rm -rf "$support" "$HOME/.singe"
  defaults delete app.singe.Singe 2>/dev/null || true
  ok "Singe removed. You can also remove it from Privacy & Security → Accessibility."
  exit 0
fi

# 1. platform ------------------------------------------------------------------
[[ $(uname -s) == Darwin ]] || die "Singe supports macOS only"
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 13 )) || die "macOS 13 or later required (found $(sw_vers -productVersion))"
if ! xcrun --find swift >/dev/null 2>&1; then
  warn "the Swift toolchain is missing; opening the Command Line Tools installer"
  xcode-select --install 2>/dev/null || true
  die "finish installing the Command Line Tools, then run this command again"
fi
ok "macOS $(sw_vers -productVersion), $(swift --version 2>/dev/null | head -1 | sed 's/.*\(Swift version [0-9.]*\).*/\1/')"

# 2. source --------------------------------------------------------------------
here=${0:A:h}
if [[ -f "$here/Package.swift" && -d "$here/Sources/Singe" ]]; then
  root=$here                                    # run from a clone
else
  mkdir -p "${src:h}"
  if [[ -d "$src/.git" ]]; then
    say "updating the source"
    git -C "$src" pull --ff-only --quiet || warn "could not update; building the copy already here"
  else
    say "fetching the source"
    if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
      gh repo clone "$repo" "$src" -- --quiet --depth 1
    else
      git clone --quiet --depth 1 "https://github.com/$repo.git" "$src" \
        || die "could not clone $repo (it is private: install the GitHub CLI and run 'gh auth login')"
    fi
  fi
  root=$src
fi
cd "$root"
ok "source in $root"

# 3. build ---------------------------------------------------------------------
say "building Singe (first build takes a minute)"
./scripts/bundle.sh >/dev/null
ok "built Singe.app $(cat VERSION)"

# 4. term index ----------------------------------------------------------------
mkdir -p "$support"
if [[ ! -s "$support/terms.sqlite" || "$(cat "$support/index-tag" 2>/dev/null)" != "$index_tag" ]]; then
  say "downloading the term index (~53 MB)"
  tmp=$(mktemp -d)
  if command -v gh >/dev/null && gh release download "$index_tag" -R "$repo" -p terms.sqlite.gz -D "$tmp" 2>/dev/null; then
    :
  elif curl -fsSL "https://github.com/$repo/releases/download/$index_tag/terms.sqlite.gz" -o "$tmp/terms.sqlite.gz" 2>/dev/null; then
    :
  elif [[ -s build/terms.sqlite ]]; then
    gzip -c build/terms.sqlite > "$tmp/terms.sqlite.gz"
  else
    warn "no prebuilt index reachable; building it from Wiktionary (streams ~3.3 GB once, about 15 minutes)"
    curl -sL https://kaikki.org/dictionary/English/kaikki.org-dictionary-English.jsonl \
      | python3 tools/build_index.py "$tmp/terms.sqlite" && gzip "$tmp/terms.sqlite"
  fi
  [[ -s "$tmp/terms.sqlite.gz" ]] || die "could not get the term index"
  gunzip -c "$tmp/terms.sqlite.gz" > "$support/terms.sqlite.part"
  mv "$support/terms.sqlite.part" "$support/terms.sqlite"
  print "$index_tag" > "$support/index-tag"
  rm -rf "$tmp"
  ok "term index ready ($(du -h "$support/terms.sqlite" | cut -f1 | tr -d ' '))"
else
  ok "term index already installed"
fi

# optional: the local model for terms no index knows
if command -v ollama >/dev/null; then
  if ollama list 2>/dev/null | grep -q '^gemma3:4b'; then
    ok "local model gemma3:4b found (shared with Sorph)"
  elif $with_model; then
    say "pulling gemma3:4b (~3.3 GB)"
    ollama pull gemma3:4b && ok "local model ready"
  else
    warn "optional: 'ollama pull gemma3:4b' lets Singe explain terms no index knows"
  fi
else
  warn "optional: install Ollama + gemma3:4b to explain terms no index knows (Singe works without it)"
fi

# 5. install -------------------------------------------------------------------
dest=/Applications
[[ -w $dest ]] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
pkill -x Singe 2>/dev/null && sleep 0.5 || true
rm -rf "$dest/Singe.app"
cp -R build/Singe.app "$dest/Singe.app"
xattr -cr "$dest/Singe.app" 2>/dev/null || true
touch "$dest/Singe.app"                         # refresh the Dock / Finder icon
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$dest/Singe.app" 2>/dev/null || true
open "$dest/Singe.app"
ok "installed $dest/Singe.app and opened it"

print
print -P "%BNext:%b macOS asks for %BAccessibility%b access. Turn on %BSinge%b in"
print    "  System Settings → Privacy & Security → Accessibility."
print    "  (After an update, switch it off and on again: the new build has a new signature.)"
print
print -P "%BUse:%b highlight a term anywhere, then hold %BLeft Control%b. Let go to close."
print    "  Your history, saved terms and lists live under the glass-bar icon in the menu bar."
