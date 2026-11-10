# Switch Tab

Windows-style window switcher for macOS, with always-on-top windows. Hold Option, press Tab, see every open window with a live preview, release Option to jump to it. Inspired by [AltTab](https://alt-tab.app/).

Version 0.4.1. Requires macOS 14 or later.

## Features

| Area | What you get |
| --- | --- |
| Switching | All windows of all apps, across Spaces, including minimized, hidden and full-screen windows |
| Second shortcut | Option + ` cycles only the windows of the current app |
| Always on top | Pin any window so it stays above everything else (T in the switcher, or Control + Option + T) |
| Window actions | Close, minimize, full screen, hide app, quit app, straight from the switcher |
| Three styles | Thumbnails, App Icons, Titles, each in Small, Medium, Large |
| Effects | Blurred glass panel, spring pop-in, cascading tiles, sliding selection with a rotating gradient glow, crossfading previews |
| Themes | Match system, Light, Dark |
| Badges | Dock badges (unread counts), pinned, minimized, hidden, full screen, Space number |
| Mouse | Hover to select, click to focus, hover buttons for close, minimize, full screen, pin |
| Preferences | Shortcuts, appearance, which windows to show, sort order, excluded apps |
| Statistics | Opt-in, local only: switches, active time per app, common app pairs, hourly pattern, export to CSV or JSON |
| System | Menu bar icon (optional), launch at login |

## Keys

| Keys | Action |
| --- | --- |
| Option + Tab | Open switcher, next window |
| Option + ` | Open switcher for the current app only |
| Shift + trigger key, arrow keys | Move selection |
| Release Option, or Return | Focus selected window |
| Escape | Cancel |
| W / M / F | Close / minimize or restore / toggle full screen |
| T | Keep selected window on top, or stop |
| H / Q | Hide or show app / quit app |
| Control + Option + T | Keep the focused window on top (works anywhere) |

Both shortcuts can be changed in Preferences (Option, Command or Control, with Tab, ` or Space). Choosing Command + Tab switches off the built-in macOS app switcher while Switch Tab runs, and restores it on quit.

## Always on top

macOS does not allow one app to change the stacking level of another app's window. Switch Tab works around that:

1. A pinned window gets a floating live mirror placed exactly over it.
2. While the real window has focus, the mirror hides and you work in the real window.
3. When another window comes forward, the mirror appears on top, updating live.
4. Clicking the mirror brings the real window back and passes the click through.

The mirror has an accent border and an unpin button in its top right corner. Pinned windows are also listed in the menu bar menu.

## Statistics

Off by default. Switch on in Preferences, Statistics.

| Collected | Used for |
| --- | --- |
| Switch events (from app, to app, Tab presses) | Common app pairs, switches per hour, selection depth |
| Active time per app per day (paused after 60 seconds idle) | Time by app |
| Switcher opens, cancels, open window count | Cancel rate, average clutter |
| Actions (close, minimize, full screen, hide, quit, pin) | Feature use |

Only app bundle IDs are stored, never window titles or content. Data lives in `~/Library/Application Support/SwitchTab/stats.sqlite` and never leaves the Mac. The Statistics tab shows the charts, exports CSV or JSON, and can delete everything.

## Install

Needs only Xcode Command Line Tools (no full Xcode).

```bash
./scripts/install.sh
```

This creates a local signing certificate (first run only), builds, copies the app to `/Applications/SwitchTab.app` and starts it. Launch at login is switched on at the first start from Applications.

## Permissions

| Permission | Why | Required |
| --- | --- | --- |
| Accessibility | Read the shortcut globally, list and control windows | Yes |
| Screen Recording | Window previews and always on top | For previews and pinning |

Grant both in System Settings, Privacy & Security. Thanks to the local signing certificate, the grants survive rebuilds.

## How it works

| File | Role |
| --- | --- |
| `Switcher.swift` | Global keyboard tap and the switching session |
| `WindowManager.swift` | Window list (Accessibility API), Spaces, focus history, window actions |
| `SwitcherPanel.swift` | The panel, its three layouts and all animations |
| `Thumbnailer.swift` | Window previews through ScreenCaptureKit, cached between sessions |
| `PinManager.swift` | Always on top (live mirror panels) |
| `Settings.swift`, `PreferencesView.swift` | Preferences storage and window |
| `Stats.swift`, `StatsView.swift` | Local usage statistics (SQLite) and the Statistics tab |
| `PrivateAPI.swift` | Undocumented system calls: window IDs, Spaces, raising one window |
| `scripts/setup-signing.sh` | One-time self-signed certificate in its own keychain |

## Not included (AltTab has these)

- Drag and drop files onto a window in the switcher
- Fully custom key recorder (any key combination) and more than two shortcuts
- Per-shortcut filters, per-screen filtering
- Translations, VoiceOver support, auto-update

## Known limits

- A pinned window that is not focused is a live picture: a click activates the real window first. Dragging the mirror does not move the window.
- macOS shows its screen recording indicator while a window is pinned.
- Windows on other Spaces are found by a background scan every few seconds, so a brand new window there can take a moment to appear.
- Uses undocumented macOS calls, so a future macOS release could break parts of it.

## Roadmap

- Drag and drop onto windows, free-form key recorder, more shortcuts
- Translations, VoiceOver, auto-update
- Optional upload of aggregate statistics (explicit opt-in, not built)

## Documentation

- [CHANGELOG.md](CHANGELOG.md): version history
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): flow, always-on-top design, stats, signing
- [CLAUDE.md](CLAUDE.md): project guide for contributors and AI assistants

## Alternatives considered

- Fork AltTab: full feature set, but needs full Xcode and is GPL-3.0.
- True always on top through code injection: needs System Integrity Protection disabled, so not used.
