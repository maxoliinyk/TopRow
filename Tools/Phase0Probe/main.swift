import Carbon.HIToolbox
import CoreFoundation
import Darwin
import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

private struct ProbeError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private final class CaptureContext: @unchecked Sendable {
    let outputURL: URL
    private let fileHandle: FileHandle

    init(outputURL: URL) throws {
        self.outputURL = outputURL
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: outputURL)
    }

    func record(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)

        // Release events are noisy for this experiment. The down value is
        // sufficient to identify the source usage and layer.
        guard integerValue != 0 else { return }

        let device = IOHIDElementGetDevice(element)
        let product = deviceProperty(device, key: "Product") ?? "Unknown device"
        guard product.localizedCaseInsensitiveContains("apple internal keyboard") else {
            return
        }

        let transport = deviceProperty(device, key: "Transport") ?? ""
        let record: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "product": product,
            "transport": transport,
            "usagePage": page,
            "usage": usage,
            "usageRawValue": UInt64(page) << 32 | UInt64(usage),
            "value": integerValue,
            "keyboardFunction": keyboardFunctionName(page: page, usage: usage) as Any,
            "carbonKeyCode": carbonKeyCode(page: page, usage: usage) as Any
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: record) else { return }
        fileHandle.write(data)
        fileHandle.write(Data([0x0A]))

        let function = keyboardFunctionName(page: page, usage: usage) ?? "page 0x\(String(page, radix: 16)), usage 0x\(String(usage, radix: 16))"
        print("\(function) — \(product) — page 0x\(String(page, radix: 16)), usage 0x\(String(usage, radix: 16))")
    }

    func close() {
        try? fileHandle.synchronize()
        try? fileHandle.close()
    }
}

private func inputValueCallback(
    _ context: UnsafeMutableRawPointer?,
    _ result: IOReturn,
    _ sender: UnsafeMutableRawPointer?,
    _ value: IOHIDValue
) {
    guard result == kIOReturnSuccess, let context else { return }
    Unmanaged<CaptureContext>.fromOpaque(context).takeUnretainedValue().record(value: value)
}

private func deviceProperty(_ device: IOHIDDevice, key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
}

private func keyboardFunctionName(page: UInt32, usage: UInt32) -> String? {
    guard page == 0x07 else { return nil }
    if (0x3A...0x45).contains(usage) {
        return "F\(usage - 0x39)"
    }
    if (0x68...0x73).contains(usage) {
        return "F\(usage - 0x68 + 13)"
    }
    return nil
}

private func carbonKeyCode(page: UInt32, usage: UInt32) -> Int? {
    guard page == 0x07 else { return nil }

    switch usage {
    case 0x3A: return Int(kVK_F1)
    case 0x3B: return Int(kVK_F2)
    case 0x3C: return Int(kVK_F3)
    case 0x3D: return Int(kVK_F4)
    case 0x3E: return Int(kVK_F5)
    case 0x3F: return Int(kVK_F6)
    case 0x40: return Int(kVK_F7)
    case 0x41: return Int(kVK_F8)
    case 0x42: return Int(kVK_F9)
    case 0x43: return Int(kVK_F10)
    case 0x44: return Int(kVK_F11)
    case 0x45: return Int(kVK_F12)
    case 0x68: return Int(kVK_F13)
    case 0x69: return Int(kVK_F14)
    case 0x6A: return Int(kVK_F15)
    case 0x6B: return Int(kVK_F16)
    case 0x6C: return Int(kVK_F17)
    case 0x6D: return Int(kVK_F18)
    case 0x6E: return Int(kVK_F19)
    case 0x6F: return Int(kVK_F20)
    default: return nil
    }
}

private func makeOutputDirectory(_ path: String?) throws -> URL {
    let directory: URL
    if let path {
        directory = URL(fileURLWithPath: path, isDirectory: true)
    } else {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        directory = URL(fileURLWithPath: "/tmp/toprow-phase0-\(formatter.string(from: Date()))", isDirectory: true)
    }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func runCommand(_ executable: String, arguments: [String], outputURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    let terminated = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in terminated.signal() }
    try process.run()

    guard terminated.wait(timeout: .now() + 20) == .success else {
        process.terminate()
        if terminated.wait(timeout: .now() + 1) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            _ = terminated.wait(timeout: .now() + 1)
        }
        throw ProbeError(message: "\(executable) timed out")
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    try data.write(to: outputURL, options: .atomic)

    guard process.terminationStatus == 0 else {
        throw ProbeError(message: "\(executable) exited with status \(process.terminationStatus)")
    }
}

private func copyProperty(_ service: IOHIDServiceClient, key: String) -> Any? {
    IOHIDServiceClientCopyProperty(service, key as CFString)
}

private func serviceString(_ service: IOHIDServiceClient, key: String) -> String {
    copyProperty(service, key: key) as? String ?? ""
}

private func serviceBool(_ service: IOHIDServiceClient, key: String) -> Bool {
    (copyProperty(service, key: key) as? NSNumber)?.boolValue ?? false
}

