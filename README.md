# Jiggler

A tiny macOS menu bar app that keeps you "active" while you're away.

- Keeps the display awake while enabled.
- After you've been idle for the chosen time (30 s, 1, 2 or 5 min), it tells macOS there is user activity.
- Optionally nudges the cursor 1px and back, so apps like Teams and Slack don't mark you as away. This needs Accessibility permission (the menu offers a shortcut to grant it).

## Build

```bash
./build.sh
open Jiggler.app
```

Requires the Xcode command line tools (`swiftc`). To start it at login, add `Jiggler.app` under System Settings → General → Login Items.
