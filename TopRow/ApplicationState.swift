import AppKit
import Observation
import ServiceManagement

@MainActor
@Observable
final class ApplicationState {
    var configuration: AppConfiguration
    var selectedAction: FunctionRowAction = .dictation
    var statuses: [FunctionRowAction: MappingStatus]
    var isReconciling = false
    var lastError: String?
    var isPostEventAccessGranted: Bool

    private let store: ConfigurationStore
    private let hidService = HIDMappingService()
    private let shortcutRuntime = ShortcutRuntime()
    @ObservationIgnored private var serviceMonitor: HIDServiceMonitor?
    private var ownership: OwnershipState
    private var previousProxyAssignments: [FunctionRowAction: FunctionKey] = [:]
    private var reconcileTask: Task<Void, Never>?
    private var reconcileRequested = false
    private var hasStarted = false

    init(store: ConfigurationStore = ConfigurationStore()) {
        self.store = store
        self.configuration = store.loadConfiguration()
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

    var overallStatus: String {
        if isReconciling { return "Updating keyboard…" }
        if let lastError { return lastError }
        if !configuration.isEnabled { return "Remapping disabled" }
        if requiresPostEventAccess && !isPostEventAccessGranted {
            return "Shortcut permission required"
        }
        if statuses.values.contains(where: {
            if case .conflict = $0 { return true }
            return false
        }) {
            return "Some mappings need attention"
        }
        return "Remapping active"
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        serviceMonitor?.start()
        scheduleReconcile()
        if let reconcileTask {
            await reconcileTask.value
        }
    }

    func setDestination(_ destination: MappingDestination, for action: FunctionRowAction) {
        configuration.setDestination(destination, for: action)
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
        store.save(configuration: configuration)
        scheduleReconcile()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            configuration.launchAtLogin = enabled
            store.save(configuration: configuration)
        } catch {
            lastError = "Launch at login could not be updated."
        }
    }

    func requestPostEventAccess() {
        _ = PostEventAccess().request()
        isPostEventAccessGranted = PostEventAccess().isGranted
        scheduleReconcile()
    }

    func openPrivacySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_PostEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        if let url = urls.lazy.compactMap(URL.init(string:)).first(where: { NSWorkspace.shared.open($0) }) {
            _ = url
        }
    }

    func shutdown() async {
        reconcileRequested = false
        reconcileTask?.cancel()
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
            lastError = error.localizedDescription
        }

        for action in FunctionRowAction.allCases {
            statuses[action] = status(
                for: action,
                configuration: configuration,
                proxyPlan: proxyPlan,
                conflicts: result.conflicts,
                error: result.error,
                shortcutPermission: isPostEventAccessGranted
            )
        }

        guard result.error == nil, configuration.isEnabled, isPostEventAccessGranted else {
            shortcutRuntime.stop()
            return
        }

        shortcutRuntime.update(
            assignments: proxyPlan.assignments,
            destinations: shortcutDestinations
        )
    }

    private func status(
        for action: FunctionRowAction,
        configuration: AppConfiguration,
        proxyPlan: ProxyPlan,
        conflicts: [HIDUsage: HIDUsage],
        error: RemappingError?,
        shortcutPermission: Bool
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
            return error == nil ? .active : .inactive(error?.localizedDescription ?? "Unavailable")
        case .shortcut:
            guard configuration.isEnabled else { return .inactive("Remapping is disabled.") }
            guard shortcutPermission else { return .inactive("Allow shortcut output in Privacy & Security.") }
            guard proxyPlan.assignments[action] != nil else {
                return .inactive(proxyPlan.unavailable[action] ?? "No proxy function key is available.")
            }
            if let conflict = conflicts[action.candidateSourceUsage] {
                return .conflict("Another mapping sends this key to 0x\(String(conflict.rawValue, radix: 16))")
            }
            return error == nil ? .active : .inactive(error?.localizedDescription ?? "Unavailable")
        }
    }

    private func normalizeBareShortcutDestinations() {
        for index in configuration.mappings.indices {
            guard case let .shortcut(shortcut) = configuration.mappings[index].destination else { continue }
            if let functionKey = shortcut.functionKey {
                configuration.mappings[index].destination = .functionKey(functionKey)
            }
        }
        store.save(configuration: configuration)
    }
}
