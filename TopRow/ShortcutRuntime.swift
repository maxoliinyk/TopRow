import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import KeyboardShortcuts

nonisolated struct EncodedKeyEvent: Equatable, Sendable {
    let keyCode: Int
    let isKeyDown: Bool
    let modifierMask: Int
}

nonisolated struct ShortcutEventEncoder: Sendable {
    private struct ModifierKey {
        let mask: Int
        let keyCode: Int
    }

    private let modifierKeys = [
        ModifierKey(mask: Int(cmdKey), keyCode: Int(kVK_Command)),
        ModifierKey(mask: Int(optionKey), keyCode: Int(kVK_Option)),
        ModifierKey(mask: Int(controlKey), keyCode: Int(kVK_Control)),
        ModifierKey(mask: Int(shiftKey), keyCode: Int(kVK_Shift))
    ]

    func encode(_ shortcut: StoredShortcut) -> [EncodedKeyEvent] {
        let active = modifierKeys.filter { shortcut.carbonModifiers & $0.mask != 0 }
        var events: [EncodedKeyEvent] = []

        var currentMask = 0
        for modifier in active {
            currentMask |= modifier.mask
            events.append(EncodedKeyEvent(
                keyCode: modifier.keyCode,
                isKeyDown: true,
                modifierMask: currentMask
            ))
        }

        events.append(EncodedKeyEvent(
            keyCode: shortcut.carbonKeyCode,
            isKeyDown: true,
            modifierMask: currentMask
        ))
        events.append(EncodedKeyEvent(
            keyCode: shortcut.carbonKeyCode,
            isKeyDown: false,
            modifierMask: currentMask
        ))

        for modifier in active.reversed() {
            events.append(EncodedKeyEvent(
                keyCode: modifier.keyCode,
                isKeyDown: false,
                modifierMask: currentMask
            ))
            currentMask &= ~modifier.mask
        }

        return events
    }
}

nonisolated struct ShortcutEmitter: Sendable {
    private let encoder = ShortcutEventEncoder()

    func emit(_ shortcut: StoredShortcut) -> Bool {
        for event in encoder.encode(shortcut) {
            guard let cgEvent = CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(event.keyCode),
                keyDown: event.isKeyDown
            ) else {
                return false
            }

            cgEvent.flags = flags(for: event.modifierMask)
            cgEvent.post(tap: .cghidEventTap)
        }
        return true
    }

    private func flags(for modifierMask: Int) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifierMask & Int(cmdKey) != 0 { flags.insert(.maskCommand) }
        if modifierMask & Int(optionKey) != 0 { flags.insert(.maskAlternate) }
        if modifierMask & Int(controlKey) != 0 { flags.insert(.maskControl) }
        if modifierMask & Int(shiftKey) != 0 { flags.insert(.maskShift) }
        return flags
    }
}

nonisolated struct PostEventAccess: Sendable {
    var isGranted: Bool { CGPreflightPostEventAccess() }

    func request() -> Bool {
        CGRequestPostEventAccess()
    }
}

nonisolated enum ShortcutValidation {
    static func isSupported(_ shortcut: StoredShortcut) -> Bool {
        let supportedMask = Int(cmdKey) | Int(optionKey) | Int(controlKey) | Int(shiftKey)
        return shortcut.carbonModifiers & ~supportedMask == 0
    }

    static func normalizedDestination(
        from shortcut: StoredShortcut
    ) -> MappingDestination {
        if let functionKey = shortcut.functionKey {
            return .functionKey(functionKey)
        }
        return .shortcut(shortcut)
    }
}

@MainActor
final class ShortcutRuntime {
    private var listenerTasks: [FunctionRowAction: Task<Void, Never>] = [:]
    private let emitter = ShortcutEmitter()

    func update(assignments: [FunctionRowAction: FunctionKey], destinations: [FunctionRowAction: StoredShortcut]) {
        stop()

        for (action, proxy) in assignments {
            guard let keyCode = proxy.carbonKeyCode, let destination = destinations[action] else {
                continue
            }

            let proxyShortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: keyCode)
            listenerTasks[action] = Task { [emitter] in
                for await _ in KeyboardShortcuts.events(for: proxyShortcut) {
                    guard !Task.isCancelled else { return }
                    _ = emitter.emit(destination)
                }
            }
        }
    }

    func stop() {
        for task in listenerTasks.values {
            task.cancel()
        }
        listenerTasks.removeAll()
    }
}
