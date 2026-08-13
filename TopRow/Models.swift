//
//  Models.swift
//  TopRow
//
//  Created by Max Oliinyk on 13.08.26.
//

import AppKit
import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts

nonisolated struct HIDUsage: Hashable, Codable, Sendable {
    let page: UInt32
    let usage: UInt32

    init(page: UInt32, usage: UInt32) {
        self.page = page
        self.usage = usage
    }

    init(rawValue: UInt64) {
        self.page = UInt32(rawValue >> 32)
        self.usage = UInt32(rawValue & 0xFFFF_FFFF)
    }

    var rawValue: UInt64 {
        UInt64(page) << 32 | UInt64(usage)
    }
}

nonisolated enum FunctionKey: Int, CaseIterable, Codable, Identifiable, Sendable {
    case f1 = 1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12
    case f13
    case f14
    case f15
    case f16
    case f17
    case f18
    case f19
    case f20
    case f21
    case f22
    case f23
    case f24

    var id: Self { self }

    var label: String { "F\(rawValue)" }

    var hidUsage: HIDUsage {
        if rawValue <= 12 {
            return HIDUsage(page: 0x07, usage: UInt32(0x39 + rawValue))
        }

        return HIDUsage(page: 0x07, usage: UInt32(0x68 + rawValue - 13))
    }

    /// Carbon currently publishes virtual-key constants through F20.
    /// F21–F24 remain valid HID destinations but need hardware key-code discovery.
    var carbonKeyCode: Int? {
        switch self {
        case .f1: Int(kVK_F1)
        case .f2: Int(kVK_F2)
        case .f3: Int(kVK_F3)
        case .f4: Int(kVK_F4)
        case .f5: Int(kVK_F5)
        case .f6: Int(kVK_F6)
        case .f7: Int(kVK_F7)
        case .f8: Int(kVK_F8)
        case .f9: Int(kVK_F9)
        case .f10: Int(kVK_F10)
        case .f11: Int(kVK_F11)
        case .f12: Int(kVK_F12)
        case .f13: Int(kVK_F13)
        case .f14: Int(kVK_F14)
        case .f15: Int(kVK_F15)
        case .f16: Int(kVK_F16)
        case .f17: Int(kVK_F17)
        case .f18: Int(kVK_F18)
        case .f19: Int(kVK_F19)
        case .f20: Int(kVK_F20)
        case .f21, .f22, .f23, .f24: nil
        }
    }

    var isProxyCapable: Bool { carbonKeyCode != nil }

    init?(carbonKeyCode: Int) {
        guard let key = Self.allCases.first(where: { $0.carbonKeyCode == carbonKeyCode }) else {
            return nil
        }
        self = key
    }
}

