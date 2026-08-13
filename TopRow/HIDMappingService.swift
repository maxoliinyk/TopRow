//
//  HIDMappingService.swift
//  TopRow
//
//  Created by Max Oliinyk on 13.08.26.
//

import Foundation
import IOKit
import IOKit.hidsystem

nonisolated struct HIDServiceSnapshot: Equatable, Sendable {
    let descriptor: HIDServiceDescriptor
    let mappings: [HIDMappingPair]
}

nonisolated struct HIDApplyResult: Equatable, Sendable {
    /// The services selected by the built-in keyboard filter, including on a
    /// failed write. This gives the UI enough context to distinguish “no
    /// keyboard was found” from “macOS rejected a write”.
    var selectedServices: [HIDServiceDescriptor]
    var snapshots: [HIDServiceSnapshot]
    var ownership: OwnershipState
    var conflicts: [HIDUsage: HIDUsage]
    var error: RemappingError?
}

nonisolated struct HIDMappingMergeResult: Equatable, Sendable {
    var mappings: [HIDMappingPair]
    var applied: [HIDMappingPair]
    var conflicts: [HIDUsage: HIDUsage]
}

nonisolated enum HIDServiceSelector {
    static func accepts(
        conformsToKeyboard: Bool,
        product: String,
        transport: String,
        isBuiltIn: Bool
    ) -> Bool {
        guard conformsToKeyboard else { return false }

        let isVirtual = product.localizedCaseInsensitiveContains("touchbar")
            || product.localizedCaseInsensitiveContains("virtual")
            || transport.localizedCaseInsensitiveContains("virtual")
        guard !isVirtual else { return false }

        return isBuiltIn || product.localizedCaseInsensitiveContains("apple internal keyboard")
    }
}

nonisolated enum HIDMappingMerge {
    static func merge(
        current: [HIDMappingPair],
        baseline: [HIDMappingPair],
        previouslyApplied: [HIDMappingPair],
        desired: [HIDMappingPair]
    ) -> HIDMappingMergeResult {
        let baselineSet = Set(baseline)
        var merged = Set(current)

        // Only remove pairs we added and that were not part of the original state.
        for pair in previouslyApplied where !baselineSet.contains(pair) {
            merged.remove(pair)
        }

        var conflicts: [HIDUsage: HIDUsage] = [:]
        var applied = Set<HIDMappingPair>()

        for pair in desired {
            let sourceMappings = merged.filter { $0.source == pair.source }
            if sourceMappings.isEmpty {
                merged.insert(pair)
                if !baselineSet.contains(pair) {
                    applied.insert(pair)
                }
            } else if let external = sourceMappings.first(where: { $0.destination != pair.destination }) {
                conflicts[pair.source] = external.destination
            } else if sourceMappings.contains(pair) {
                if !baselineSet.contains(pair) {
                    applied.insert(pair)
                }
            }
        }

        return HIDMappingMergeResult(
            mappings: merged.sorted { lhs, rhs in
                if lhs.source.rawValue == rhs.source.rawValue {
                    return lhs.destination.rawValue < rhs.destination.rawValue
                }
                return lhs.source.rawValue < rhs.source.rawValue
            },
            applied: applied.sorted { $0.source.rawValue < $1.source.rawValue },
            conflicts: conflicts
        )
    }
}

