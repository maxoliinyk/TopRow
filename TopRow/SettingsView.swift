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
                        detail: "Apply the saved destinations to the built-in function row."
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
                        detail: "Keep TopRow running so your mappings are restored after you sign in."
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
                Text("General")
            } footer: {
                Text("Changes take effect immediately. Your individual key destinations stay saved when remapping is disabled.")
            }

            Section {
                Toggle(
                    isOn: Binding(
                        get: { appState.configuration.hideDockIcon },
                        set: { appState.setHideDockIcon($0) }
                    )
                ) {
                    SettingsToggleLabel(
                        title: "Hide Dock Icon",
                        detail: "Keep TopRow out of the Dock. It can still be opened from the menu bar unless Silent Mode is enabled."
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
                        detail: "Remove the keyboard icon from the menu bar. Use the Dock or Spotlight to open TopRow unless Silent Mode is enabled."
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
                        detail: "Hide both icons. Open TopRow from Spotlight or another app launcher."
                    )
                }
                .toggleStyle(.switch)

                if appState.configuration.isSilentMode {
                    InlineSettingsMessage(
                        title: "TopRow is running silently",
                        detail: "Use Spotlight or another app launcher to bring TopRow back when you need it.",
                        systemImage: "moon.fill",
                        color: .secondary
                    )
                }
            } header: {
                Text("App Visibility")
            } footer: {
                Text("These settings affect only the app's Dock and menu bar presence. They do not change remapping or Launch at Login.")
            }

            Section {
                PermissionStatusRow(appState: appState)

                if appState.requiresPostEventAccess && !appState.isPostEventAccessGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enable shortcut output")
                            .font(.callout.weight(.semibold))
                        Text("Core Graphics calls this Post Event access. macOS lists the switch under Privacy & Security › \(PostEventAccess.settingsCategoryName).")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("1. Open \(PostEventAccess.settingsCategoryName).  2. Turn on TopRow.  3. Return here and check again.")
                            .font(.caption)

                        Text("If TopRow was previously built ad hoc, remove that old TopRow entry once, enable this signed build, and future rebuilds will keep the grant.")
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

                Text("Direct Function Key destinations do not need this permission. TopRow only posts the shortcut you configure; it does not monitor keyboard input, install an event tap, or request Input Monitoring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Permissions")
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
                Text("Keyboard Service")
            } footer: {
                Text("TopRow only selects the built-in Apple keyboard. External, Touch Bar, and virtual services are left untouched. Direct HID access is used by this personal-build workflow; no helper, driver, or elevated process is involved.")
            }

            Section {
                LabeledContent("Version", value: "1.0")
                LabeledContent("Keyboard scope", value: "Built-in Apple keyboard")
                LabeledContent("Shortcut output", value: "Post Event access only")
            } header: {
                Text("About TopRow")
            }
        }
        .formStyle(.grouped)
        .controlSize(.large)
        .frame(width: 590)
        .padding(.vertical, 8)
        .task {
            await appState.start()
            appState.refreshPostEventAccess()
            appState.refreshLaunchAtLogin()
        }
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
            return "TopRow can emit configured shortcuts through CGEvent."
        }
        return "Turn on TopRow in System Settings › Privacy & Security › \(PostEventAccess.settingsCategoryName)."
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