nonisolated enum FunctionRowAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case brightnessDown
    case brightnessUp
    case missionControl
    case spotlight
    case dictation
    case focus
    case previous
    case playPause
    case next
    case mute
    case volumeDown
    case volumeUp

    var id: Self { self }

    var physicalKey: FunctionKey {
        switch self {
        case .brightnessDown: .f1
        case .brightnessUp: .f2
        case .missionControl: .f3
        case .spotlight: .f4
        case .dictation: .f5
        case .focus: .f6
        case .previous: .f7
        case .playPause: .f8
        case .next: .f9
        case .mute: .f10
        case .volumeDown: .f11
        case .volumeUp: .f12
        }
    }

    var title: String {
        switch self {
        case .brightnessDown: "Brightness Down"
        case .brightnessUp: "Brightness Up"
        case .missionControl: "Mission Control"
        case .spotlight: "Spotlight"
        case .dictation: "Dictation"
        case .focus: "Focus"
        case .previous: "Previous"
        case .playPause: "Play/Pause"
        case .next: "Next"
        case .mute: "Mute"
        case .volumeDown: "Volume Down"
        case .volumeUp: "Volume Up"
        }
    }

    var symbolName: String {
        switch self {
        case .brightnessDown: "sun.min"
        case .brightnessUp: "sun.max"
        case .missionControl: "rectangle.3.group"
        case .spotlight: "magnifyingglass"
        case .dictation: "mic"
        case .focus: "moon"
        case .previous: "backward.end"
        case .playPause: "playpause"
        case .next: "forward.end"
        case .mute: "speaker.slash"
        case .volumeDown: "speaker.wave.1"
        case .volumeUp: "speaker.wave.3"
        }
    }

    /// Candidate values are intentionally centralized. Phase 0 can replace these
    /// values with the observed built-in keyboard profile before enabling a row.
    var candidateSourceUsage: HIDUsage {
        switch self {
        case .brightnessDown: HIDUsage(page: 0x0C, usage: 0x70)
        case .brightnessUp: HIDUsage(page: 0x0C, usage: 0x6F)
        case .missionControl: HIDUsage(page: 0x0C, usage: 0x29F)
        case .spotlight: HIDUsage(page: 0x0C, usage: 0x221)
        case .dictation: HIDUsage(page: 0x0C, usage: 0x0CF)
        case .focus: HIDUsage(page: 0x01, usage: 0x09B)
        case .previous: HIDUsage(page: 0x0C, usage: 0x0B6)
        case .playPause: HIDUsage(page: 0x0C, usage: 0x0CD)
        case .next: HIDUsage(page: 0x0C, usage: 0x0B5)
        case .mute: HIDUsage(page: 0x0C, usage: 0x0E2)
        case .volumeDown: HIDUsage(page: 0x0C, usage: 0x0EA)
        case .volumeUp: HIDUsage(page: 0x0C, usage: 0x0E9)
        }
    }
}

