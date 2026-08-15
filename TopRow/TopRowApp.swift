//
//  TopRowApp.swift
//  TopRow
//
//  Created by Max Oliinyk on 13.08.26.
//

import AppKit
import SwiftUI

@MainActor
final class TopRowAppDelegate: NSObject, NSApplicationDelegate {
    static var applicationState: ApplicationState?
    private var terminationStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let applicationState = Self.applicationState else { return }
        MenuBarController.shared.start(applicationState: applicationState)
        applicationState.applyApplicationPresentation()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationStarted else { return .terminateLater }
        terminationStarted = true
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
        WindowGroup("Top Row", id: "main") {
            ContentView()
                .environment(applicationState)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(applicationState)
        }

    }
}
