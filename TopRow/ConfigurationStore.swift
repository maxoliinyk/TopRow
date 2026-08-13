//
//  ConfigurationStore.swift
//  TopRow
//
//  Created by Max Oliinyk on 13.08.26.
//

import Foundation

nonisolated struct ServiceOwnership: Codable, Equatable, Sendable {
    var fingerprint: String
    var baseline: [HIDMappingPair]
    var applied: [HIDMappingPair]
}

nonisolated struct OwnershipState: Codable, Equatable, Sendable {
    var services: [ServiceOwnership] = []

    func ownership(for fingerprint: String) -> ServiceOwnership? {
        services.first(where: { $0.fingerprint == fingerprint })
    }

    mutating func update(_ ownership: ServiceOwnership) {
        if let index = services.firstIndex(where: { $0.fingerprint == ownership.fingerprint }) {
            services[index] = ownership
        } else {
            services.append(ownership)
        }
    }
}

@MainActor
final class ConfigurationStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadConfiguration() -> AppConfiguration {
        guard let data = defaults.data(forKey: "TopRow.configuration") else {
            return .defaults
        }

        do {
            var configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
            configuration.normalize()
            return configuration
        } catch {
            return .defaults
        }
    }

    func save(configuration: AppConfiguration) {
        var normalized = configuration
        normalized.normalize()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults.set(data, forKey: "TopRow.configuration")
    }

    func loadOwnership() -> OwnershipState {
        guard let data = defaults.data(forKey: "TopRow.ownership") else {
            return OwnershipState()
        }
        return (try? JSONDecoder().decode(OwnershipState.self, from: data)) ?? OwnershipState()
    }

    func save(ownership: OwnershipState) {
        guard let data = try? JSONEncoder().encode(ownership) else { return }
        defaults.set(data, forKey: "TopRow.ownership")
    }
}