nonisolated struct StoredShortcut: Codable, Equatable, Hashable, Sendable {
    let carbonKeyCode: Int
    let carbonModifiers: Int

    init(carbonKeyCode: Int, carbonModifiers: Int = 0) {
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
    }

    init(_ shortcut: KeyboardShortcuts.Shortcut) {
        self.init(
            carbonKeyCode: shortcut.carbonKeyCode,
            carbonModifiers: shortcut.carbonModifiers
        )
    }

    var shortcut: KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(
            carbonKeyCode: carbonKeyCode,
            carbonModifiers: carbonModifiers
        )
    }

    var isBareFunctionKey: Bool {
        carbonModifiers == 0 && FunctionKey(carbonKeyCode: carbonKeyCode) != nil
    }

    var functionKey: FunctionKey? {
        guard isBareFunctionKey else { return nil }
        return FunctionKey(carbonKeyCode: carbonKeyCode)
    }

    var displayName: String {
        var result = ""
        if carbonModifiers & Int(cmdKey) != 0 { result += "⌘" }
        if carbonModifiers & Int(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & Int(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & Int(shiftKey) != 0 { result += "⇧" }
        result += Self.keyName(for: carbonKeyCode)
        return result
    }

    private static func keyName(for keyCode: Int) -> String {
        if let functionKey = FunctionKey(carbonKeyCode: keyCode) {
            return functionKey.label
        }

        let names: [Int: String] = [
            Int(kVK_Space): "Space",
            Int(kVK_Return): "Return",
            Int(kVK_Tab): "Tab",
            Int(kVK_Escape): "Esc",
            Int(kVK_Delete): "Delete",
            Int(kVK_ANSI_A): "A",
            Int(kVK_ANSI_B): "B",
            Int(kVK_ANSI_C): "C",
            Int(kVK_ANSI_D): "D",
            Int(kVK_ANSI_E): "E",
            Int(kVK_ANSI_F): "F",
            Int(kVK_ANSI_G): "G",
            Int(kVK_ANSI_H): "H",
            Int(kVK_ANSI_I): "I",
            Int(kVK_ANSI_J): "J",
            Int(kVK_ANSI_K): "K",
            Int(kVK_ANSI_L): "L",
            Int(kVK_ANSI_M): "M",
            Int(kVK_ANSI_N): "N",
            Int(kVK_ANSI_O): "O",
            Int(kVK_ANSI_P): "P",
            Int(kVK_ANSI_Q): "Q",
            Int(kVK_ANSI_R): "R",
            Int(kVK_ANSI_S): "S",
            Int(kVK_ANSI_T): "T",
            Int(kVK_ANSI_U): "U",
            Int(kVK_ANSI_V): "V",
            Int(kVK_ANSI_W): "W",
            Int(kVK_ANSI_X): "X",
            Int(kVK_ANSI_Y): "Y",
            Int(kVK_ANSI_Z): "Z"
        ]
        return names[keyCode] ?? "Key (keyCode)"
    }
}

nonisolated enum MappingDestination: Codable, Equatable, Sendable {
    case systemDefault
    case functionKey(FunctionKey)
    case shortcut(StoredShortcut)

    var summary: String {
        switch self {
        case .systemDefault: "Default"
        case let .functionKey(key): key.label
        case let .shortcut(shortcut): shortcut.displayName
        }
    }

    private enum CodingKeys: String, CodingKey {
        case systemDefault
        case functionKey
        case shortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if (try? container.decode(Bool.self, forKey: .systemDefault)) == true {
            self = .systemDefault
        } else if let key = try? container.decode(FunctionKey.self, forKey: .functionKey) {
            self = .functionKey(key)
        } else if let shortcut = try? container.decode(StoredShortcut.self, forKey: .shortcut) {
            self = .shortcut(shortcut)
        } else {
            self = .systemDefault
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .systemDefault:
            try container.encode(true, forKey: .systemDefault)
        case let .functionKey(key):
            try container.encode(key, forKey: .functionKey)
        case let .shortcut(shortcut):
            try container.encode(shortcut, forKey: .shortcut)
        }
    }
}

nonisolated struct FunctionRowMapping: Codable, Equatable, Sendable {
    var action: FunctionRowAction
    var destination: MappingDestination
}

nonisolated struct AppConfiguration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var isEnabled: Bool
    var launchAtLogin: Bool
    var mappings: [FunctionRowMapping]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        isEnabled: Bool = true,
        launchAtLogin: Bool = false,
        mappings: [FunctionRowMapping] = FunctionRowAction.allCases.map {
            FunctionRowMapping(action: $0, destination: .systemDefault)
        }
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.launchAtLogin = launchAtLogin
        self.mappings = mappings
        normalize()
    }

    func destination(for action: FunctionRowAction) -> MappingDestination {
        mappings.first(where: { $0.action == action })?.destination ?? .systemDefault
    }

    mutating func setDestination(_ destination: MappingDestination, for action: FunctionRowAction) {
        if let index = mappings.firstIndex(where: { $0.action == action }) {
            mappings[index].destination = destination
        } else {
            mappings.append(FunctionRowMapping(action: action, destination: destination))
        }
        normalize()
    }

    mutating func normalize() {
        var values: [FunctionRowAction: MappingDestination] = [:]
        for mapping in mappings {
            values[mapping.action] = mapping.destination
        }
        mappings = FunctionRowAction.allCases.map {
            FunctionRowMapping(action: $0, destination: values[$0] ?? .systemDefault)
        }
        schemaVersion = Self.currentSchemaVersion
    }

    static var defaults: Self { Self() }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isEnabled
        case launchAtLogin
        case mappings
    }

    private struct StoredMapping: Decodable {
        let action: String?
        let destination: MappingDestination

        private enum CodingKeys: String, CodingKey {
            case action
            case destination
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            action = try? container.decode(String.self, forKey: .action)
            destination = (try? container.decode(MappingDestination.self, forKey: .destination)) ?? .systemDefault
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? -1
        guard version == Self.currentSchemaVersion else {
            self = .defaults
            return
        }

        let enabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? true
        let launchAtLogin = (try? container.decode(Bool.self, forKey: .launchAtLogin)) ?? false
        let storedMappings = (try? container.decode([StoredMapping].self, forKey: .mappings)) ?? []

        self.init(
            schemaVersion: Self.currentSchemaVersion,
            isEnabled: enabled,
            launchAtLogin: launchAtLogin,
            mappings: storedMappings.compactMap { mapping in
                guard let rawAction = mapping.action,
                      let action = FunctionRowAction(rawValue: rawAction) else { return nil }
                return FunctionRowMapping(action: action, destination: mapping.destination)
            }
        )
        normalize()
    }
}

