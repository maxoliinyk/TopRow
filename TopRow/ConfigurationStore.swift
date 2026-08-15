//
//  ConfigurationStore.swift
//  TopRow
//
//  Created by Max Oliinyk on 13.08.26.
//

import Defaults
import Foundation

extension Defaults.Keys {
    static let topRowSchemaVersion = Key<Int>("TopRowSchemaVersion", default: AppConfiguration.currentSchemaVersion)
    static let topRowIsEnabled = Key<Bool>("TopRowIsEnabled", default: true)
    static let topRowLaunchAtLogin = Key<Bool>("TopRowLaunchAtLogin", default: false)
    static let topRowHideDockIcon = Key<Bool>("TopRowHideDockIcon", default: false)
    static let topRowHideMenuBarIcon = Key<Bool>("TopRowHideMenuBarIcon", default: false)
    static let topRowMappingsData = Key<Data?>("TopRowMappingsData", default: nil)
    static let topRowProfilesData = Key<Data?>("TopRowProfilesData", default: nil)
    static let topRowOwnershipData = Key<Data?>("TopRowOwnershipData", default: nil)
}

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

    private enum LegacyKey {
        static let configuration = "TopRow.configuration"
        static let ownership = "TopRow.ownership"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadConfiguration() -> AppConfiguration {
        if let legacyConfiguration = loadLegacyConfiguration() {
            var normalized = legacyConfiguration
            normalized.normalize()
            save(configuration: normalized)
            return normalized
        }

        let mappings = defaults[.topRowMappingsData]
            .flatMap { try? JSONDecoder().decode([FunctionRowMapping].self, from: $0) }
            ?? AppConfiguration.defaults.mappings

        var configuration = AppConfiguration(
            schemaVersion: defaults[.topRowSchemaVersion],
            isEnabled: defaults[.topRowIsEnabled],
            launchAtLogin: defaults[.topRowLaunchAtLogin],
            hideDockIcon: defaults[.topRowHideDockIcon],
            hideMenuBarIcon: defaults[.topRowHideMenuBarIcon],
            mappings: mappings
        )
        configuration.normalize()
        return configuration
    }

    func save(configuration: AppConfiguration) {
        var normalized = configuration
        normalized.normalize()

        defaults[.topRowSchemaVersion] = normalized.schemaVersion
        defaults[.topRowIsEnabled] = normalized.isEnabled
        defaults[.topRowLaunchAtLogin] = normalized.launchAtLogin
        defaults[.topRowHideDockIcon] = normalized.hideDockIcon
        defaults[.topRowHideMenuBarIcon] = normalized.hideMenuBarIcon

        guard let mappings = try? JSONEncoder().encode(normalized.mappings) else { return }
        defaults[.topRowMappingsData] = mappings

        // Keep the global profile in sync once the profile catalog has been
        // created. Before that point, the existing single-layer storage remains
        // the source of truth and `loadProfiles()` performs the migration.
        guard let profileData = defaults[.topRowProfilesData],
              var profiles = try? JSONDecoder().decode(ProfileLibrary.self, from: profileData)
        else { return }

        profiles.global.normal = normalized.mappings
        profiles.normalize()
        save(profiles: profiles)
    }

    func loadProfiles() -> ProfileLibrary {
        if let data = defaults[.topRowProfilesData],
           var profiles = try? JSONDecoder().decode(ProfileLibrary.self, from: data) {
            let original = profiles
            profiles.normalize()
            if profiles != original {
                save(profiles: profiles)
            }
            return profiles
        }

        let migrated = ProfileLibrary(global: LayeredProfile(migrating: loadConfiguration()))
        save(profiles: migrated)
        return migrated
    }

    func save(profiles: ProfileLibrary) {
        var normalized = profiles
        normalized.normalize()
        guard let data = try? JSONEncoder().encode(normalized) else { return }
        defaults[.topRowProfilesData] = data
    }

    func loadOwnership() -> OwnershipState {
        if let legacyOwnership = loadLegacyOwnership() {
            save(ownership: legacyOwnership)
            return legacyOwnership
        }

        guard let data = defaults[.topRowOwnershipData] else { return OwnershipState() }
        return (try? JSONDecoder().decode(OwnershipState.self, from: data)) ?? OwnershipState()
    }

    func save(ownership: OwnershipState) {
        guard let data = try? JSONEncoder().encode(ownership) else { return }
        defaults[.topRowOwnershipData] = data
    }

    private func loadLegacyConfiguration() -> AppConfiguration? {
        guard let data = defaults.data(forKey: LegacyKey.configuration) else { return nil }
        return try? JSONDecoder().decode(AppConfiguration.self, from: data)
    }

    private func loadLegacyOwnership() -> OwnershipState? {
        guard let data = defaults.data(forKey: LegacyKey.ownership) else { return nil }
        return try? JSONDecoder().decode(OwnershipState.self, from: data)
    }
}
