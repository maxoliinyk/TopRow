//
//  ApplicationState.swift
//  TopRow
//
//  Created by Max Oliinyk on 13.08.26.
//

import AppKit
import LaunchAtLogin
import Observation

@MainActor
@Observable
final class ApplicationState {
    var configuration: AppConfiguration
    var selectedAction: FunctionRowAction = .dictation
    var statuses: [FunctionRowAction: MappingStatus]
    var isReconciling = false
    var lastError: String?
    var launchAtLoginError: String?
    var isPostEventAccessGranted: Bool
    var hidServiceState: HIDServiceState = .checking

    private let store: ConfigurationStore
    private let hidService = HIDMappingService()
    private let shortcutRuntime = ShortcutRuntime()
    @ObservationIgnored private var serviceMonitor: HIDServiceMonitor?
    private var ownership: OwnershipState
    private var previousProxyAssignments: [FunctionRowAction: FunctionKey] = [:]
    private var reconcileTask: Task<Void, Never>?
    private var permissionMonitorTask: Task<Void, Never>?
    private var reconcileRequested = false
    private var hasStarted = false
    private var shutdownStarted = false

    init(store: ConfigurationStore = ConfigurationStore()) {
        self.store = store
        let actualLaunchAtLogin = LaunchAtLogin.isEnabled
        var configuration = store.loadConfiguration()
        if configuration.launchAtLogin != actualLaunchAtLogin {
            configuration.launchAtLogin = actualLaunchAtLogin
            store.save(configuration: configuration)
        }
        self.configuration = configuration
        self.ownership = store.loadOwnership()
        self.statuses = Dictionary(
            uniqueKeysWithValues: FunctionRowAction.allCases.map { ($0, .defaulted) }
        )
        self.isPostEventAccessGranted = PostEventAccess().isGranted
        normalizeBareShortcutDestinations()
        self.serviceMonitor = HIDServiceMonitor(hidService: hidService) { [weak self] in
            self?.scheduleReconcile()
        }
    }

    var requiresPostEventAccess: Bool {
        configuration.mappings.contains {
            if case .shortcut = $0.destination { return true }
            return false
        }
    }

    var hasConfiguredMappings: Bool {
        configuration.mappings.contains { $0.destination != .systemDefault }
    }

    var hasDirectMappings: Bool {
        configuration.mappings.contains {
            if case .functionKey = $0.destination { return true }
            return false
        }
    }

    var overallStatus: String {
        if isReconciling { return "Updating keyboard…" }
        if !configuration.isEnabled { return "Remapping disabled" }
        if requiresPostEventAccess && !isPostEventAccessGranted {
            return "Shortcut output permission needed"
        }
        if case .unavailable = hidServiceState, hasConfiguredMappings {
            return "No supported keyboard found"
        }
        if lastError != nil || launchAtLoginError != nil {
            return "Mapping needs attention"
        }
        if statuses.values.contains(where: {
            if case .conflict = $0 { return true }
            if case .inactive = $0 { return true }
            return false
        }) {
            return "Some mappings need attention"
        }
        return "Remapping active"
    }