private func mappingRecords(_ service: IOHIDServiceClient) -> [[String: Any]] {
    guard let property = copyProperty(service, key: "UserKeyMapping"),
          let mappings = property as? [Any]
    else { return [] }

    return mappings.compactMap { item in
        guard let dictionary = item as? [String: Any],
              let source = (dictionary["HIDKeyboardModifierMappingSrc"] as? NSNumber)?.uint64Value,
              let destination = (dictionary["HIDKeyboardModifierMappingDst"] as? NSNumber)?.uint64Value
        else { return nil }

        return [
            "source": source,
            "destination": destination,
            "sourcePage": UInt32(source >> 32),
            "sourceUsage": UInt32(source & 0xFFFF_FFFF),
            "destinationPage": UInt32(destination >> 32),
            "destinationUsage": UInt32(destination & 0xFFFF_FFFF)
        ]
    }
}

private func structuredServiceSnapshot() -> [[String: Any]] {
    let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    guard let services = IOHIDEventSystemClientCopyServices(client) else { return [] }

    var records: [[String: Any]] = []
    for index in 0..<CFArrayGetCount(services) {
        guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
        let service = unsafeBitCast(raw, to: IOHIDServiceClient.self)
        let registryID = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0
        let conforms = IOHIDServiceClientConformsTo(service, 0x01, 0x06) != 0

        records.append([
            "registryID": registryID,
            "product": serviceString(service, key: "Product"),
            "manufacturer": serviceString(service, key: "Manufacturer"),
            "transport": serviceString(service, key: "Transport"),
            "builtIn": serviceBool(service, key: "Built-In"),
            "conformsToGenericDesktopKeyboard": conforms,
            "vendorID": (copyProperty(service, key: "VendorID") as? NSNumber)?.uint32Value ?? 0,
            "productID": (copyProperty(service, key: "ProductID") as? NSNumber)?.uint32Value ?? 0,
            "locationID": (copyProperty(service, key: "LocationID") as? NSNumber)?.uint32Value ?? 0,
            "userKeyMapping": mappingRecords(service)
        ])
    }
    return records
}

private func writeJSON(_ value: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
}

private func snapshot(to directory: URL) throws {
    let hidutil = "/usr/bin/hidutil"
    let commands: [(name: String, arguments: [String])] = [
        ("user-key-mapping.txt", ["property", "--get", "UserKeyMapping"]),
        ("hid-list.ndjson", ["list", "--matching", "keyboard", "--ndjson"]),
        ("services.xml", ["dump", "services", "--format", "xml"])
    ]

    for command in commands {
        do {
            try runCommand(hidutil, arguments: command.arguments, outputURL: directory.appendingPathComponent(command.name))
        } catch {
            let message = "Command failed: \(error.localizedDescription)\n"
            try Data(message.utf8).write(to: directory.appendingPathComponent(command.name), options: .atomic)
            print("Warning: \(message.trimmingCharacters(in: .newlines))")
        }
    }

    try writeJSON(structuredServiceSnapshot(), to: directory.appendingPathComponent("services-structured.json"))

    print("Snapshot written to \(directory.path)")
    print("No HID properties were written.")
}

private func capture(seconds: Double, to directory: URL) throws {
    let context = try CaptureContext(outputURL: directory.appendingPathComponent("events.ndjson"))
    defer { context.close() }

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    let matching: [String: Any] = [
        "DeviceUsagePage": NSNumber(value: 0x01),
        "DeviceUsage": NSNumber(value: 0x06)
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

    let opaqueContext = Unmanaged.passUnretained(context).toOpaque()
    IOHIDManagerRegisterInputValueCallback(manager, inputValueCallback, opaqueContext)
    IOHIDManagerSetDispatchQueue(manager, DispatchQueue(label: "toprow.phase0.capture"))
    IOHIDManagerActivate(manager)
    defer { IOHIDManagerCancel(manager) }

    print("Capturing built-in keyboard value-down events for \(seconds) seconds.")
    print("Press normal and Fn-layer function-row keys now. Ctrl-C also stops the process.")
    Thread.sleep(forTimeInterval: seconds)
    print("Events written to \(directory.appendingPathComponent("events.ndjson").path)")
}

private func usage() {
    print("Usage:")
    print("  phase0-probe snapshot [output-directory]")
    print("  phase0-probe capture [seconds] [output-directory]")
    print("")
    print("The probe is read-only. It never calls hidutil property --set and never writes UserKeyMapping.")
}

private func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        usage()
        return
    }

    switch command {
    case "snapshot":
        let directory = try makeOutputDirectory(arguments.dropFirst().first)
        try snapshot(to: directory)
    case "capture":
        let seconds = arguments.dropFirst().first.flatMap(Double.init) ?? 30
        let outputPath = arguments.dropFirst(2).first
        let directory = try makeOutputDirectory(outputPath)
        try capture(seconds: max(seconds, 1), to: directory)
    case "help", "--help", "-h":
        usage()
    default:
        throw ProbeError(message: "Unknown command: \(command)")
    }
}

do {
    try main()
} catch {
    fputs("phase0-probe: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
