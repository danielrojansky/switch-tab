# Changelog

## 0.5.0
- New app icon (stacked windows with a Tab arrow) and a matching menu bar glyph. `scripts/make-icon.swift` regenerates `Resources/AppIcon.icns`.
- Switcher: key hints bar and position counter (optional), tiles drawn as cards with a hover state, window buttons also on the selected thumbnail, dimmed titles for minimized and hidden windows, tooltips with the full title.
- Menu bar menu: sections with icons, Style submenu, quick toggles for all Spaces and key hints, pinned windows listed with app icons, permission items only while a permission is missing.
- Preferences: live preview of the switcher, permission status with a shortcut to System Settings, keycap-style shortcut list, excluded apps shown with name and icon.
- README roadmap: prioritized feature suggestions from similar apps.

## 0.4.1
- Documentation: added CHANGELOG, CLAUDE.md (project guide), docs/ARCHITECTURE.md, README roadmap.

## 0.4.0
- Opt-in local usage statistics (SQLite, bundle IDs only): switches, active time per app, app pairs, hourly pattern, actions.
- Statistics tab with charts, CSV and JSON export, Delete All Data.

## 0.3.0
- Dock badges (unread counts) shown on switcher tiles.

## 0.2.0
- Windows from other Spaces and full-screen windows.
- Preferences window (shortcuts, appearance, exclusions, launch at login).
- Visual effects: glass panel, spring pop-in, staggered tiles, rotating gradient glow.
- Window actions (close, minimize, full screen, hide, quit).
- Always on top via live mirror panels.
- Stable local code signing so permission grants survive rebuilds.
- Install script (copies to /Applications).

## 0.1.0
- First version: Option + Tab switcher with live previews, SwiftPM only (no Xcode).