    var overallStatusDetail: String? {
        if isReconciling { return "Checking the built-in keyboard service…" }
        if !configuration.isEnabled { return "Turn on Enable Remapping in Settings to apply your saved mappings." }
        if requiresPostEventAccess && !isPostEventAccessGranted {
            return "Allow TopRow under Privacy & Security › \(PostEventAccess.settingsCategoryName) to enable shortcut output."
        }
        if let lastError { return lastError }
        if let launchAtLoginError { return launchAtLoginError }
        if case let .inactive(reason) = statuses.values.first(where: {
            if case .inactive = $0 { return true }
            return false
        }) {
            return reason
        }
        if case let .conflict(reason) = statuses.values.first(where: {
            if case .conflict = $0 { return true }
            return false
        }) {
            return reason
        }
        if case .unavailable = hidServiceState, hasConfiguredMappings {
            return hidServiceState.detail
        }
        return nil
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        serviceMonitor?.start()
        permissionMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }
                refreshPostEventAccess()
            }
        }
        scheduleReconcile()
        if let reconcileTask {
            await reconcileTask.value
        }
    }

    func setDestination(_ destination: MappingDestination, for action: FunctionRowAction) {
        configuration.setDestination(destination, for: action)
        lastError = nil
        store.save(configuration: configuration)
        scheduleReconcile()
    }

    func resetSelected() {
        setDestination(.systemDefault, for: selectedAction)
    }

    func resetAll() {
        for action in FunctionRowAction.allCases {
            configuration.setDestination(.systemDefault, for: action)
        }
        store.save(configuration: configuration)
        scheduleReconcile()
    }

    func setEnabled(_ enabled: Bool) {
        configuration.isEnabled = enabled
        lastError = nil
        store.save(configuration: configuration)
        scheduleReconcile()
    }

    func setHideDockIcon(_ hidden: Bool) {
        configuration.hideDockIcon = hidden
        store.save(configuration: configuration)
        applyApplicationPresentation()
    }

    func setHideMenuBarIcon(_ hidden: Bool) {
        guard configuration.hideMenuBarIcon != hidden else { return }
        configuration.hideMenuBarIcon = hidden
        store.save(configuration: configuration)
        MenuBarController.shared.updateVisibility(isHidden: hidden)
    }

    func setSilentMode(_ enabled: Bool) {
        configuration.hideDockIcon = enabled
        configuration.hideMenuBarIcon = enabled
        store.save(configuration: configuration)
        applyApplicationPresentation()
        MenuBarController.shared.updateVisibility(isHidden: enabled)
    }

    func applyApplicationPresentation() {
        // Accessory apps stay launchable and can show windows, but do not add
        // an application icon to the Dock or own the main menu bar.
        let desiredPolicy: NSApplication.ActivationPolicy = configuration.hideDockIcon
            ? .accessory
            : .regular

        guard NSApp.activationPolicy() != desiredPolicy else { return }
        _ = NSApp.setActivationPolicy(desiredPolicy)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        // LaunchAtLogin performs the SMAppService registration and retries a
        // stale enabled registration before registering again.
        LaunchAtLogin.isEnabled = enabled
        let actualLaunchAtLogin = LaunchAtLogin.isEnabled
        configuration.launchAtLogin = actualLaunchAtLogin
        store.save(configuration: configuration)

        guard actualLaunchAtLogin == enabled else {
            launchAtLoginError = enabled
                ? "macOS did not enable Launch at Login. Open System Settings › General › Login Items and allow TopRow."
                : "macOS did not disable Launch at Login. Try again from System Settings › General › Login Items."
            return
        }

        lastError = nil
        launchAtLoginError = nil
    }

    func refreshLaunchAtLogin() {
        let actualLaunchAtLogin = LaunchAtLogin.isEnabled
        guard configuration.launchAtLogin != actualLaunchAtLogin else { return }
        configuration.launchAtLogin = actualLaunchAtLogin
        store.save(configuration: configuration)
    }

    func requestPostEventAccess() {
        _ = PostEventAccess().request()
        isPostEventAccessGranted = PostEventAccess().isGranted
        if !isPostEventAccessGranted {
            openPostEventSettings()
        }
        scheduleReconcile()
    }

    /// Core Graphics calls this narrow privilege Post Event access. macOS
    /// exposes the switch under its Accessibility privacy pane, so open that
    /// exact pane instead of the generic privacy landing page.
    func openPostEventSettings() {
        let accessibilityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")
        if let accessibilityURL, NSWorkspace.shared.open(accessibilityURL) {
            return
        }
        if let fallbackURL {
            _ = NSWorkspace.shared.open(fallbackURL)
        }
    }

    func openPrivacySettings() {
        openPostEventSettings()
    }

    func refreshPostEventAccess() {
        let wasGranted = isPostEventAccessGranted
        isPostEventAccessGranted = PostEventAccess().isGranted
        if wasGranted != isPostEventAccessGranted {
            scheduleReconcile()
        }
    }

    func retryReconciliation() {
        lastError = nil
        scheduleReconcile()
    }

    func shutdown() async {
        guard !shutdownStarted else { return }
        shutdownStarted = true
        reconcileRequested = false
        reconcileTask?.cancel()
        permissionMonitorTask?.cancel()
        permissionMonitorTask = nil
        if let reconcileTask {
            await reconcileTask.value
        }
        self.reconcileTask = nil
        serviceMonitor?.stop()
        shortcutRuntime.stop()
        let result = await hidService.apply(desired: [], ownership: ownership)
        ownership = result.ownership
        store.save(ownership: ownership)
    }

    func status(for action: FunctionRowAction) -> MappingStatus {
        statuses[action] ?? .defaulted
    }

    private func scheduleReconcile() {
        reconcileRequested = true
        guard reconcileTask == nil else { return }

        reconcileTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.reconcileRequested && !Task.isCancelled {
                self.reconcileRequested = false
                await self.reconcile()
            }
            self.reconcileTask = nil
        }
    }

    private func reconcile() async {
        guard !isReconciling else {
            reconcileRequested = true
            return
        }
        isReconciling = true
        lastError = nil
        defer { isReconciling = false }

        isPostEventAccessGranted = PostEventAccess().isGranted

        let unavailableProxyKeys = Set(ProxyAllocator.proxyKeys.filter { !$0.isProxyCapable })
        let allocator = ProxyAllocator()
        let proxyPlan = allocator.allocate(
            configuration: configuration,
            unavailableKeys: unavailableProxyKeys,
            previous: previousProxyAssignments
        )

        var desired: [HIDMappingPair] = []
        var shortcutDestinations: [FunctionRowAction: StoredShortcut] = [:]

        if configuration.isEnabled {
            for mapping in configuration.mappings {
                switch mapping.destination {
                case .systemDefault:
                    continue
                case let .functionKey(key):
                    desired.append(HIDMappingPair(
                        source: mapping.action.candidateSourceUsage,
                        destination: key.hidUsage
                    ))
                case let .shortcut(shortcut):
                    guard isPostEventAccessGranted else { continue }
                    guard let proxy = proxyPlan.assignments[mapping.action] else { continue }
                    desired.append(HIDMappingPair(
                        source: mapping.action.candidateSourceUsage,
                        destination: proxy.hidUsage
                    ))
                    shortcutDestinations[mapping.action] = shortcut
                }
            }
        }

        let result = await hidService.apply(desired: desired, ownership: ownership)
        ownership = result.ownership
        store.save(ownership: ownership)
        previousProxyAssignments = proxyPlan.assignments

        if let error = result.error {
            if error == .unavailableHardware {
                hidServiceState = .unavailable
            } else {
                hidServiceState = .failed(error, result.selectedServices)
            }
        } else if result.selectedServices.isEmpty {
            hidServiceState = .unavailable
        } else {
            hidServiceState = .available(result.selectedServices)
        }

        if result.error != nil {
            let shouldSurfaceHIDFailure = configuration.isEnabled
                && (hasDirectMappings || (requiresPostEventAccess && isPostEventAccessGranted))
            if shouldSurfaceHIDFailure {
                lastError = hidServiceState.detail
            }
        }

        for action in FunctionRowAction.allCases {
            statuses[action] = status(
                for: action,
                configuration: configuration,
                proxyPlan: proxyPlan,
                conflicts: result.conflicts,
                error: result.error,
                shortcutPermission: isPostEventAccessGranted,
                hidState: hidServiceState
            )
        }

        guard result.error == nil, configuration.isEnabled, isPostEventAccessGranted else {
            shortcutRuntime.stop()
            return
        }

        let conflictedActions = Set(
            configuration.mappings.compactMap { mapping in
                result.conflicts[mapping.action.candidateSourceUsage] == nil ? nil : mapping.action
            }
        )
        let activeAssignments = proxyPlan.assignments.filter { !conflictedActions.contains($0.key) }
        let activeDestinations = shortcutDestinations.filter { !conflictedActions.contains($0.key) }

        shortcutRuntime.update(
            assignments: activeAssignments,
            destinations: activeDestinations
        )
    }

    private func status(
        for action: FunctionRowAction,
        configuration: AppConfiguration,
        proxyPlan: ProxyPlan,
        conflicts: [HIDUsage: HIDUsage],
        error: RemappingError?,
        shortcutPermission: Bool,
        hidState: HIDServiceState
    ) -> MappingStatus {
        let destination = configuration.destination(for: action)
        switch destination {
        case .systemDefault:
            return .defaulted
        case .functionKey:
            guard configuration.isEnabled else { return .inactive("Remapping is disabled.") }
            if let conflict = conflicts[action.candidateSourceUsage] {
                return .conflict("Another mapping sends this key to 0x\(String(conflict.rawValue, radix: 16))")
            }
            return error == nil ? .active : .inactive(hidState.detail)
        case .shortcut:
            guard configuration.isEnabled else { return .inactive("Remapping is disabled.") }
            guard shortcutPermission else {
                return .inactive("Allow TopRow in Privacy & Security › \(PostEventAccess.settingsCategoryName).")
            }
            guard proxyPlan.assignments[action] != nil else {
                return .inactive(proxyPlan.unavailable[action] ?? "No proxy function key is available.")
            }
            if let conflict = conflicts[action.candidateSourceUsage] {
                return .conflict("Another mapping sends this key to 0x\(String(conflict.rawValue, radix: 16))")
            }
            return error == nil ? .active : .inactive(hidState.detail)
        }
    }

    private func normalizeBareShortcutDestinations() {
        for index in configuration.mappings.indices {
            guard case let .shortcut(shortcut) = configuration.mappings[index].destination else { continue }
            if let functionKey = shortcut.functionKey {
                configuration.mappings[index].destination = functionKey.isSelectableDestination
                    ? .functionKey(functionKey)
                    : .systemDefault
            }
        }
        configuration.normalize()
        store.save(configuration: configuration)
    }
}
