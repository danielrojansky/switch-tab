# Architecture

## Purpose
Hold Option, press Tab, pick a window from a live-preview panel, release to jump. Plus pinning a window above all others.

## Flow
1. `Switcher` installs a session CGEventTap (needs Accessibility). It swallows the shortcut and in-switcher keys.
2. On shortcut: `WindowManager.listWindows` builds the list (Accessibility API per app, private calls for window IDs and Spaces; `RemoteWindowScanner` finds windows on other Spaces in the background).
3. `SwitcherPanel` (non-activating NSPanel) shows tiles. `Thumbnailer` fills previews through ScreenCaptureKit. `DockBadges` adds unread counts read from the Dock process.
4. Release of the modifier (or Return) calls `WindowManager.focus`, which raises the exact window via SkyLight private calls.
5. `FocusTracker` keeps most-recently-used order.

## Always on top
macOS forbids changing another app's window level. `PinManager` places a floating `NSPanel` over the pinned window showing a live `SCStream` of it. The panel hides while the real window has focus, shows when it loses focus, and forwards clicks.

## Statistics
`StatsStore` (SQLite, `~/Library/Application Support/SwitchTab/stats.sqlite`): tables `events` and `focus`. Recorded only when `Settings.statsEnabled`. `StatsView` renders summaries; exports CSV and JSON.

## Signing
`scripts/setup-signing.sh` makes a self-signed certificate in its own keychain. A fixed designated requirement keeps TCC grants valid across rebuilds.

## Alternatives considered
- Fork AltTab: complete, but GPL-3.0 and needs full Xcode.
- True always on top by injection: needs SIP disabled, rejected.
- Swift Charts for stats: avoided, hand-drawn bars keep the build Xcode-free.
- Uploading statistics: not built. Would need explicit opt-in, aggregation and a server.
