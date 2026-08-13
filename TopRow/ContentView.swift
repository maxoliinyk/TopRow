import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

struct ContentView: View {
    @Environment(ApplicationState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 18) {
            HeaderView(
                status: appState.overallStatus,
                detail: appState.overallStatusDetail,
                systemImage: headerSystemImage,
                tone: headerTone
            )

            FunctionRowCard(appState: appState)

            MappingEditor(appState: appState, action: appState.selectedAction)

            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                Text("Remapping and launch behavior live in Settings.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Open Settings…") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
            .font(.callout)
            .frame(maxWidth: 700)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
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
        VStack(spacing: 11) {
            Image(systemName: "keyboard")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            Text("Function Row")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))

            Text("Choose what the twelve special keys do. Fn + F1–F12 always stays unchanged.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            VStack(spacing: 7) {
                Label(status, systemImage: systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(tone.color.opacity(0.12), in: Capsule())

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 680)
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
                    Text("Special keys")
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

            HStack(spacing: 10) {
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
            .padding(.vertical, 4)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
            VStack(spacing: 8) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .frame(height: 25)

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
            .frame(width: 73, height: 92)
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
        VStack(alignment: .leading, spacing: 19) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.title3.weight(.semibold))
                    Text("Physical \(action.physicalKey.label)")
                        .font(.caption)
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Destination")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Destination", selection: modeBinding) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.large)
            }

            destinationEditor

            StatusBanner(status: appState.status(for: action))
        }
        .padding(25)
        .frame(maxWidth: 700)
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
            Label("Apple's original action", systemImage: "arrow.uturn.backward.circle")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .functionKey:
            HStack(spacing: 12) {
                Label("Send as", systemImage: "function")
                    .foregroundStyle(.secondary)
                Picker("Function Key", selection: functionKeyBinding) {
                    ForEach(FunctionKey.allCases.filter { $0.rawValue >= 13 }) { functionKey in
                        Text(functionKey.label).tag(functionKey)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.large)
                Spacer(minLength: 0)
            }

        case .shortcut:
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    Label("Press", systemImage: "command")
                        .foregroundStyle(.secondary)
                    KeyboardShortcuts.Recorder(shortcut: shortcutBinding)
                        .keyboardShortcutsConflictPolicy(.init(menuItem: .allow, systemShortcut: .warn, disallowed: .block))
                        .controlSize(.large)
                    Spacer(minLength: 0)
                }

                if let shortcutValidationMessage {
                    Label(shortcutValidationMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !appState.isPostEventAccessGranted {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Shortcut output is paused", systemImage: "lock.shield")
                            .font(.callout.weight(.semibold))
                        Text("TopRow needs Post Event access to send this shortcut to the active app. This is separate from Accessibility and Input Monitoring.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Allow Shortcut Output") {
                            appState.requestPostEventAccess()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

private struct StatusBanner: View {
    let status: MappingStatus

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .frame(width: 17)
            Text(message)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
