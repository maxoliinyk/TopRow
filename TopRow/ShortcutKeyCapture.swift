//
//  ShortcutKeyCapture.swift
//  TopRow
//
//  A key-only shortcut input. Modifiers are selected in SwiftUI; this view
//  captures only the base key so system-reserved combinations such as
//  Command–Space cannot fire while a shortcut is being recorded.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutKeyCapture: View {
    let shortcut: StoredShortcut
    let isEnabled: Bool
    let onKeyCapture: (Int) -> Void
    let onInvalidInput: () -> Void

    @State private var isCapturing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(isCapturing ? 0.08 : 0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            isCapturing ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: isCapturing ? 2 : 1
                        )
                }

            HStack(spacing: 8) {
                Image(systemName: isCapturing ? "record.circle" : "keyboard")
                    .foregroundStyle(isCapturing ? Color.accentColor : .secondary)

                Text(isCapturing ? "Press a key…" : shortcut.keyDisplayName)
                    .font(.body.weight(.medium).monospaced())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .allowsHitTesting(false)

            ShortcutKeyCaptureRepresentable(
                isEnabled: isEnabled,
                onKeyCapture: onKeyCapture,
                onInvalidInput: onInvalidInput,
                onRecordingChanged: { isCapturing = $0 }
            )
        }
        .frame(minWidth: 150, minHeight: 34)
        .opacity(isEnabled ? 1 : 0.55)
        .help("Click, then press the key. Choose modifiers separately.")
    }
}

private struct ShortcutKeyCaptureRepresentable: NSViewRepresentable {
    let isEnabled: Bool
    let onKeyCapture: (Int) -> Void
    let onInvalidInput: () -> Void
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutKeyCaptureNSView {
        let view = ShortcutKeyCaptureNSView()
        view.isEnabled = isEnabled
        view.onKeyCapture = onKeyCapture
        view.onInvalidInput = onInvalidInput
        view.onRecordingChanged = onRecordingChanged
        return view
    }

    func updateNSView(_ nsView: ShortcutKeyCaptureNSView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onKeyCapture = onKeyCapture
        nsView.onInvalidInput = onInvalidInput
        nsView.onRecordingChanged = onRecordingChanged
    }
}

@MainActor
private final class ShortcutKeyCaptureNSView: NSView {
    var isEnabled = true
    var onKeyCapture: ((Int) -> Void)?
    var onInvalidInput: (() -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?

    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        guard isEnabled, super.becomeFirstResponder() else { return false }
        isRecording = true
        onRecordingChanged?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        isRecording = false
        onRecordingChanged?(false)
        return result
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, isEnabled else { return }

        if event.keyCode == UInt16(kVK_Escape) {
            window?.makeFirstResponder(nil)
            return
        }

        let physicalModifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])

        guard physicalModifiers.isEmpty else {
            // Modifiers are deliberately chosen with the buttons beside this
            // control. Do not save a different combination just because a
            // user happened to hold Command while pressing the base key.
            NSSound.beep()
            onInvalidInput?()
            return
        }

        onKeyCapture?(Int(event.keyCode))
        window?.makeFirstResponder(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }

        // AppKit may route modified key equivalents here instead of keyDown.
        // Consume them while recording so the app's menu cannot act. The
        // selected modifier buttons, rather than physical modifier keys, are
        // the source of truth for the saved shortcut.
        let physicalModifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
        guard physicalModifiers.isEmpty else {
            NSSound.beep()
            onInvalidInput?()
            return true
        }

        keyDown(with: event)
        return true
    }
}
