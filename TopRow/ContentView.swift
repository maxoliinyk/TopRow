//
//  ContentView.swift
//  TopRow
//
//  Created by Max Oliinyk on 13.08.26.
//

import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

struct ContentView: View {
    @Environment(ApplicationState.self) private var appState

    var body: some View {
        VStack(spacing: 14) {
            HeaderView(
                status: appState.overallStatus,
                detail: appState.overallStatusDetail,
                systemImage: headerSystemImage,
                tone: headerTone
            )

            FunctionRowCard(appState: appState)

            MappingEditor(appState: appState, action: appState.selectedAction)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .frame(width: 1180, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await appState.start()
        }
    }

    private var headerSystemImage: String {
        if !appState.configuration.isEnabled { return "pause.circle" }
        if appState.isReconciling { return "ellipsis.circle" }
        if appState.lastError != nil || appState.launchAtLoginError != nil { return "exclamationmark.triangle.fill" }
        if appState.requiresPostEventAccess && !appState.isPostEventAccessGranted {
            return "lock.shield"
        }
        return appState.hidServiceState.systemImage
    }

    private var headerTone: StatusTone {
        if !appState.configuration.isEnabled { return .neutral }
        if appState.isReconciling || !appState.hidServiceState.isReady && !appState.hasConfiguredMappings {
            return .neutral
        }
        if appState.lastError != nil || appState.launchAtLoginError != nil || appState.requiresPostEventAccess && !appState.isPostEventAccessGranted {
            return .warning
        }
        if appState.hidServiceState.isReady || !appState.hasConfiguredMappings {
            return .success
        }
        return .warning
    }
}

private enum StatusTone {
    case neutral
    case success
    case warning

    var color: Color {
        switch self {
        case .neutral: .secondary
        case .success: .green
        case .warning: .orange
        }
    }
}

private struct HeaderView: View {
    let status: String
    let detail: String?
    let systemImage: String
    let tone: StatusTone

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            Text("Function Row")
                .font(.system(.title2, design: .rounded).weight(.semibold))

            Text("Choose what the twelve Top Row keys do. Fn + F1–F12 stays unchanged.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(maxWidth: 700)

            VStack(spacing: 4) {
                Label(status, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(tone.color.opacity(0.12), in: Capsule())

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 780)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FunctionRowCard: View {
    @Bindable var appState: ApplicationState

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Top Row")
                        .font(.headline)
                    Text("Select a key to edit its destination")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Text("F1–F12")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            HStack(spacing: 8) {
                ForEach(FunctionRowAction.allCases) { action in
                    FunctionKeyCap(
                        action: action,
                        destination: appState.configuration.destination(for: action),
                        status: appState.status(for: action),
                        isSelected: appState.selectedAction == action
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            appState.selectedAction = action
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FunctionKeyCap: View {
    let action: FunctionRowAction
    let destination: MappingDestination
    let status: MappingStatus
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            VStack(spacing: 5) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .frame(height: 22)

                Text(action.physicalKey.label)
                    .font(.caption.weight(.semibold).monospacedDigit())

                Text(destination.summary)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(destination == .systemDefault ? .secondary : Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        (destination == .systemDefault ? Color.secondary : Color.accentColor).opacity(0.10),
                        in: Capsule()
                    )
            }
            .frame(width: 73, height: 82)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(KeyCapButtonStyle(isSelected: isSelected, isHovered: isHovered))
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("function-key-\(action.rawValue)")
        .help("\(action.title), \(action.physicalKey.label)")
    }

    private var accessibilityLabel: String {
        var value = "\(action.title), \(action.physicalKey.label)"
        if destination != .systemDefault {
            value += ", mapped to \(destination.summary)"
        }
        return value
    }
}

private struct KeyCapButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(isHovered ? 0.07 : 0.035))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.16 : 0.08),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.01 : 1))
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovered)
    }
}

private struct MappingEditor: View {
    let appState: ApplicationState
    let action: FunctionRowAction
    @State private var shortcutValidationMessage: String?
    @State private var showingResetAllConfirmation = false