nonisolated struct HIDMappingPair: Codable, Equatable, Hashable, Sendable {
    let source: HIDUsage
    let destination: HIDUsage
}

nonisolated struct HIDServiceDescriptor: Equatable, Hashable, Sendable {
    let registryID: UInt64
    let fingerprint: String
    let product: String
    let isBuiltIn: Bool

    var displayName: String {
        product.isEmpty ? "Built-in Apple keyboard" : product
    }
}

/// The small, user-facing state machine for the direct HID connection. Keeping
/// this separate from `MappingStatus` lets the UI explain a service/write
/// failure once, instead of repeating a generic error under every key.
nonisolated enum HIDServiceState: Equatable, Sendable {
    case checking
    case unavailable
    case available([HIDServiceDescriptor])
    case failed(RemappingError, [HIDServiceDescriptor])

    var title: String {
        switch self {
        case .checking: "Checking keyboard"
        case .unavailable: "No supported keyboard found"
        case .available: "Keyboard connected"
        case .failed: "Keyboard mapping needs attention"
        }
    }

    var systemImage: String {
        switch self {
        case .checking: "ellipsis.circle"
        case .unavailable: "keyboard.badge.exclamationmark"
        case .available: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var isReady: Bool {
        if case .available = self { return true }
        return false
    }

    var detail: String {
        switch self {
        case .checking:
            return "TopRow is looking for the built-in Apple keyboard service."
        case .unavailable:
            return "No supported built-in Apple keyboard service was found. External, Touch Bar, and virtual keyboards are intentionally ignored."
        case let .available(services):
            let names = services.map(\.displayName).joined(separator: ", ")
            return names.isEmpty
                ? "The built-in Apple keyboard is ready for a mapping."
                : "Connected to \(names)."
        case let .failed(error, services):
            let serviceText: String
            if services.isEmpty {
                serviceText = "No supported built-in Apple keyboard service was available."
            } else {
                serviceText = "Found \(services.map(\.displayName).joined(separator: ", ")), but "
            }

            switch error {
            case .writeFailed:
                return serviceText + "macOS rejected the HID mapping write. Direct function-key mappings do not use Post Event permission; TopRow left this key unchanged. Try again after relaunching the app."
            case .verificationFailed:
                return serviceText + "macOS did not return the requested mapping after the write, so TopRow left this mapping inactive."
            case .readFailed:
                return serviceText + "TopRow could not read the keyboard's UserKeyMapping property."
            default:
                return serviceText + error.localizedDescription
            }
        }
    }
}

nonisolated enum MappingStatus: Equatable, Sendable {
    case defaulted
    case active
    case inactive(String)
    case conflict(String)
}

nonisolated enum RemappingError: LocalizedError, Equatable, Sendable {
    case unavailableHardware
    case permissionRequired
    case noProxyAvailable
    case readFailed
    case writeFailed
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .unavailableHardware: "No supported built-in Apple keyboard service was found."
        case .permissionRequired: "Shortcut output permission is required."
        case .noProxyAvailable: "No unused proxy function key is available."
        case .readFailed: "TopRow could not read the keyboard's UserKeyMapping property."
        case .writeFailed: "macOS rejected the HID mapping write."
        case .verificationFailed: "macOS did not return the requested keyboard mapping after the write."
        }
    }
}
