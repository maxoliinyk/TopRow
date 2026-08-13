//
//  HIDServiceMonitor.swift
//  TopRow
//
//  Created by Max Oliinyk on 13.08.26.
//

import Foundation

/// Watches the small set of services that TopRow is allowed to touch.
///
/// A service can be recreated by sleep/wake, login, or HID stack changes while
/// the app remains alive. Polling the already-filtered descriptor list avoids
/// opening an event tap or keeping a helper process around, and gives the
/// reconciliation actor a single, serialized refresh path.
@MainActor
final class HIDServiceMonitor {
    private let hidService: HIDMappingService
    private let onChange: () -> Void
    private var task: Task<Void, Never>?
    private var lastDescriptors: Set<HIDServiceDescriptor>?

    init(hidService: HIDMappingService, onChange: @escaping () -> Void) {
        self.hidService = hidService
        self.onChange = onChange
    }

    func start() {
        guard task == nil else { return }

        task = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let descriptors = Set(await hidService.availableServices())
                if let lastDescriptors, lastDescriptors != descriptors {
                    onChange()
                }
                lastDescriptors = descriptors

                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }
            }

            task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        lastDescriptors = nil
    }
}
