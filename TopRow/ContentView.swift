import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

struct ContentView: View {
    @Environment(ApplicationState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading) {
            HeaderView(status: appState.overallStatus, isEnabled: appState.configuration.isEnabled)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(FunctionRowAction.allCases) { action in
                        FunctionKeyCap(
                            action: action,
                            destination: appState.configuration.destination(for: action),
                            status: appState.status(for: action),
                            isSelected: appState.selectedAction == action
                        ) {
                            appState.selectedAction = action
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            MappingEditor(appState: appState, action: appState.selectedAction)

            Divider()

            HStack {
                Toggle(
                    "Remapping Enabled",
                    isOn: Binding(
                        get: { appState.configuration.isEnabled },
                        set: { appState.setEnabled($0) }
                    )
                )

                Spacer()

                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { appState.configuration.launchAtLogin },
                        set: { appState.setLaunchAtLogin($0) }
                    )
                )
            }
            .toggleStyle(.checkbox)

            if let lastError = appState.lastError {
                Label(lastError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(24)
        .frame(minWidth: 900, idealWidth: 1080, minHeight: 330, idealHeight: 360)
        .task {
            await appState.start()
        }
    }
}

private struct HeaderView: View {
    let status: String
    let isEnabled: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text("Function Row")
                    .font(.title2.weight(.semibold))
                Text("Remap the primary actions without changing Fn + F1–F12.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(status, systemImage: isEnabled ? "checkmark.circle" : "pause.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(isEnabled ? Color.secondary : Color.orange)
        }
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
            VStack(spacing: 7) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 21, weight: .medium))
                    .frame(height: 26)

                Text(action.physicalKey.label)
                    .font(.caption.weight(.semibold).monospacedDigit())

                Text(destination.summary)
                    .font(.caption2)
                    .foregroundStyle(destination == .systemDefault ? Color.secondary.opacity(0.65) : Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 68, height: 78)
            .contentShape(.rect(cornerRadius: 12))
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
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.22 : 0.10),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MappingEditor: View {
    let appState: ApplicationState
    let action: FunctionRowAction
    @State private var shortcutValidationMessage: String?

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
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(action.title)
                        .font(.headline)
                    Text("Physical \(action.physicalKey.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset Selected") {
                    appState.resetSelected()
                }
                .buttonStyle(.borderless)

                Button("Reset All") {
                    appState.resetAll()
                }
                .buttonStyle(.borderless)
            }

            Picker("Remap to", selection: modeBinding) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            destinationEditor

            HStack(spacing: 6) {
                Image(systemName: statusSymbol)
                Text(statusMessage)
            }
            .font(.caption)
            .foregroundStyle(statusColor)
        }
        .animation(.easeInOut(duration: 0.18), value: appState.configuration.destination(for: action).summary)
    }

    private var statusSymbol: String {
        switch appState.status(for: action) {
        case .defaulted: "arrow.uturn.backward.circle"
        case .active: "checkmark.circle"
        case .inactive: "pause.circle"
        case .conflict: "exclamationmark.triangle"
        }
    }

    private var statusMessage: String {
        switch appState.status(for: action) {
        case .defaulted: "Using Apple’s original action"
        case .active: "Mapping active"
        case let .inactive(reason): reason
        case let .conflict(reason): reason
        }
    }

    private var statusColor: Color {
        switch appState.status(for: action) {
        case .defaulted: .secondary
        case .active: .green
        case .inactive, .conflict: .orange
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
                    appState.setDestination(.functionKey(.f13), for: action)
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
            Label("Apple's original action", systemImage: "arrow.uturn.backward")
                .foregroundStyle(.secondary)
        case .functionKey:
            Picker("Function Key", selection: functionKeyBinding) {
                ForEach(FunctionKey.allCases.filter { $0.rawValue >= 13 }) { functionKey in
                    Text(functionKey.label).tag(functionKey)
                }
            }
            .frame(maxWidth: 240)
        case .shortcut:
            KeyboardShortcuts.Recorder(shortcut: shortcutBinding)
                .keyboardShortcutsConflictPolicy(.init(menuItem: .allow, systemShortcut: .warn, disallowed: .block))
                .frame(maxWidth: 300)

            if let shortcutValidationMessage {
                Label(shortcutValidationMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !appState.isPostEventAccessGranted {
                HStack {
                    Label("Shortcut output needs permission to send keys to the active app.", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Privacy Settings") {
                        appState.requestPostEventAccess()
                        appState.openPrivacySettings()
                    }
                    .buttonStyle(.link)
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
                return .f13
            },
            set: { appState.setDestination(.functionKey($0), for: action) }
        )
    }

    private var shortcutBinding: Binding<KeyboardShortcuts.Shortcut?> {
        Binding(
            get: {
                guard case let .shortcut(shortcut) = appState.configuration.destination(for: action) else {
                    return nil
                }
                return shortcut.shortcut
            },
            set: { shortcut in
                guard let shortcut else {
                    appState.setDestination(.systemDefault, for: action)
                    return
                }

                let stored = StoredShortcut(shortcut)
                guard ShortcutValidation.isSupported(stored) else {
                    shortcutValidationMessage = "Use Command, Option, Control, or Shift modifiers only."
                    return
                }
                shortcutValidationMessage = nil
                appState.setDestination(ShortcutValidation.normalizedDestination(from: stored), for: action)
            }
        )
    }
}

#Preview {
    ContentView()
        .environment(ApplicationState())
}
