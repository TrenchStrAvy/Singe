#!/usr/bin/env python3
"""End-to-end check of Singe across real apps (needs a terminal with Accessibility access
and pyobjc; Sorph's venv has it).

This one clicks and holds Control for real, so it takes over the screen: run it in a VM or
CI (docs/TESTING.md). On your own Mac, use `Singe --selftest`, which runs in the background.

For each app: open a file containing one term, select it with ⌘A, then either
  --reader   run `Singe --read-selection` and print what it reads, or
  --hold     simulate holding Left Control and check the lookup landed in a temp history.

    python3 tools/test_apps.py --reader
    python3 tools/test_apps.py --hold      # with `SINGE_HOME=/tmp/singe-e2e Singe` running
"""

import os
import sqlite3
import subprocess
import sys
import time

import Quartz as Q

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SINGE = os.path.join(ROOT, ".build/release/Singe")
TMP = "/tmp/singe-apps"
TERM = "TLPT"
HOLDS = 4

APPS = [
    ("TextEdit", "term.txt"),
    ("Safari", "term.html"),
    ("Google Chrome", "term.html"),
    ("Visual Studio Code", "term.md"),
    ("Cursor", "term.md"),
    ("Notes", None),
]

src = Q.CGEventSourceCreate(Q.kCGEventSourceStatePrivate)


def key(code, flags=0, down=True):
    e = Q.CGEventCreateKeyboardEvent(src, code, down)
    Q.CGEventSetFlags(e, flags)
    Q.CGEventPost(Q.kCGHIDEventTap, e)


def select_all():
    key(0, Q.kCGEventFlagMaskCommand, True)     # A
    key(0, Q.kCGEventFlagMaskCommand, False)


def hold_left_control(seconds):
    e = Q.CGEventCreateKeyboardEvent(src, 59, True)
    Q.CGEventSetType(e, Q.kCGEventFlagsChanged)
    Q.CGEventSetFlags(e, Q.kCGEventFlagMaskControl)
    Q.CGEventPost(Q.kCGHIDEventTap, e)
    time.sleep(seconds)
    e = Q.CGEventCreateKeyboardEvent(src, 59, False)
    Q.CGEventSetType(e, Q.kCGEventFlagsChanged)
    Q.CGEventSetFlags(e, 0)
    Q.CGEventPost(Q.kCGHIDEventTap, e)


def prepare():
    os.makedirs(TMP, exist_ok=True)
    open(f"{TMP}/term.txt", "w").write(TERM)
    open(f"{TMP}/term.md", "w").write(TERM)
    # the page selects the term itself (a synthetic click doesn't always reach Safari's page),
    # and again a moment later, once the browser's accessibility is up
    open(f"{TMP}/term.html", "w").write(
        f"<html><body style='font:24px sans-serif'><p id='t'>{TERM}</p><script>"
        "function pick() { const r = document.createRange(); r.selectNodeContents(document.getElementById('t'));"
        " getSelection().removeAllRanges(); getSelection().addRange(r); }"
        "pick(); setTimeout(pick, 1000); setTimeout(pick, 2000);</script></body></html>")


def open_app(app, file):
    if file:
        subprocess.run(["open", "-a", app, f"{TMP}/{file}"], check=False, timeout=30)
    else:
        subprocess.run(["open", "-a", app], check=False, timeout=30)
    time.sleep(6 if app in ("Visual Studio Code", "Cursor") else 2.5)
    # bring it forward again without AppleScript, which would wait on an Automation prompt
    subprocess.run(["open", "-a", app], check=False, timeout=30)
    time.sleep(0.8)


def history_terms(home):
    db = os.path.join(home, "history.sqlite")
    if not os.path.exists(db):
        return []
    return [r[0] for r in sqlite3.connect(db).execute("SELECT term FROM terms ORDER BY last_seen DESC")]


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--reader"
    prepare()
    home = os.environ.get("SINGE_HOME", "/tmp/singe-e2e")
    results = []
    only = sys.argv[2:]
    for app, file in APPS:
        if only and app not in only:
            continue
        if not os.path.exists(f"/Applications/{app}.app") and not os.path.exists(f"/System/Applications/{app}.app"):
            continue
        if file is None:
            continue
        print(f"… {app}")
        open_app(app, file)
        if not file.endswith(".html"):
            select_all()
        time.sleep(0.4)
        if mode == "--reader":
            out = subprocess.run([SINGE, "--read-selection", "0"], capture_output=True, text=True, timeout=60).stdout.strip()
            ok = f"text: {TERM}" in out
            results.append((app, ok, out.replace("\n", " | ")))
        else:
            # A browser just opened can take several seconds to build its page tree for Singe
            # (Chrome switches on its full accessibility mode on the first lookup), so a miss
            # is retried like a person would; the report says how many holds it took.
            before = len(history_terms(home))
            for attempt in range(1, HOLDS + 1):
                hold_left_control(1.2)
                time.sleep(0.5)
                terms = history_terms(home)
                ok = len(terms) > before or bool(terms and terms[0] == TERM)
                if ok:
                    break
                time.sleep(2.5)
            results.append((app, ok, f"history: {terms[:3]}, {attempt} hold{'s' if attempt > 1 else ''}"))
            # forget it so the next app counts as a new lookup
            if terms:
                sqlite3.connect(os.path.join(home, "history.sqlite")).execute("DELETE FROM terms").connection.commit()
    print()
    for app, ok, detail in results:
        print(f"{'✓' if ok else '✗'} {app:20} {detail}")
    sys.exit(0 if results and all(ok for _, ok, _ in results) else 1)


if __name__ == "__main__":
    main()
