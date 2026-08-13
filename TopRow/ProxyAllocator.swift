import Foundation

nonisolated struct ProxyPlan: Equatable, Sendable {
    var assignments: [FunctionRowAction: FunctionKey]
    var unavailable: [FunctionRowAction: String]

    static let empty = Self(assignments: [:], unavailable: [:])
}

nonisolated struct ProxyAllocator: Sendable {
    static let proxyKeys: [FunctionKey] = [
        .f13, .f14, .f15, .f16, .f17, .f18,
        .f19, .f20, .f21, .f22, .f23, .f24
    ]

    /// Allocates one distinct proxy per shortcut source. The caller supplies
    /// the keys that have been proven listenable on the current system.
    func allocate(
        configuration: AppConfiguration,
        unavailableKeys: Set<FunctionKey> = [],
        previous: [FunctionRowAction: FunctionKey] = [:]
    ) -> ProxyPlan {
        var reserved = Set<FunctionKey>()
        var shortcutActions: [FunctionRowAction] = []

        for mapping in configuration.mappings {
            switch mapping.destination {
            case let .functionKey(key):
                if Self.proxyKeys.contains(key) {
                    reserved.insert(key)
                }
            case let .shortcut(shortcut):
                if shortcut.functionKey == nil {
                    shortcutActions.append(mapping.action)
                }
            case .systemDefault:
                break
            }
        }

        var available = Set(Self.proxyKeys)
        available.subtract(unavailableKeys)
        available.subtract(reserved)

        var assignments: [FunctionRowAction: FunctionKey] = [:]
        var remaining = Set(shortcutActions)

        // Preserve stable assignments first, provided the proxy is still safe.
        for action in shortcutActions {
            guard let key = previous[action], available.contains(key) else { continue }
            assignments[action] = key
            available.remove(key)
            remaining.remove(action)
        }

        let orderedKeys = Self.proxyKeys.filter { available.contains($0) }
        for action in shortcutActions where remaining.contains(action) {
            guard let key = orderedKeys.first(where: { available.contains($0) }) else {
                continue
            }
            assignments[action] = key
            available.remove(key)
        }

        var unavailable: [FunctionRowAction: String] = [:]
        for action in shortcutActions where assignments[action] == nil {
            unavailable[action] = "No unused proxy function key is available."
        }

        return ProxyPlan(assignments: assignments, unavailable: unavailable)
    }
}
