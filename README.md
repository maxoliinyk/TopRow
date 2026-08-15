# Top Row

Top Row is a tiny native macOS utility for remapping function keys on an Apple Silicon MacBook's top row.

I don't know anyone who uses Mission Control, Spotlight, or Dictation from those keys. I don't use Apple's Dictation either — I use VoiceInk, so I wanted the Dictation key to activate it. I mapped Spotlight to Raycast too (idk why, I still use `⌘ + Space` lol).

For example:

```text
Dictation → F13

normal Dictation key → F13
Fn + Dictation key   → F5
```

Top Row can send a top-row action to an unused function key such as `F13` or `F16–F24`, or to a shortcut such as `⌘ + Space`. The regular F1–F12 layer stays available, and external keyboards are left alone.

## How it works

Built with Swift 6 and SwiftUI.

- Apple IOHID APIs update `UserKeyMapping` on the built-in keyboard.
- Existing mappings are preserved; external keyboards are ignored.
- Core Graphics HID-system events emit configured shortcuts.
- `KeyboardShortcuts` handles shortcut capture and validation.
- `Defaults` provides typed, migratable UserDefaults-backed settings.
- No driver, helper, event tap, Input Monitoring, telemetry, or cloud sync.

Direct destinations use F13, F16–F24; F14 and F15 remain reserved for brightness. Shortcut destinations require macOS Accessibility/Post Event access.

## Requirements

- macOS 26+
- Apple Silicon MacBook with keyboard (preferably)
- Xcode

## Build

Open `TopRow.xcodeproj` in Xcode. For shortcut output, copy `Config/LocalSigning.xcconfig.example` to `Config/LocalSigning.xcconfig`, add your Team ID, and build with a stable development signature.

## Roadmap

Top Row is intentionally growing in small, hardware-validated steps. This is a
permanent checklist: completed items stay checked so the history remains visible.

### Completed

- [x] Compact, centered main window with the product name **Top Row**.
- [x] Native-style Settings tabs: General, Appearance, Permissions, and About.
- [x] Typed `Defaults` storage with migration from the original UserDefaults keys,
  preserving mappings, visibility, Launch at Login, and HID ownership.
- [x] Versioned profile data foundation with a global profile, app-profile
  bundle-ID overrides, independent normal/Fn destinations, and Codable migration
  tests.

### Next

- [ ] **Two-layer profiles** — prove both the normal and Fn behavior for each key,
  so a game can use F1–F12 normally while brightness and media actions remain
  available with Fn.
- [ ] **App-specific profiles** — match frontmost apps by bundle identifier and
  switch profiles automatically, with a master toggle and the global profile as
  the fallback.
- [ ] **Profile editor** — create an app profile by copying the global profile,
  then edit normal and Fn destinations side by side.
- [ ] **Safe activation** — serialize focus changes, verify HID writes, and keep
  the last known-good mapping when a switch fails.
- [ ] **Hardware validation** — prove the behavior on the intended Apple Silicon
  MacBook before enabling the feature for everyday use.

External keyboards, general-purpose remapping, per-window profiles, cloud sync,
and telemetry remain out of scope.

## License

MIT
