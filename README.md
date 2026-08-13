# TopRow

Remap the special actions on your Mac’s function row without changing the F1–F12 keys underneath them.

For example:

```text
Dictation → F13

normal Dictation key → F13
Fn + Dictation key   → F5
```

TopRow is a small native macOS utility for modern Apple Silicon MacBook keyboards. It supports direct F13–F24 destinations and ordinary keyboard shortcut destinations. Shortcut output uses macOS Post Event access only when configured.

The main window is a focused function-row editor; remapping and Launch at Login are managed from the app's native Settings window. Enable Remapping is an immediate switch, and the Keyboard Service section reports whether the built-in HID service was found, whether macOS rejected a write, or whether a saved mapping is conflicted. Shortcut destinations explain and request Post Event access in place; Accessibility and Input Monitoring are not required.

Shortcut destinations use a key-only recorder: choose Command, Option, Control, and/or Shift with the modifier buttons, then click the key field and press only the base key. This lets you configure destinations such as `⌘Space` without opening Spotlight while recording. TopRow uses the `KeyboardShortcuts` package's shortcut representation and validation, while keeping the app's own storage and runtime as the source of truth.

The app intentionally does not provide general keyboard remapping, modifier remapping, macros, per-app profiles, external keyboard profiles, telemetry, or cloud sync.

HID source usages are hardware-sensitive. The app filters for the built-in Apple keyboard and preserves unrelated `UserKeyMapping` entries, but the Phase 0 capture and cleanup proof must still be run on the specific Apple Silicon MacBook model before enabling a release build. Direct HID property writes use the personal-build app directly; no root helper, driver, event tap, or Input Monitoring permission is used.

## Phase 0 release gate

Build the read-only probe and snapshot before any manual write experiment:

```sh
xcrun swiftc -swift-version 6 \
  Tools/Phase0Probe/main.swift \
  -o /tmp/toprow-phase0-probe \
  -framework Carbon \
  -framework IOKit
/tmp/toprow-phase0-probe snapshot
/tmp/toprow-phase0-probe capture 30
```

Do not ship until the supported MacBook hardware proves all of the following:

- normal and Fn-layer usages are distinct for every supported action;
- Dictation can map to F13 without opening Dictation, while Fn + Dictation remains F5;
- a Spotlight proxy emits exactly one configured shortcut and does not recurse while held;
- F13–F24 listener support is confirmed, including any raw F21–F24 key codes;
- unrelated mappings are restored byte-for-byte or semantically identically after the experiment;
- external keyboards remain untouched and the intended signed app succeeds.

The probe is intentionally read-only. If its capture file is empty, treat that as an environment/permission result—not as evidence that a usage is absent—and perform the capture on the supported hardware with the intended app signing.

## Development

- macOS 26+
- Apple Silicon
- Swift 6 / SwiftUI
- Xcode 27+

Open `TopRow.xcodeproj` and select your own signing team for the app and test targets. The project does not include a developer-specific team or private signing configuration.

The project uses Apple HID APIs and [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts). HID source usages are hardware-sensitive; validate them on the supported built-in keyboard before enabling remapping.
