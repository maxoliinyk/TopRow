//
//  SettingsView.swift
//  TopRow
//
//  Created by Max Oliinyk on 13.08.26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(ApplicationState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsTab(appState: appState)
                .tabItem { Label("General", systemImage: "gearshape") }

            AppearanceSettingsTab(appState: appState)
                .tabItem { Label("Appearance", systemImage: "macwindow") }

            PermissionsSettingsTab(appState: appState)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 500)
        .task {
            await appState.start()
            appState.refreshPostEventAccess()
            appState.refreshLaunchAtLogin()
        }
    }
}

private struct GeneralSettingsTab: View {
    let appState: ApplicationState

    var body: some View {
        Form {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { appState.configuration.isEnabled },
                        set: { appState.setEnabled($0) }
                    )
                ) {
                    SettingsToggleLabel(
                        title: "Enable Remapping",
                        detail: "Apply saved destinations to the built-in top row."
                    )
                }
                .toggleStyle(.switch)

                Toggle(
                    isOn: Binding(
                        get: { appState.configuration.launchAtLogin },
                        set: { appState.setLaunchAtLogin($0) }
                    )
                ) {
                    SettingsToggleLabel(
                        title: "Launch at Login",
                        detail: "Restore your mappings automatically after you sign in."
                    )
                }
                .toggleStyle(.switch)

                if let launchAtLoginError = appState.launchAtLoginError {
                    InlineSettingsMessage(
                        title: "Launch at Login could not be changed",
                        detail: launchAtLoginError,
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
            } header: {
                Text("Behavior")
            } footer: {
                Text("Changes apply immediately. Saved destinations stay intact when remapping is off.")
            }
        }
        .formStyle(.grouped)
        .controlSize(.large)
    }
}

private struct AppearanceSettingsTab: View {
    let appState: ApplicationState

    var body: some View {
        Form {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { appState.configuration.hideDockIcon },
                        set: { appState.setHideDockIcon($0) }
                    )
                ) {
                    SettingsToggleLabel(
                        title: "Hide Dock Icon",
                        detail: "Keep Top Row out of the Dock."
                    )
                }
                .toggleStyle(.switch)

                Toggle(
                    isOn: Binding(
                        get: { appState.configuration.hideMenuBarIcon },
                        set: { appState.setHideMenuBarIcon($0) }
                    )
                ) {
                    SettingsToggleLabel(
                        title: "Hide Menu Bar Icon",
                        detail: "Remove the keyboard icon from the menu bar."
                    )
                }
                .toggleStyle(.switch)

                Toggle(
                    isOn: Binding(
                        get: { appState.configuration.isSilentMode },
                        set: { appState.setSilentMode($0) }
                    )
                ) {
                    SettingsToggleLabel(
                        title: "Silent Mode",
                        detail: "Hide both icons; reopen Top Row from Spotlight."
                    )
                }
                .toggleStyle(.switch)

                if appState.configuration.isSilentMode {
                    InlineSettingsMessage(
                        title: "Top Row is running silently",
                        detail: "Use Spotlight or another app launcher to bring it back.",
                        systemImage: "moon.fill",
                        color: .secondary
                    )
                }
            } header: {
                Text("Where Top Row appears")
            } footer: {
                Text("Visibility only changes where Top Row can be opened. It does not change remapping or Launch at Login.")
            }
        }
        .formStyle(.grouped)
        .controlSize(.large)
    }
}

private struct PermissionsSettingsTab: View {
    let appState: ApplicationState

    var body: some View {
        Form {
            Section {
                PermissionStatusRow(appState: appState)

                if appState.requiresPostEventAccess && !appState.isPostEventAccessGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enable shortcut output")
                            .font(.callout.weight(.semibold))
                        Text("macOS lists Post Event access under Privacy & Security › \(PostEventAccess.settingsCategoryName).")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 7) {
                            PermissionStep(number: 1, text: "Open \(PostEventAccess.settingsCategoryName).")
                            PermissionStep(number: 2, text: "Turn on Top Row.")
                            PermissionStep(number: 3, text: "Return here and choose Check Again.")
                        }

                        Text("If an older ad-hoc Top Row entry is listed, remove it once before enabling this signed build.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button("Open Permission Settings…") {
                                appState.requestPostEventAccess()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Check Again") {
                                appState.refreshPostEventAccess()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Text("Direct Function Key destinations do not need this permission. Top Row only posts the shortcut you configure; it does not monitor keyboard input, install an event tap, or request Input Monitoring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Shortcut output")
            }

            Section {
                HIDStatusRow(appState: appState)

                if appState.lastError != nil {
                    Button("Try Again") {
                        appState.retryReconciliation()
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Keyboard service")
            } footer: {
                Text("Only the built-in Apple keyboard is touched. External, Touch Bar, and virtual keyboards are left alone; no helper or elevated process is installed.")
            }
        }
        .formStyle(.grouped)
        .controlSize(.large)
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: "1.0")
                LabeledContent("Keyboard scope", value: "Built-in Apple keyboard")
                LabeledContent("Shortcut output", value: "Post Event access only")
            } header: {
                Text("About Top Row")
            }

            Section {
                Text("Top Row keeps the standard Fn layer available while letting you redirect the special keys you actually use.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .controlSize(.large)
    }
}

private struct SettingsToggleLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct PermissionStatusRow: View {
    let appState: ApplicationState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if appState.requiresPostEventAccess {
                Text(appState.isPostEventAccessGranted ? "Allowed" : "Needed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconColor)
            } else {
                Text("Not needed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var title: String {
        if !appState.requiresPostEventAccess { return "Shortcut output is not in use" }
        return appState.isPostEventAccessGranted ? "Shortcut output is allowed" : "Shortcut output is paused"
    }

    private var detail: String {
        if !appState.requiresPostEventAccess {
            return "Add a Keyboard Shortcut destination to request Post Event access."
        }
        if appState.isPostEventAccessGranted {
            return "Top Row can emit configured shortcuts through CGEvent."
        }
        return "Turn on Top Row in System Settings › Privacy & Security › \(PostEventAccess.settingsCategoryName)."
    }

    private var iconName: String {
        if !appState.requiresPostEventAccess { return "checkmark.shield" }
        return appState.isPostEventAccessGranted ? "checkmark.shield.fill" : "lock.shield"
    }

    private var iconColor: Color {
        if !appState.requiresPostEventAccess || appState.isPostEventAccessGranted { return .green }
        return .orange
    }
}

private struct HIDStatusRow: View {
    let appState: ApplicationState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: appState.hidServiceState.systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(appState.hidServiceState.title)
                    .font(.body.weight(.medium))
                Text(appState.hidServiceState.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var color: Color {
        switch appState.hidServiceState {
        case .checking: .secondary
        case .available: .green
        case .unavailable, .failed: .orange
        }
    }
}

private struct PermissionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())

            Text(text)
                .font(.caption)
        }
    }
}

private struct InlineSettingsMessage: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .foregroundStyle(color)
    }
}

#Preview {
    SettingsView()
        .environment(ApplicationState())
}