    private enum Mode: String, CaseIterable, Hashable {
        case systemDefault
        case functionKey
        case shortcut

        var title: String {
            switch self {
            case .systemDefault: "Default"
            case .functionKey: "Function Key"
            case .shortcut: "Keyboard Shortcut"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.headline.weight(.semibold))
                    Text("Physical \(action.physicalKey.label)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button("Reset Selected") {
                    appState.resetSelected()
                }
                .buttonStyle(.borderless)

                Button("Reset All", role: .destructive) {
                    showingResetAllConfirmation = true
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Destination")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Destination", selection: modeBinding) {
                    ForEach(availableModes, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)
            }

            destinationEditor

            if appState.status(for: action) != .defaulted {
                StatusBanner(status: appState.status(for: action))
            }
        }
        .padding(18)
        .frame(maxWidth: 780)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.18), value: appState.configuration.destination(for: action).summary)
        .confirmationDialog(
            "Reset every function-row key?",
            isPresented: $showingResetAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive) {
                appState.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All twelve keys will return to Apple's original actions.")
        }
    }

    private var modeBinding: Binding<Mode> {
        Binding(
            get: {
                switch appState.configuration.destination(for: action) {
                case .systemDefault: .systemDefault
                case .functionKey: .functionKey
                case .shortcut: .shortcut
                }
            },
            set: { mode in
                switch mode {
                case .systemDefault:
                    appState.setDestination(.systemDefault, for: action)
                case .functionKey:
                    guard let functionKey = availableFunctionKeys.first else { return }
                    appState.setDestination(.functionKey(functionKey), for: action)
                case .shortcut:
                    let existing: StoredShortcut
                    if case let .shortcut(shortcut) = appState.configuration.destination(for: action) {
                        existing = shortcut
                    } else {
                        existing = StoredShortcut(carbonKeyCode: Int(kVK_ANSI_D), carbonModifiers: Int(controlKey | optionKey))
                    }
                    appState.setDestination(.shortcut(existing), for: action)
                }
            }
        )
    }

    @ViewBuilder
    private var destinationEditor: some View {
        switch appState.configuration.destination(for: action) {
        case .systemDefault:
            Label("Apple's original action", systemImage: "arrow.uturn.backward.circle")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .functionKey:
            HStack(spacing: 12) {
                Label("Send as", systemImage: "function")
                    .foregroundStyle(.secondary)
                Picker("Function Key", selection: functionKeyBinding) {
                    ForEach(availableFunctionKeys) { functionKey in
                        Text(functionKey.label).tag(functionKey)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.regular)
                Spacer(minLength: 0)
            }

            Text("F14 and F15 are reserved by macOS brightness controls.")
                .font(.caption2)
                .foregroundStyle(.secondary)

        case .shortcut:
            VStack(alignment: .leading, spacing: 9) {
                Text("Modifiers")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(ShortcutModifier.allCases) { modifier in
                        Button {
                            toggleModifier(modifier)
                        } label: {
                            Text("\(modifier.symbol) \(modifier.title)")
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ModifierChipButtonStyle(isSelected: isModifierSelected(modifier)))
                    }
                }

                HStack(spacing: 10) {
                    Label("Key", systemImage: "keyboard")
                        .foregroundStyle(.secondary)
                    ShortcutKeyCapture(
                        shortcut: currentShortcut,
                        isEnabled: true,
                        onKeyCapture: captureBaseKey,
                        onInvalidInput: {
                            shortcutValidationMessage = "Press the base key only. Choose Command, Option, Control, or Shift above."
                        }
                    )
                    Spacer(minLength: 0)
                }

                Text("Choose modifiers, then press one base key. System shortcuts such as ⌘Space are recorded without opening Spotlight.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let shortcutValidationMessage {
                    Label(shortcutValidationMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if currentShortcut.shortcut.isTakenBySystem {
                    Label("This matches a macOS shortcut. TopRow will still emit it when the function-row key is pressed.", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !appState.isPostEventAccessGranted {
                    HStack(spacing: 9) {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shortcut output needs permission")
                                .font(.caption.weight(.semibold))
                            Text("Allow TopRow in Privacy & Security › Accessibility.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Button("Open Accessibility Settings…") {
                            appState.requestPostEventAccess()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private var functionKeyBinding: Binding<FunctionKey> {
        Binding(
            get: {
                if case let .functionKey(key) = appState.configuration.destination(for: action) {
                    return key
                }
                return availableFunctionKeys.first ?? .f13
            },
            set: { appState.setDestination(.functionKey($0), for: action) }
        )
    }

    private var availableModes: [Mode] {
        Mode.allCases.filter { mode in
            mode != .functionKey || !availableFunctionKeys.isEmpty
        }
    }

    private var availableFunctionKeys: [FunctionKey] {
        let current: FunctionKey?
        if case let .functionKey(key) = appState.configuration.destination(for: action) {
            current = key
        } else {
            current = nil
        }

        return FunctionKey.destinationKeys.filter { key in
            key == current || !appState.configuration.mappings.contains { mapping in
                guard mapping.action != action else { return false }
                if case let .functionKey(destination) = mapping.destination {
                    return destination == key
                }
                return false
            }
        }
    }

    private var currentShortcut: StoredShortcut {
        if case let .shortcut(shortcut) = appState.configuration.destination(for: action) {
            return shortcut
        }

        return StoredShortcut(carbonKeyCode: Int(kVK_ANSI_D), carbonModifiers: Int(controlKey | optionKey))
    }

    private func isModifierSelected(_ modifier: ShortcutModifier) -> Bool {
        currentShortcut.carbonModifiers & modifier.carbonMask != 0
    }

    private func toggleModifier(_ modifier: ShortcutModifier) {
        let current = currentShortcut
        let nextMask: Int
        if isModifierSelected(modifier) {
            nextMask = current.carbonModifiers & ~modifier.carbonMask
        } else {
            nextMask = current.carbonModifiers | modifier.carbonMask
        }

        applyShortcut(KeyboardShortcuts.Shortcut(
            carbonKeyCode: current.carbonKeyCode,
            carbonModifiers: nextMask
        ))
    }

    private func captureBaseKey(_ keyCode: Int) {
        let shortcut = KeyboardShortcuts.Shortcut(
            carbonKeyCode: keyCode,
            carbonModifiers: currentShortcut.carbonModifiers
        )
        applyShortcut(shortcut)
    }

    private func applyShortcut(_ shortcut: KeyboardShortcuts.Shortcut) {
        let stored = StoredShortcut(shortcut)
        guard ShortcutValidation.isSupported(stored) else {
            shortcutValidationMessage = "Use Command, Option, Control, or Shift modifiers only."
            return
        }

        if let functionKey = stored.functionKey, !functionKey.isSelectableDestination {
            shortcutValidationMessage = "\(functionKey.label) is reserved by macOS and cannot be used by TopRow."
            return
        }

        shortcutValidationMessage = nil
        appState.setDestination(ShortcutValidation.normalizedDestination(from: stored), for: action)
    }
}

private struct ModifierChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.accentColor : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(isSelected ? 0 : 0.10), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct StatusBanner: View {
    let status: MappingStatus

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .frame(width: 17)
            Text(message)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2)
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var systemImage: String {
        switch status {
        case .defaulted: "arrow.uturn.backward.circle"
        case .active: "checkmark.circle.fill"
        case .inactive: "pause.circle"
        case .conflict: "exclamationmark.triangle.fill"
        }
    }

    private var message: String {
        switch status {
        case .defaulted: "Using Apple's original action"
        case .active: "Mapping active"
        case let .inactive(reason): reason
        case let .conflict(reason): reason
        }
    }

    private var color: Color {
        switch status {
        case .defaulted: .secondary
        case .active: .green
        case .inactive, .conflict: .orange
        }
    }
}

#Preview {
    ContentView()
        .environment(ApplicationState())
}
