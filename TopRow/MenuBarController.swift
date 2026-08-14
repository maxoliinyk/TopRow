//
//  MenuBarController.swift
//  TopRow
//

import AppKit

/// Owns the status item outside SwiftUI's `MenuBarExtra` scene.
///
/// `MenuBarExtra(isInserted:)` writes back into its binding while AppKit is
/// rebuilding the status item. Persisting that write from an observable
/// binding invalidates the same graph update and can recurse until the app
/// crashes. An AppKit status item gives visibility changes an imperative,
/// one-way update path instead.
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private weak var applicationState: ApplicationState?
    private var openMainWindowAction: (@MainActor () -> Void)?
    private var openSettingsAction: (@MainActor () -> Void)?

    func start(applicationState: ApplicationState) {
        self.applicationState = applicationState

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(
                systemSymbolName: "keyboard",
                accessibilityDescription: "TopRow"
            )
            item.button?.image?.isTemplate = true
            item.button?.toolTip = "TopRow"
            item.menu = makeMenu()
            statusItem = item
        }

        updateVisibility(isHidden: applicationState.configuration.hideMenuBarIcon)
        updateStatus(applicationState.overallStatus)
    }

    func registerWindowActions(
        openMainWindow: @escaping @MainActor () -> Void,
        openSettings: @escaping @MainActor () -> Void
    ) {
        openMainWindowAction = openMainWindow
        openSettingsAction = openSettings
    }

    func updateVisibility(isHidden: Bool) {
        statusItem?.isVisible = !isHidden
    }

    func updateStatus(_ status: String) {
        statusMenuItem?.title = status
    }

    func stop() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        statusMenuItem = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let openItem = NSMenuItem(
            title: "Open Function Row",
            action: #selector(openMainWindow),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let statusItem = NSMenuItem(title: "Checking keyboard…", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        self.statusMenuItem = statusItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openMainWindow() {
        if let openMainWindowAction {
            openMainWindowAction()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if let openSettingsAction {
            openSettingsAction()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let selector = Selector(("showSettingsWindow:"))
        if NSApp.responds(to: selector) {
            NSApp.sendAction(selector, to: nil, from: nil)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
