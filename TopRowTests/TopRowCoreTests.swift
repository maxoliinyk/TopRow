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
    }

    @Test
    func configurationRoundTripsThroughCodable() throws {
        var configuration = AppConfiguration.defaults
        configuration.isEnabled = true
        configuration.launchAtLogin = true
        configuration.mappings[4].destination = .functionKey(.f13)
        configuration.mappings[3].destination = .shortcut(
            StoredShortcut(carbonKeyCode: 49, carbonModifiers: Int(cmdKey))
        )

        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: encoded)

        #expect(decoded == configuration)
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
    func proxyAllocatorSupportsTwelveShortcuts() {
        let sources = FunctionRowAction.allCases
        let destinations = Dictionary(uniqueKeysWithValues: sources.map {
            ($0, MappingDestination.shortcut(StoredShortcut(carbonKeyCode: 10, carbonModifiers: 0)))
        })
        var configuration = AppConfiguration.defaults
        for source in sources {
            configuration.setDestination(destinations[source]!, for: source)
        }
        let plan = ProxyAllocator().allocate(configuration: configuration, unavailableKeys: [], previous: [:])

        #expect(plan.assignments.count == 12)
        #expect(Set(plan.assignments.values).count == 12)
        #expect(plan.unavailable.isEmpty)
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
    func duplicateDirectDestinationsDoNotConsumeDuplicateProxyCapacity() {
        var configuration = AppConfiguration.defaults
        configuration.setDestination(.functionKey(.f13), for: .brightnessDown)
        configuration.setDestination(.functionKey(.f13), for: .brightnessUp)
        configuration.setDestination(
            .shortcut(StoredShortcut(carbonKeyCode: Int(kVK_Space))),
            for: .spotlight
        )

        let plan = ProxyAllocator().allocate(configuration: configuration, unavailableKeys: [], previous: [:])

        #expect(plan.assignments[.spotlight] == .f14)
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
