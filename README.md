# Awake

A tiny macOS menu bar toggle that keeps your display awake — a clickable version of `caffeinate -d` — with an optional mouse jiggle.

- On: the display and Mac won't sleep because of inactivity.
- Off (or quit): normal sleep settings apply again.

- **Move cursor 1px when idle** (menu toggle, off by default): after a minute without input, the cursor moves 1px and straight back, so apps like Teams and Slack keep showing you as active. This needs Accessibility permission; the menu offers a shortcut to grant it.

## Build

```bash
./build.sh
open Awake.app
```

Requires the Xcode command line tools (`swiftc`). To start it at login, add `Awake.app` under System Settings → General → Login Items.
