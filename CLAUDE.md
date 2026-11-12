# Switch Tab: project guide

Windows-style window switcher for macOS with always-on-top windows. Swift, SwiftPM, no Xcode needed (Command Line Tools only). macOS 14+.

## Commands
- Build and install: `./scripts/install.sh` (signs, builds, copies to /Applications, starts).
- Build only: `./scripts/build-app.sh` (output in `build/`).
- Debug renders: `SwitchTab --snapshot <png>` draws the panel with demo tiles; `--snapshot-preview <png>` the Preferences preview; `--snapshot-menu-icon <png>` the menu bar glyph; `--snapshot-ui <folder>` every Preferences tab and the custom menu rows.
- App icon: `swift scripts/make-icon.swift` rewrites `Resources/AppIcon.icns` (add a PNG path to only render a preview).
- Stats self-test: `SWITCHTAB_STATS_DB=<tmp.sqlite> SwitchTab --stats-selftest`.

## Rules
- Every push bumps the version in `Resources/Info.plist` (ShortVersion and Build) and `README.md`, plus a `CHANGELOG.md` entry.
- No `@State` and other SwiftUI macros: they need full Xcode. Use `@Published` on an ObservableObject.
- Stats store only app bundle IDs, never window titles. Collection stays off by default and local only.
- Do not reset or change macOS permissions (TCC) from code or scripts. The user grants them in System Settings.
- Keep the signing identity stable (`scripts/setup-signing.sh`), otherwise Accessibility and Screen Recording grants are lost on every rebuild.

## Layout
See `docs/ARCHITECTURE.md`.
