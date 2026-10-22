# Testing Singe without losing your screen

Singe acts on the app in front of you: it needs a selection, a held Control key and a
window on screen. A test that does all that for real takes over the Mac you are working
on. So the tests are split by what they need.

## 1. In the background, on your own Mac

```sh
swift build -c release
B=$(swift build -c release --show-bin-path)
SINGE_CORE=$B/libSingeCore.dylib /Applications/Singe.app/Contents/MacOS/Singe --selftest
```

(`SINGE_CORE` runs the fresh build through the installed launcher, which holds the
Accessibility permission; `.build/release/Singe --selftest` works too when your terminal
has Accessibility.)

- Opens a fixture with the term "Kerberos" in each installed test app, **hidden** and in
  the background (`open -g -j`). Your frontmost app keeps focus.
- Selects the term through Accessibility, or the page selects it itself. No clicks, no key
  presses, no ⌘C, your clipboard is never touched.
- Reads each app by its process ID (`SelectionReader.read(app:)`) and checks the term came
  back with a position inside the app's window: `highlight`, `text only` or `FAIL`.
- Apps you already have open are skipped (`--include-running` opens a test window behind
  yours and closes it afterwards). Settings it learns go to a throwaway folder.
- `--only textedit,preview` picks apps.

Other background tools:

| Command | What it does |
|---|---|
| `Singe --probe Safari` | what Singe reads in a running app (name, bundle id or pid), without bringing it forward |
| `Singe --render-menu out.png --apps` | the menu panel drawn offscreen, never shown |
| `Singe --snapshot out.png "TERM"` | highlight + popover rendered offscreen |
| `Singe --lookup "RTS/ITS"` | the ranked meanings, in the terminal |

**Not covered here:** Chromium and Electron apps (Chrome, Edge, Brave, VS Code, Cursor,
Slack) and Firefox build their page tree reliably only for the window in front; hidden,
minimized or covered by your windows they often report nothing, so the self-test skips
them (`--visible` tries anyway, behind your windows). Neither can a background test press
the real Control key or look at the drawn glass. Those need a screen of their own: below.

`tools/test_apps.py` is the older end-to-end test that clicks and holds Control for real.
It takes over the screen; run it only in a VM or when you are away.

## 2. On a screen of its own

### A macOS virtual machine

The only way to run the front-app tests on the same Mac without them touching yours.

- **Apple Silicon:** Apple's Virtualization framework runs macOS guests natively, with
  Metal through the paravirtualized GPU (the glass renders). [Tart](https://tart.run) makes
  it scriptable: `tart clone` a golden image in seconds, `tart run --no-graphics`, run the
  tests over SSH, throw the clone away.
- **Intel Macs (this iMac, i9-9900K):** the Virtualization framework does not run macOS
  guests on Intel. VMware Fusion (free for personal use) or Parallels can, but macOS guests
  get no GPU acceleration, so the Metal glass may not draw. Selection reading, the hold
  key, the popover and the Apps switches all still work.
- **"A VM of my exact desktop":** a running Mac cannot be cloned into a VM directly, but
  close enough: install the same macOS in the VM, then use Migration Assistant from a Time
  Machine backup (or over the network from this Mac) to bring your apps, settings and
  files across. Privacy permissions (Accessibility, Screen Recording) never migrate: grant
  Singe and the terminal once inside the VM, then snapshot it. Revert to the snapshot
  after each run so every test starts from the same state. Licensed apps may ask to be
  activated again.

### Docker or Kubernetes

Not for this. A container shares the host's Linux kernel; there is no macOS container,
so no WindowServer, AppKit, Metal or Accessibility, which is everything Singe is.
(Docker-OSX runs macOS in QEMU inside a Linux container: it needs a Linux host with KVM,
and Apple's licence allows macOS VMs only on Apple hardware. On a Mac, Docker itself runs
inside a Linux VM.) Kubernetes schedules containers, so it inherits the same limit;
commercial tools (Orka, Anka) orchestrate macOS VMs on Mac hardware instead.

### Continuous integration

GitHub Actions' macOS runners are macOS VMs with a real GUI session, fresh on every run:
the same isolation as a local VM with nothing to set up on your Mac. A workflow can build
Singe, grant Accessibility to the runner (check the current runner image's notes on
TCC/SIP), and run `--selftest --visible` plus `tools/test_apps.py --hold` on every push.
Private repositories pay per minute for macOS runners.

## What to use when

| You changed | Run |
|---|---|
| ranking, index, glossary | `--lookup` |
| popover or menu looks | `--snapshot`, `--render-menu` |
| reading selections, the Apps switches | `--selftest` locally; Chromium apps in a VM or CI |
| the hold key, the drawn glass | a VM or CI (`tools/test_apps.py --hold`) |