actor HIDMappingService {
    private static let propertyKeyValue = "UserKeyMapping"
    private static let genericDesktopPage: UInt32 = 0x01
    private static let keyboardUsage: UInt32 = 0x06

    // IOHID's C client keeps internal unfair locks and service references that
    // are sensitive to thread affinity. The actor serializes callers, but an
    // actor may resume on different cooperative threads between calls. Keep
    // every HID framework operation on one dedicated serial thread as well.
    private let ioQueue = DispatchQueue(
        label: "com.maxoliinyk.TopRow.hid-io",
        qos: .userInitiated,
        autoreleaseFrequency: .workItem
    )

    func availableServices() -> [HIDServiceDescriptor] {
        let queue = ioQueue
        return queue.sync {
            Self.withSelectedServices { services in
                services.map(\.descriptor)
            }
        }
    }

    func apply(
        desired: [HIDMappingPair],
        ownership: OwnershipState
    ) -> HIDApplyResult {
        let queue = ioQueue
        return queue.sync {
            Self.withSelectedServices { services in
                guard !services.isEmpty else {
                    return HIDApplyResult(
                        selectedServices: [],
                        snapshots: [],
                        ownership: ownership,
                        conflicts: [:],
                        error: .unavailableHardware
                    )
                }

                // A missing UserKeyMapping property is the normal “no
                // remap” state. A malformed property is different: applying
                // a plan without knowing the complete current array could
                // overwrite another tool's mapping, so fail closed.
                guard !services.contains(where: { $0.mappingRead.isInvalid }) else {
                    return HIDApplyResult(
                        selectedServices: services.map(\.descriptor),
                        snapshots: [],
                        ownership: ownership,
                        conflicts: [:],
                        error: .readFailed
                    )
                }

                var nextOwnership = ownership
                let selectedServices = services.map(\.descriptor)
                var snapshots: [HIDServiceSnapshot] = []
                var conflicts: [HIDUsage: HIDUsage] = [:]

                for service in services {
                    let previous = ownership.ownership(for: service.descriptor.fingerprint)
                    let baseline = previous?.baseline ?? service.mappingRead.mappings
                    let previouslyApplied = previous?.applied ?? []
                    let merge = HIDMappingMerge.merge(
                        current: service.mappingRead.mappings,
                        baseline: baseline,
                        previouslyApplied: previouslyApplied,
                        desired: desired
                    )

                    // Record the intended ownership before the write so a partial
                    // multi-service update can still be reconciled on the next launch.
                    let record = ServiceOwnership(
                        fingerprint: service.descriptor.fingerprint,
                        baseline: baseline,
                        applied: merge.applied
                    )
                    nextOwnership.update(record)

                    if merge.mappings != service.mappingRead.mappings {
                        let success = Self.setMappings(merge.mappings, on: service.client)
                        guard success else {
                            return HIDApplyResult(
                                selectedServices: selectedServices,
                                snapshots: snapshots,
                                ownership: nextOwnership,
                                conflicts: conflicts,
                                error: .writeFailed
                            )
                        }
                    }

                    let verified: [HIDMappingPair]
                    switch Self.readMappings(from: service.client) {
                    case let .values(values):
                        verified = values
                    case .missing:
                        // Clearing the last mapping can make macOS remove the
                        // property entirely. That is equivalent to [] for
                        // verification; a missing property cannot satisfy a
                        // non-empty desired array.
                        guard merge.mappings.isEmpty else {
                            return HIDApplyResult(
                                selectedServices: selectedServices,
                                snapshots: snapshots,
                                ownership: nextOwnership,
                                conflicts: conflicts,
                                error: .readFailed
                            )
                        }
                        verified = []
                    case .invalid:
                        return HIDApplyResult(
                            selectedServices: selectedServices,
                            snapshots: snapshots,
                            ownership: nextOwnership,
                            conflicts: conflicts,
                            error: .readFailed
                        )
                    }
                    guard verified == merge.mappings else {
                        return HIDApplyResult(
                            selectedServices: selectedServices,
                            snapshots: snapshots,
                            ownership: nextOwnership,
                            conflicts: conflicts,
                            error: .verificationFailed
                        )
                    }

                    conflicts.merge(merge.conflicts) { _, new in new }
                    snapshots.append(HIDServiceSnapshot(descriptor: service.descriptor, mappings: verified))
                }

                return HIDApplyResult(
                    selectedServices: selectedServices,
                    snapshots: snapshots,
                    ownership: nextOwnership,
                    conflicts: conflicts,
                    error: nil
                )
            }
        }
    }

    private struct ServiceHandle {
        let client: IOHIDServiceClient
        let descriptor: HIDServiceDescriptor
        let mappingRead: MappingRead
    }

    private enum MappingRead {
        case missing
        case values([HIDMappingPair])
        case invalid

        var mappings: [HIDMappingPair] {
            switch self {
            case .missing, .invalid: []
            case let .values(mappings): mappings
            }
        }

        var isInvalid: Bool {
            if case .invalid = self { return true }
            return false
        }
    }

    /// The HID framework's service references are only valid while the event
    /// system client and copied service array are alive. Keep all reads/writes
    /// inside this synchronous scope; never return a raw service pointer to a
    /// later actor turn.
    private static func withSelectedServices<Result>(
        _ body: ([ServiceHandle]) -> Result
    ) -> Result {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let services = IOHIDEventSystemClientCopyServices(client) else {
            return body([])
        }

        var handles: [ServiceHandle] = []
        for index in 0..<CFArrayGetCount(services) {
            guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = unsafeBitCast(raw, to: IOHIDServiceClient.self)

            let product = Self.stringProperty(service, key: "Product") ?? "Unknown keyboard"
            let transport = Self.stringProperty(service, key: "Transport") ?? ""
            let builtIn = Self.boolProperty(service, key: "Built-In")
            guard HIDServiceSelector.accepts(
                conformsToKeyboard: IOHIDServiceClientConformsTo(service, Self.genericDesktopPage, Self.keyboardUsage) != 0,
                product: product,
                transport: transport,
                isBuiltIn: builtIn
            ) else { continue }

            let registryID = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0
            let fingerprint = [
                product,
                transport,
                Self.stringProperty(service, key: "Manufacturer") ?? "",
                Self.numberProperty(service, key: "VendorID")?.stringValue ?? "",
                Self.numberProperty(service, key: "ProductID")?.stringValue ?? "",
                Self.numberProperty(service, key: "LocationID")?.stringValue ?? ""
            ].joined(separator: "|")

            handles.append(ServiceHandle(
                client: service,
                descriptor: HIDServiceDescriptor(
                    registryID: registryID,
                    fingerprint: fingerprint,
                    product: product,
                    isBuiltIn: builtIn || product.localizedCaseInsensitiveContains("apple internal keyboard")
                ),
                mappingRead: Self.readMappings(from: service)
            ))
        }

        // Keep both the event client and copied service array alive through the
        // entire transaction. Service pointers are borrowed from that array.
        return withExtendedLifetime(client) {
            withExtendedLifetime(services) {
                body(handles)
            }
        }
    }

    private static func readMappings(from service: IOHIDServiceClient) -> MappingRead {
        guard let property = IOHIDServiceClientCopyProperty(service, propertyKeyValue as CFString) else {
            return .missing
        }

        guard let array = property as? [Any] else { return .invalid }
        var mappings: [HIDMappingPair] = []
        mappings.reserveCapacity(array.count)

        for item in array {
            guard let dictionary = item as? [String: Any],
                  let source = (dictionary["HIDKeyboardModifierMappingSrc"] as? NSNumber)?.uint64Value,
                  let destination = (dictionary["HIDKeyboardModifierMappingDst"] as? NSNumber)?.uint64Value
            else { return .invalid }

            mappings.append(HIDMappingPair(
                source: HIDUsage(page: UInt32(source >> 32), usage: UInt32(source & 0xFFFF_FFFF)),
                destination: HIDUsage(page: UInt32(destination >> 32), usage: UInt32(destination & 0xFFFF_FFFF))
            ))
        }

        let canonical = Set(mappings).sorted { lhs, rhs in
            if lhs.source.rawValue == rhs.source.rawValue {
                return lhs.destination.rawValue < rhs.destination.rawValue
            }
            return lhs.source.rawValue < rhs.source.rawValue
        }
        return .values(canonical)
    }

    private static func setMappings(_ mappings: [HIDMappingPair], on service: IOHIDServiceClient) -> Bool {
        let array: [[String: Any]] = mappings.map { pair in
            [
                "HIDKeyboardModifierMappingSrc": NSNumber(value: pair.source.rawValue),
                "HIDKeyboardModifierMappingDst": NSNumber(value: pair.destination.rawValue)
            ]
        }
        return IOHIDServiceClientSetProperty(service, propertyKeyValue as CFString, array as NSArray)
    }

    private static func stringProperty(_ service: IOHIDServiceClient, key: String) -> String? {
        IOHIDServiceClientCopyProperty(service, key as CFString) as? String
    }

    private static func boolProperty(_ service: IOHIDServiceClient, key: String) -> Bool {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.boolValue ?? false
    }

    private static func numberProperty(_ service: IOHIDServiceClient, key: String) -> NSNumber? {
        IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber
    }
}
