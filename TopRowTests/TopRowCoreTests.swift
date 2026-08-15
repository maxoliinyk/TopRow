//
//  TopRowCoreTests.swift
//  TopRow
//
//  Created by Max Oliinyk on 13.08.26.
//

import Carbon.HIToolbox
import Foundation
import Testing

@testable import TopRow

struct TopRowCoreTests {
    @Test
    func hidUsageEncoding() {
        let usage = HIDUsage(page: 0x0C, usage: 0x0CF)

        #expect(usage.rawValue == 0x0000000C000000CF)
        #expect(HIDUsage(rawValue: usage.rawValue) == usage)
    }

    @Test
    func shortcutModifierMasksComposeIndependently() {
        let mask = ShortcutModifier.command.carbonMask | ShortcutModifier.option.carbonMask
        let shortcut = StoredShortcut(carbonKeyCode: Int(kVK_Space), carbonModifiers: mask)

        #expect(shortcut.displayName == "⌘⌥Space")
        #expect(shortcut.replacingModifiers(ShortcutModifier.shift.carbonMask).displayName == "⇧Space")
    }

    @Test
    func shortcutKeyDisplayDoesNotExposeTextFieldEditing() {
        let shortcut = StoredShortcut(carbonKeyCode: Int(kVK_ANSI_D), carbonModifiers: Int(cmdKey))

        #expect(shortcut.keyDisplayName == "D")
        #expect(shortcut.displayName == "⌘D")
    }

    @Test
    func functionKeyMappings() {
        #expect(FunctionKey.f1.hidUsage == HIDUsage(page: 0x07, usage: 0x3A))
        #expect(FunctionKey.f12.hidUsage == HIDUsage(page: 0x07, usage: 0x45))
        #expect(FunctionKey.f13.hidUsage == HIDUsage(page: 0x07, usage: 0x68))
        #expect(FunctionKey.f24.hidUsage == HIDUsage(page: 0x07, usage: 0x73))
    }

    @Test
    func destinationKeysExcludeBrightnessControls() {
        #expect(!FunctionKey.destinationKeys.contains(.f14))
        #expect(!FunctionKey.destinationKeys.contains(.f15))
        #expect(FunctionKey.destinationKeys == [.f13, .f16, .f17, .f18, .f19, .f20, .f21, .f22, .f23, .f24])
    }

    @Test
    func configurationRejectsReservedAndDuplicateFunctionDestinations() {
        var configuration = AppConfiguration.defaults
        configuration.setDestination(.functionKey(.f14), for: .brightnessDown)
        configuration.setDestination(.functionKey(.f13), for: .brightnessDown)
        configuration.setDestination(.functionKey(.f13), for: .brightnessUp)

        #expect(configuration.destination(for: .brightnessDown) == .functionKey(.f13))
        #expect(configuration.destination(for: .brightnessUp) == .systemDefault)
    }

