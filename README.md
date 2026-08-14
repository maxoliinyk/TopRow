# TopRow

TopRow is a tiny native macOS utility for remapping function keys on an Apple Silicon MacBook's top row.

I don't know anyone who uses Mission Control, Spotlight, or Dictation from those keys. I don't use Apple's Dictation either — I use VoiceInk, so I wanted the Dictation key to activate it. I mapped Spotlight to Raycast too (idk why, I still use `⌘ + Space` lol).

For example:

```text
Dictation → F13

normal Dictation key → F13
Fn + Dictation key   → F5
```

TopRow can send a top-row action to an unused function key such as `F13` or `F16–F24`, or to a shortcut such as `⌘ + Space`. The regular F1–F12 layer stays available, and external keyboards are left alone.

## How it works

Built with Swift 6 and SwiftUI.

- Apple IOHID APIs update `UserKeyMapping` on the built-in keyboard.
- Existing mappings are preserved; external keyboards are ignored.
- Core Graphics HID-system events emit configured shortcuts.
- `KeyboardShortcuts` handles shortcut capture and validation.
- No driver, helper, event tap, Input Monitoring, telemetry, or cloud sync.

Direct destinations use F13, F16–F24; F14 and F15 remain reserved for brightness. Shortcut destinations require macOS Accessibility/Post Event access.

## Requirements

- macOS 26+
- Apple Silicon MacBook with keyboard (preferably)
- Xcode

## Build

Open `TopRow.xcodeproj` in Xcode. For shortcut output, copy `Config/LocalSigning.xcconfig.example` to `Config/LocalSigning.xcconfig`, add your Team ID, and build with a stable development signature.

## WIP...more later...

## License

MIT
