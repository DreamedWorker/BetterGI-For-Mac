# BetterGI for Mac

macOS port of [BetterGI](https://github.com/babalae/better-genshin-impact) (GPL-3.0), for the game
running under Wine via the Yaagl launcher. Because the game window belongs to a `wine` process, the
capture window is chosen manually from a list.

## How it is put together

Upstream's non-UI C# code (tasks, recognition, triggers, scripting) is compiled **unmodified** from
`upstream/`. Three mechanisms make that possible:

- **Exclusions** (`src/BetterGI.Core/Exclude.props`): files that are Windows-only by nature.
- **Stand-ins** (`src/BetterGI.Core/Shims`, `src/BetterGI.Core/Mac`, `src/BetterGI.Mac.Platform`): WPF / WinForms /
  GDI+ types and the excluded classes, re-implemented or left inert under their upstream names.
- **Win32 compatibility layer** (`native/BgiMacNative/Win32Compat.swift`): the few dozen `user32` / `gdi32` /
  `kernel32` functions upstream still calls are redirected to macOS implementations.

Performance adjustments are applied the same way: upstream's `Cv2.MatchTemplate` calls go to a parallel
version (`src/BetterGI.Core/Mac/FastMatch.cs`; OpenCV's own runs on one core on Apple Silicon), the forced GC every
2 s in the capture loop is dropped, and the auto-enter-game trigger only runs its full-screen OCR when the popup
button is present. `BetterGI --perftest` measures the capture loop (stalls, GC, CPU) without sending input.

A few members and whole files are copied from upstream with documented patches by
`scripts/extract-upstream-members.py` into `src/BetterGI.Core/Mac/Generated/`; the same script generates the
service registration and the settings descriptions. Re-run it after updating `upstream/`.

## Layout

| Path | What |
| --- | --- |
| `upstream/` | Shallow clone of upstream. Not modified. |
| `native/BgiMacNative/` | Swift library (C ABI): window list, ScreenCaptureKit capture, CGEvent input, keychain, Win32 subset. |
| `src/BetterGI.Mac.Platform/` | .NET wrapper over the native library; capture, input, hotkeys, `System.Drawing` subset. |
| `src/BetterGI.Core/` | Upstream's non-UI code plus the stand-ins and the macOS composition root (`MacAppHost`). |
| `src/BetterGI.Mac/` | Avalonia app. `Pages/`: Home, Triggers, Tasks, Scripts, Pathing, Macros, Scheduler, Settings. |
| `scripts/` | `core-errors.sh`, `coretest.sh` (regenerate, build, headless core test), `ui-snapshot.sh` (render a page to PNG). |
| `packaging/`, `build-dmg.sh` | Disk image for distribution. |

## Build and run

Needs the .NET 10 SDK and the Xcode Command Line Tools (full Xcode is not required). Apple Silicon only.

```bash
./build-app.sh
```

```bash
open dist/BetterGI.app
```

Disk image for other Macs (`dist/BetterGI-<version>-arm64.dmg`; see the script header for signing and notarising):

```bash
./build-dmg.sh
```

Headless checks (no input is sent):

```bash
dist/BetterGI.app/Contents/MacOS/BetterGI --selftest
```

```bash
dist/BetterGI.app/Contents/MacOS/BetterGI --coretest
```

`--selftest` lists windows and permissions (add `--window <id> --out frame.png` to capture one frame).
`--coretest` boots upstream's core, runs every real-time trigger on a blank frame, and checks OCR, the
JavaScript engine, the git library and the task registry.

## Permissions

- **Screen Recording**: capture and window titles. Quit and reopen the app after granting.
- **Accessibility**: keyboard / mouse injection.

The bundle is ad-hoc signed, so macOS asks for both again after each rebuild. Set
`CODESIGN_IDENTITY` to a stable certificate name when running `build-app.sh` to avoid that.

User data, config and upstream's logs: `~/Library/Application Support/BetterGI/`
App log: `~/Library/Logs/BetterGI-Mac/app.log`

## What works through the app

- Real-time triggers, solo tasks, JS scripts, pathing routes, macro playback and script groups, all run by
  upstream's own code. Settings for all of it are edited on the Settings / Triggers pages.
- The script repository is updated with git and scripts are imported from it on the Scripts page.

## Not working on macOS yet

- Overlay ("mask") window, skill-cooldown overlay, HTML overlays, picture-in-picture.
- Key / mouse recording and the `keyMouseHook` script API (need a global event tap).
- Upstream's hotkey page (only ⌥P pause exists), Pulonia task plans / one-dragon editor, map tools, account pages.
- The script repository web page and other WebView2 pages; the cloud-game web runtime.
- Hardware-accelerated inference (CPU only; CoreML not wired).
- Launching the game (Yaagl does that), multi-instance / child sessions, auto-update.
- Options that are lists or nested objects are not editable in the Settings page (edit `User/config.json`).
- Text drawn into debug images uses a Latin font, so Chinese labels show as `?`.