    @Test
    func serviceSelectorFailsClosedForExternalAndVirtualServices() {
        #expect(HIDServiceSelector.accepts(
            conformsToKeyboard: true,
            product: "Apple Internal Keyboard / Trackpad",
            transport: "FIFO",
            isBuiltIn: true
        ))
        #expect(!HIDServiceSelector.accepts(
            conformsToKeyboard: true,
            product: "TouchBarUserDevice",
            transport: "Virtual",
            isBuiltIn: true
        ))
        #expect(!HIDServiceSelector.accepts(
            conformsToKeyboard: true,
            product: "External Keyboard",
            transport: "USB",
            isBuiltIn: false
        ))
        #expect(!HIDServiceSelector.accepts(
            conformsToKeyboard: false,
            product: "Apple Internal Keyboard / Trackpad",
            transport: "FIFO",
            isBuiltIn: true
        ))
    }

    @Test
    func defaultConfigurationIsOrdered() {
        let configuration = AppConfiguration.defaults

        #expect(configuration.mappings.count == FunctionRowAction.allCases.count)
        #expect(configuration.mappings.map(\.action) == FunctionRowAction.allCases)
        #expect(configuration.mappings.allSatisfy { $0.destination == MappingDestination.systemDefault })
        #expect(!configuration.hideDockIcon)
        #expect(!configuration.hideMenuBarIcon)
        #expect(!configuration.isSilentMode)
    }

    @Test
    func configurationRoundTripsThroughCodable() throws {
        var configuration = AppConfiguration.defaults
        configuration.isEnabled = true
        configuration.launchAtLogin = true
        configuration.hideDockIcon = true
        configuration.hideMenuBarIcon = true
        configuration.mappings[4].destination = .functionKey(.f13)
        configuration.mappings[3].destination = .shortcut(
            StoredShortcut(carbonKeyCode: 49, carbonModifiers: Int(cmdKey))
        )

        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: encoded)

        #expect(decoded == configuration)
        #expect(decoded.isSilentMode)
    }

    @Test
    func layeredProfileKeepsIndependentNormalAndFnDestinations() throws {
        var profile = LayeredProfile.defaults
        profile.setDestination(.functionKey(.f13), for: .dictation, in: .normal)
        profile.setDestination(.shortcut(
            StoredShortcut(carbonKeyCode: 49, carbonModifiers: Int(cmdKey))
        ), for: .dictation, in: .fn)

        #expect(profile.destination(for: .dictation, in: .normal) == .functionKey(.f13))
        #expect(profile.destination(for: .dictation, in: .fn) == .shortcut(
            StoredShortcut(carbonKeyCode: 49, carbonModifiers: Int(cmdKey))
        ))

        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(LayeredProfile.self, from: encoded)
        #expect(decoded == profile)
    }

    @Test
    func profileLibraryUsesAppOverrideAndGlobalFallback() {
        var library = ProfileLibrary.defaults
        var appProfile = library.copyOfGlobal(for: "com.example.Game")
        appProfile.profile.setDestination(.functionKey(.f13), for: .dictation, in: .normal)
        library.upsert(appProfile)

        #expect(library.profile(for: "com.example.Game") == appProfile.profile)
        #expect(library.profile(for: "com.example.Editor") == library.global)

        library.remove(bundleIdentifier: "com.example.Game")
        #expect(library.appProfile(for: "com.example.Game") == nil)
        #expect(library.profile(for: "com.example.Game") == library.global)
    }

    @Test
    @MainActor
    func configurationStoreMigratesLegacyConfigurationIntoDefaultsKeys() throws {
        let suiteName = "TopRowTests.configurationStore.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        var legacy = AppConfiguration.defaults
        legacy.isEnabled = false
        legacy.hideMenuBarIcon = true
        legacy.setDestination(.functionKey(.f13), for: .dictation)
        suite.set(try JSONEncoder().encode(legacy), forKey: "TopRow.configuration")

        let store = ConfigurationStore(defaults: suite)
        let migrated = store.loadConfiguration()

        #expect(migrated == legacy)
        #expect(suite.object(forKey: "TopRowIsEnabled") as? Bool == false)
        #expect(suite.data(forKey: "TopRowMappingsData") != nil)
    }

    @Test
    @MainActor
    func configurationStoreMigratesSingleLayerConfigurationIntoGlobalProfile() throws {
        let suiteName = "TopRowTests.profileStore.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        var legacy = AppConfiguration.defaults
        legacy.setDestination(.functionKey(.f13), for: .dictation)
        suite.set(try JSONEncoder().encode(legacy), forKey: "TopRow.configuration")

        let store = ConfigurationStore(defaults: suite)
        let profiles = store.loadProfiles()

        #expect(profiles.global.normal == legacy.mappings)
        #expect(profiles.global.fn == AppConfiguration.defaults.mappings)
        #expect(profiles.appProfiles.isEmpty)
        #expect(suite.data(forKey: "TopRowProfilesData") != nil)
    }

    @Test
    @MainActor
    func configurationStorePersistsProfileOverridesAndKeepsGlobalInSync() {
        let suiteName = "TopRowTests.profileOverrideStore.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = ConfigurationStore(defaults: suite)
        var profiles = store.loadProfiles()
        var appProfile = profiles.copyOfGlobal(for: "com.example.Game")
        appProfile.profile.setDestination(.functionKey(.f16), for: .dictation, in: .fn)
        profiles.upsert(appProfile)
        store.save(profiles: profiles)

        var configuration = AppConfiguration.defaults
        configuration.setDestination(.functionKey(.f13), for: .dictation)
        store.save(configuration: configuration)

        let loaded = store.loadProfiles()
        #expect(loaded.global.normal == configuration.mappings)
        #expect(loaded.profile(for: "com.example.Game").destination(for: .dictation, in: .fn) == .functionKey(.f16))
    }

    @Test
    @MainActor
    func configurationStoreMigratesLegacyOwnershipIntoDefaultsKeys() throws {
        let suiteName = "TopRowTests.ownershipStore.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        let ownership = OwnershipState(services: [
            ServiceOwnership(
                fingerprint: "test-service",
                baseline: [],
                applied: []
            )
        ])
        suite.set(try JSONEncoder().encode(ownership), forKey: "TopRow.ownership")

        let store = ConfigurationStore(defaults: suite)

        #expect(store.loadOwnership() == ownership)
        #expect(suite.data(forKey: "TopRowOwnershipData") != nil)
    }

    @Test
    func configurationSupportsIndependentVisibilitySettings() {
        var configuration = AppConfiguration.defaults
        configuration.hideDockIcon = true

        #expect(!configuration.hideMenuBarIcon)
        #expect(!configuration.isSilentMode)

        configuration.hideMenuBarIcon = true
        #expect(configuration.isSilentMode)

        configuration.hideDockIcon = false
        #expect(!configuration.isSilentMode)
    }

    @Test
    func invalidConfigurationFallsBackToDefaults() throws {
        let invalid = Data(#"{"schemaVersion":999,"enabled":true,"mappings":[],"launchAtLogin":false}"#.utf8)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: invalid)

        #expect(decoded == .defaults)
    }

    @Test
    func unknownEntriesDecodeAsDefaults() throws {
        let data = Data(#"{"schemaVersion":1,"isEnabled":true,"launchAtLogin":false,"mappings":[{"action":"dictation","destination":{"unknown":true}},{"action":"futureAction","destination":{"functionKey":13}}]}"#.utf8)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        #expect(decoded.destination(for: .dictation) == .systemDefault)
        #expect(decoded.destination(for: .spotlight) == .systemDefault)
    }

    @Test
    func proxyAllocatorReportsUnavailableShortcutsWhenBrightnessKeysAreReserved() {
        let sources = FunctionRowAction.allCases
        let destinations = Dictionary(uniqueKeysWithValues: sources.map {
            ($0, MappingDestination.shortcut(StoredShortcut(carbonKeyCode: 10, carbonModifiers: 0)))
        })
        var configuration = AppConfiguration.defaults
        for source in sources {
            configuration.setDestination(destinations[source]!, for: source)
        }
        let plan = ProxyAllocator().allocate(configuration: configuration, unavailableKeys: [], previous: [:])

        #expect(plan.assignments.count == FunctionKey.destinationKeys.count)
        #expect(Set(plan.assignments.values).count == FunctionKey.destinationKeys.count)
        #expect(plan.unavailable.count == sources.count - FunctionKey.destinationKeys.count)
    }

    @Test
    func proxyAllocatorReservesDirectDestinations() {
        let directAction = FunctionRowAction.brightnessDown
        let shortcutAction = FunctionRowAction.brightnessUp
        let destinations: [FunctionRowAction: MappingDestination] = [
            directAction: .functionKey(.f13),
            shortcutAction: .shortcut(StoredShortcut(carbonKeyCode: 49, carbonModifiers: 0))
        ]

        var configuration = AppConfiguration.defaults
        for (action, destination) in destinations {
            configuration.setDestination(destination, for: action)
        }
        let plan = ProxyAllocator().allocate(configuration: configuration, unavailableKeys: [], previous: [:])

        #expect(plan.assignments[shortcutAction] != .f13)
        #expect(plan.unavailable.isEmpty)
    }

    @Test
    func proxyAllocatorKeepsStableAssignments() {
        let source = FunctionRowAction.brightnessDown
        let destination = MappingDestination.shortcut(StoredShortcut(carbonKeyCode: 49, carbonModifiers: 0))
        var configuration = AppConfiguration.defaults
        configuration.setDestination(destination, for: source)
        let first = ProxyAllocator().allocate(configuration: configuration, unavailableKeys: [], previous: [:])
        let second = ProxyAllocator().allocate(configuration: configuration, unavailableKeys: [], previous: first.assignments)

        #expect(second.assignments[source] == first.assignments[source])
    }

    @Test
    func hidMergePreservesUnrelatedMappings() {
        let unrelated = HIDMappingPair(source: HIDUsage(page: 0x07, usage: 0x39), destination: FunctionKey.f20.hidUsage)
        let owned = HIDMappingPair(source: HIDUsage(page: 0x0C, usage: 0x0CF), destination: FunctionKey.f13.hidUsage)
        let desired = HIDMappingPair(source: HIDUsage(page: 0x0C, usage: 0x0CF), destination: FunctionKey.f14.hidUsage)

        let result = HIDMappingMerge.merge(
            current: [unrelated, owned],
            baseline: [unrelated],
            previouslyApplied: [owned],
            desired: [desired]
        )

        #expect(result.mappings.contains(unrelated))
        #expect(result.mappings.contains(desired))
        #expect(!result.mappings.contains(owned))
        #expect(result.conflicts.isEmpty)
    }

    @Test
    func hidMergePreservesChangedExternalDestination() {
        let baseline = HIDMappingPair(source: HIDUsage(page: 0x0C, usage: 0x0CF), destination: FunctionKey.f13.hidUsage)
        let external = HIDMappingPair(source: baseline.source, destination: FunctionKey.f14.hidUsage)
        let desired = HIDMappingPair(source: baseline.source, destination: FunctionKey.f15.hidUsage)

        let result = HIDMappingMerge.merge(
            current: [external],
            baseline: [baseline],
            previouslyApplied: [baseline],
            desired: [desired]
        )

        #expect(result.mappings == [external])
        #expect(result.conflicts[baseline.source] == external.destination)
    }

    @Test
    func hidMergeRemovesOnlyPreviouslyAppliedPairs() {
        let owned = HIDMappingPair(
            source: HIDUsage(page: 0x0C, usage: 0x0CF),
            destination: FunctionKey.f13.hidUsage
        )

        let result = HIDMappingMerge.merge(
            current: [owned],
            baseline: [],
            previouslyApplied: [owned],
            desired: []
        )

        #expect(result.mappings.isEmpty)
        #expect(result.applied.isEmpty)
        #expect(result.conflicts.isEmpty)
    }

    @Test
    func proxyAllocatorReportsUnavailableSources() {
        var configuration = AppConfiguration.defaults
        for action in FunctionRowAction.allCases {
            configuration.setDestination(
                .shortcut(StoredShortcut(carbonKeyCode: Int(kVK_Space))),
                for: action
            )
        }

        let unavailable = Set(ProxyAllocator.proxyKeys.dropFirst())
        let plan = ProxyAllocator().allocate(
            configuration: configuration,
            unavailableKeys: unavailable,
            previous: [:]
        )

        #expect(plan.assignments.count == 1)
        #expect(plan.unavailable.count == 11)
    }

    @Test
    func duplicateDirectDestinationsAreClearedAndNeverReused() {
        var configuration = AppConfiguration.defaults
        configuration.setDestination(.functionKey(.f13), for: .brightnessDown)
        configuration.setDestination(.functionKey(.f13), for: .brightnessUp)
        configuration.setDestination(
            .shortcut(StoredShortcut(carbonKeyCode: Int(kVK_Space))),
            for: .spotlight
        )

        let plan = ProxyAllocator().allocate(configuration: configuration, unavailableKeys: [], previous: [:])

        #expect(configuration.destination(for: .brightnessDown) == .functionKey(.f13))
        #expect(configuration.destination(for: .brightnessUp) == .systemDefault)
        #expect(plan.assignments[.spotlight] == .f16)
        #expect(plan.unavailable.isEmpty)
    }

    @Test
    func shortcutEventOrdering() {
        let shortcut = StoredShortcut(carbonKeyCode: 49, carbonModifiers: Int(cmdKey | optionKey))
        let events = ShortcutEventEncoder().encode(shortcut)

        #expect(events.map { $0.keyCode } == [55, 58, 49, 49, 58, 55])
        #expect(events.map { $0.isKeyDown } == [true, true, true, false, false, false])
        #expect(events[2].modifierMask == Int(cmdKey | optionKey))
    }

    @Test
    func bareProxyShortcutNormalizesToDirectFunctionKey() {
        let shortcut = StoredShortcut(carbonKeyCode: FunctionKey.f18.carbonKeyCode!, carbonModifiers: 0)

        #expect(shortcut.functionKey == .f18)
    }

    @Test
    func hidServiceStateExplainsWriteFailures() {
        let service = HIDServiceDescriptor(
            registryID: 42,
            fingerprint: "Apple Internal Keyboard / Trackpad|FIFO",
            product: "Apple Internal Keyboard / Trackpad",
            isBuiltIn: true
        )
        let state = HIDServiceState.failed(.writeFailed, [service])

        #expect(state.title == "Keyboard mapping needs attention")
        #expect(state.detail.contains("macOS rejected the HID mapping write"))
        #expect(state.detail.contains("Post Event permission"))
        #expect(HIDServiceState.unavailable.detail.contains("External"))
    }
}
