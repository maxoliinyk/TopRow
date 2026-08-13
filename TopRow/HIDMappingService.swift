import Foundation
import IOKit
import IOKit.hidsystem

nonisolated struct HIDServiceSnapshot: Equatable, Sendable {
    let descriptor: HIDServiceDescriptor
    let mappings: [HIDMappingPair]
}

nonisolated struct HIDApplyResult: Equatable, Sendable {
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
    private let propertyKey = "UserKeyMapping" as CFString
    private let genericDesktopPage: UInt32 = 0x01
    private let keyboardUsage: UInt32 = 0x06

    func availableServices() -> [HIDServiceDescriptor] {
        let services = enumerateServices()
        defer { services.forEach { Unmanaged.passUnretained($0.client).release() } }
        return services.map(\.descriptor)
    }

    func apply(
        desired: [HIDMappingPair],
        ownership: OwnershipState
    ) -> HIDApplyResult {
        let services = enumerateServices()
        guard !services.isEmpty else {
            return HIDApplyResult(
                snapshots: [],
                ownership: ownership,
                conflicts: [:],
                error: .unavailableHardware
            )
        }

        var nextOwnership = ownership
        var snapshots: [HIDServiceSnapshot] = []
        var conflicts: [HIDUsage: HIDUsage] = [:]

        for service in services {
            defer { Unmanaged.passUnretained(service.client).release() }
            let previous = ownership.ownership(for: service.descriptor.fingerprint)
            let baseline = previous?.baseline ?? service.mappings
            let previouslyApplied = previous?.applied ?? []
            let merge = HIDMappingMerge.merge(
                current: service.mappings,
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

            if merge.mappings != service.mappings {
                let success = setMappings(merge.mappings, on: service.client)
                guard success else {
                    return HIDApplyResult(
                        snapshots: snapshots,
                        ownership: nextOwnership,
                        conflicts: conflicts,
                        error: .writeFailed
                    )
                }
            }

            let verified = readMappings(from: service.client)
            guard verified == merge.mappings else {
                return HIDApplyResult(
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
            snapshots: snapshots,
            ownership: nextOwnership,
            conflicts: conflicts,
            error: nil
        )
    }

    private struct ServiceHandle {
        let client: IOHIDServiceClient
        let descriptor: HIDServiceDescriptor
        let mappings: [HIDMappingPair]
    }

    private func enumerateServices() -> [ServiceHandle] {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let services = IOHIDEventSystemClientCopyServices(client) else { return [] }

        var handles: [ServiceHandle] = []
        for index in 0..<CFArrayGetCount(services) {
            guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = unsafeBitCast(raw, to: IOHIDServiceClient.self)
            _ = Unmanaged.passUnretained(service).retain()

            let product = stringProperty(service, key: "Product") ?? "Unknown keyboard"
            let transport = stringProperty(service, key: "Transport") ?? ""
            let builtIn = boolProperty(service, key: "Built-In")
            guard HIDServiceSelector.accepts(
                conformsToKeyboard: IOHIDServiceClientConformsTo(service, genericDesktopPage, keyboardUsage) != 0,
                product: product,
                transport: transport,
                isBuiltIn: builtIn
            ) else { continue }

            let registryID = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0
            let fingerprint = [
                product,
                transport,
                stringProperty(service, key: "Manufacturer") ?? "",
                numberProperty(service, key: "VendorID")?.stringValue ?? "",
                numberProperty(service, key: "ProductID")?.stringValue ?? "",
                numberProperty(service, key: "LocationID")?.stringValue ?? ""
            ].joined(separator: "|")

            handles.append(ServiceHandle(
                client: service,
                descriptor: HIDServiceDescriptor(
                    registryID: registryID,
                    fingerprint: fingerprint,
                    product: product,
                    isBuiltIn: builtIn || product.localizedCaseInsensitiveContains("apple internal keyboard")
                ),
                mappings: readMappings(from: service)
            ))
        }

        return handles
    }

    private func readMappings(from service: IOHIDServiceClient) -> [HIDMappingPair] {
        guard let property = IOHIDServiceClientCopyProperty(service, propertyKey) else {
            return []
        }

        guard let array = property as? [Any] else { return [] }
        return array.compactMap { item in
            guard let dictionary = item as? [String: Any] else { return nil }
            guard
                let source = (dictionary["HIDKeyboardModifierMappingSrc"] as? NSNumber)?.uint64Value,
                let destination = (dictionary["HIDKeyboardModifierMappingDst"] as? NSNumber)?.uint64Value
            else { return nil }

            return HIDMappingPair(
                source: HIDUsage(page: UInt32(source >> 32), usage: UInt32(source & 0xFFFF_FFFF)),
                destination: HIDUsage(page: UInt32(destination >> 32), usage: UInt32(destination & 0xFFFF_FFFF))
            )
        }
    }

    private func setMappings(_ mappings: [HIDMappingPair], on service: IOHIDServiceClient) -> Bool {
        let array: [[String: Any]] = mappings.map { pair in
            [
                "HIDKeyboardModifierMappingSrc": NSNumber(value: pair.source.rawValue),
                "HIDKeyboardModifierMappingDst": NSNumber(value: pair.destination.rawValue)
            ]
        }
        return IOHIDServiceClientSetProperty(service, propertyKey, array as NSArray)
    }

    private func stringProperty(_ service: IOHIDServiceClient, key: String) -> String? {
        IOHIDServiceClientCopyProperty(service, key as CFString) as? String
    }

    private func boolProperty(_ service: IOHIDServiceClient, key: String) -> Bool {
        (IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber)?.boolValue ?? false
    }

    private func numberProperty(_ service: IOHIDServiceClient, key: String) -> NSNumber? {
        IOHIDServiceClientCopyProperty(service, key as CFString) as? NSNumber
    }
}
