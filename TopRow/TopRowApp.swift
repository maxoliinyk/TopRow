import AppKit
import SwiftUI

@MainActor
final class TopRowAppDelegate: NSObject, NSApplicationDelegate {
    static var applicationState: ApplicationState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let applicationState = Self.applicationState else { return .terminateNow }

        Task { @MainActor in
            await applicationState.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct TopRowApp: App {
    @NSApplicationDelegateAdaptor(TopRowAppDelegate.self) private var appDelegate
    @State private var applicationState: ApplicationState

    init() {
        let state = ApplicationState()
        _applicationState = State(initialValue: state)
        TopRowAppDelegate.applicationState = state
    }

    var body: some Scene {
        WindowGroup("Function Row", id: "main") {
            ContentView()
                .environment(applicationState)
        }
        .defaultSize(width: 1180, height: 720)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(applicationState)
        }

        MenuBarExtra("TopRow", systemImage: "keyboard") {
            MenuBarView(applicationState: applicationState)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarView: View {
    let applicationState: ApplicationState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Function Row") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Settings…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Label(applicationState.overallStatus, systemImage: "circle.fill")
            .foregroundStyle(.secondary)

        Divider()

        Button("Quit") {
            Task { @MainActor in
                await applicationState.shutdown()
                NSApp.terminate(nil)
            }
        }
        .keyboardShortcut("q")
    }
}
