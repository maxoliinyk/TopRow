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
        WindowGroup(id: "main") {
            ContentView()
                .environment(applicationState)
        }
        .defaultSize(width: 1080, height: 360)

        MenuBarExtra("TopRow", systemImage: "keyboard") {
            MenuBarView(applicationState: applicationState)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarView: View {
    let applicationState: ApplicationState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Function Row Settings") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Toggle(
            "Remapping Enabled",
            isOn: Binding(
                get: { applicationState.configuration.isEnabled },
                set: { applicationState.setEnabled($0) }
            )
        )

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
