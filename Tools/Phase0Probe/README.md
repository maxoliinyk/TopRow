# Phase 0 probe

This temporary macOS tool makes the hardware gate repeatable without changing keyboard state.

Build it from the repository root:

```sh
xcrun swiftc -swift-version 6 \
  Tools/Phase0Probe/main.swift \
  -o /tmp/toprow-phase0-probe \
  -framework Carbon \
  -framework IOKit
```

Snapshot the current state first:

```sh
/tmp/toprow-phase0-probe snapshot
```

Capture observed built-in-keyboard value-down events while pressing normal and Fn-layer function-row keys:

```sh
/tmp/toprow-phase0-probe capture 30
```

The output directory contains:

- `user-key-mapping.txt` — the current `hidutil` mapping view.
- `hid-list.ndjson` — matching HID services/devices.
- `services.xml` — the HID event-system dump.
- `services-structured.json` — per-service registry, product, transport, built-in, conformance, and mapping data.
- `events.ndjson` — observed page/usage/value records for the built-in Apple keyboard.

The probe is deliberately read-only. It does not call `hidutil property --set`, does not write `UserKeyMapping`, does not install an event tap, and does not request Input Monitoring. Apply/restore proof remains an explicit manual step through TopRow’s ownership-aware service boundary on a supported MacBook, with the original snapshot retained for comparison.
