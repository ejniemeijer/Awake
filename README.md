# Awake

A tiny macOS menu bar toggle that keeps your display awake — a clickable version of `caffeinate -d`.

- On: the display and Mac won't sleep because of inactivity.
- Off (or quit): normal sleep settings apply again.

It doesn't move the cursor or fake any activity, so chat apps still show you as away when you are.

## Build

```bash
./build.sh
open Awake.app
```

Requires the Xcode command line tools (`swiftc`). To start it at login, add `Awake.app` under System Settings → General → Login Items.
