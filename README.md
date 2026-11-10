# Switch Tab

Windows-style window switcher for macOS. Hold Option, press Tab, see every open window with a preview, release Option to jump to it. Inspired by [AltTab](https://alt-tab.app/).

Version 0.1.0. Requires macOS 14 or later.

## Use

| Keys | Action |
| --- | --- |
| Option + Tab | Open switcher, move to next window |
| Option + Shift + Tab | Move to previous window |
| Arrow keys | Move selection (while Option is held) |
| Release Option, or Return | Focus selected window |
| Escape | Cancel |
| Mouse click | Focus clicked window |

A menu bar icon shows permission status, a Launch at Login toggle, and Quit.

## Build and run

Needs only Xcode Command Line Tools (no full Xcode).

```bash
./scripts/build-app.sh
```

```bash
open build/SwitchTab.app
```

## Permissions

| Permission | Why | Required |
| --- | --- | --- |
| Accessibility | Read the shortcut globally, list and focus windows | Yes |
| Screen Recording | Window previews. Without it, tiles show app icons | No |

Grant both in System Settings, Privacy & Security. The app is ad-hoc signed, so macOS asks again after each rebuild.

## How it works

1. `Switcher.swift`: a `CGEventTap` watches the keyboard. Option + Tab opens a session and swallows keys until Option is released.
2. `WindowManager.swift`: lists windows of regular apps through the Accessibility API, ordered front to back (most recent first), minimized last.
3. `Thumbnailer.swift`: captures previews with ScreenCaptureKit, cached between sessions so the panel opens instantly.
4. `SwitcherPanel.swift`: a non-activating floating panel, so the current app keeps focus until a window is chosen.
5. `PrivateAPI.swift`: three undocumented system calls, used to map a window to its ID and to raise one window instead of the whole app.

## Known limits

- Windows on other Spaces and full-screen windows are not listed (Accessibility API only reports the current Space).
- Shortcut is fixed to Option + Tab. No preferences window yet.
- Uses undocumented macOS calls, so a future macOS release could break focusing.

## Alternatives considered

- Fork AltTab: full feature set, but needs full Xcode and is GPL-3.0.
- Replace Cmd + Tab: closer to Windows, but overrides the native app switcher.
