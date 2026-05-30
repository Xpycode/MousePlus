import Foundation
import IOKit
import IOKit.hid
import Observation
import os.log

/// Exploratory diagnostic — enumerates HID devices that match the standard
/// pointer / keyboard / consumer-control collections, dumps every element,
/// and live-captures input value events so the user can press a "silent"
/// MX Master button and see exactly which `(usagePage, usage, cookie)` fires.
///
/// Output: per-device snapshot JSON written to Application Support, plus a
/// "Copy JSON" button. Drives the runtime-data map that `HIDMouseButtonMonitor`
/// (plan B) will consume.
///
/// Threading: IOHIDManager is configured with a private serial dispatch queue;
/// the C value callback hops to the main actor before mutating @Observable state.
@MainActor
@Observable
final class IOHIDDeviceInspector {
    enum Status: Equatable {
        case idle
        case requestingAccess
        case denied
        case running
        case runningPartial(String)
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var devices: [HIDDeviceInfo] = []
    private(set) var elementsByDevice: [HIDDeviceInfo.ID: [HIDElementInfo]] = [:]
    private(set) var fireCountsByDevice: [HIDDeviceInfo.ID: [UInt32: Int]] = [:]
    /// Per-device ring of recent value-fires. Was a single global `lastFires`
    /// array; that conflated devices and made the snapshot's filter best-effort.
    /// Per-device makes the snapshot exact and removes cookie-overlap risk.
    private(set) var lastFiresByDevice: [HIDDeviceInfo.ID: [HIDValueCapture]] = [:]
    private(set) var lastFireCookieByDevice: [HIDDeviceInfo.ID: UInt32] = [:]
    private(set) var rawReportsByDevice: [HIDDeviceInfo.ID: [HIDRawReport]] = [:]
    /// When true, matching is widened to every HID device (including vendor-
    /// page-only interfaces, where the MX Master 3S DPI / gesture buttons
    /// likely live as HID++ reports). Toggling restarts the manager.
    var matchAllDevices: Bool = false

    private var manager: IOHIDManager?
    private var deviceRefsByID: [HIDDeviceInfo.ID: IOHIDDevice] = [:]
    /// Each input-report registration needs a buffer alive for the registration's
    /// lifetime (the C callback writes into it). We never free during start/stop;
    /// IOHIDManagerCancel stops the writes, and the inspector's own deinit
    /// frees on app exit. Buffer size pulled from kIOHIDMaxInputReportSizeKey
    /// per device, with a 256-byte ceiling.
    private var reportBuffers: [HIDDeviceInfo.ID: (pointer: UnsafeMutablePointer<UInt8>, length: Int)] = [:]
    private let queue = DispatchQueue(label: "dk.xpycode.MousePlus.HIDInspector", qos: .userInitiated)
    private let logger = Logger(subsystem: "dk.xpycode.MousePlus", category: "HIDInspector")
    /// Per-device cap. Each capture is ~80 bytes, so 10k × ~10 devices ≈ 8 MB
    /// in match-all mode — fine for a diagnostic. Old global cap of 80 covered
    /// roughly one second of mouse motion before evicting button presses.
    private let lastFiresLimit = 10_000
    /// Per-device cap. Each report is ~100 bytes incl. payload. 1k entries ≈
    /// 100 KB per device; gives room for a multi-minute HID++ capture session.
    private let rawReportsLimit = 1_000
    private let maxReportSize = 256

    func start() {
        guard manager == nil else { return }
        status = .requestingAccess

        // Trigger Input Monitoring TCC prompt cleanly. IOHIDManagerOpen alone
        // returns kIOReturnNotPermitted silently if denied — this surfaces it.
        let access = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if !access {
            // User hasn't granted yet (or denied). Continue with Open anyway —
            // the user may flip the switch live; we'll surface the denial state.
            logger.notice("Input Monitoring not yet granted; opening manager anyway")
        }

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        if matchAllDevices {
            // NULL = match every HID device. (The doc text says "no devices"
            // but every working sample passes NULL for match-all; the doc is
            // stale.) Empty dict and empty multiple-array are NOT equivalent.
            IOHIDManagerSetDeviceMatching(mgr, nil)
        } else {
            IOHIDManagerSetDeviceMatchingMultiple(mgr, Self.matchingPairs() as CFArray)
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, Self.deviceMatchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, Self.deviceRemovalCallback, context)
        IOHIDManagerRegisterInputValueCallback(mgr, Self.inputValueCallback, context)

        // Order matters: with dispatch-queue mode, Open must happen BEFORE
        // Activate. Activating first causes Open's per-device callback wiring
        // to assert ("Device has already been activated/cancelled").
        IOHIDManagerSetDispatchQueue(mgr, queue)

        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnNotPermitted {
            status = .denied
            logger.error("IOHIDManagerOpen denied — Input Monitoring permission missing")
            return
        }

        // PRE-ACTIVATE: snapshot already-matched devices and register the raw
        // input-report callback on each. Doing this post-Activate asserts
        // ("Device has already been activated/cancelled"). Hot-plug devices
        // arriving via the matching callback later won't get raw-report
        // capture for the same reason — accept that limitation.
        prepopulateDevices(manager: mgr)

        // Activate regardless of partial Open failures. With match-all,
        // IOHIDManagerOpen returns the first non-success code from any of
        // the dozens of system HID devices it tries to open — touchbar /
        // builtin sensors / system-claimed interfaces commonly return
        // kIOReturnUnsupported (0xE00002C7). Devices that DID open still
        // deliver value callbacks; we just surface the partial state.
        IOHIDManagerActivate(mgr)
        if result == kIOReturnSuccess {
            status = .running
        } else {
            let hex = String(format: "0x%08X", result)
            status = .runningPartial("Open partial (\(hex)) — some devices declined; others active")
            logger.notice("IOHIDManagerOpen partial: \(hex, privacy: .public)")
        }
    }

    /// Synchronously enumerate currently-matched devices and register raw
    /// input-report callbacks before the manager is activated.
    private func prepopulateDevices(manager mgr: IOHIDManager) {
        guard let cfSet = IOHIDManagerCopyDevices(mgr) else { return }
        let nsSet = cfSet as NSSet
        for case let device as IOHIDDevice in nsSet {
            let info = HIDIntrospect.deviceInfo(device)
            let elements = HIDIntrospect.elementInfos(device)
            handleDeviceMatched(info: info, elements: elements, ref: device, registerReports: true)
        }
    }

    func stop() {
        guard let mgr = manager else { return }
        // Once activated, IOHIDManagerRegister*Callback(mgr, nil, nil) is
        // illegal — IOKit asserts ("Manager has already been activated/cancelled").
        // The dispatch-queue contract is: register before Activate, then Cancel.
        // Cancel drains pending callbacks asynchronously; the Swift CF bridge
        // releases the manager when it goes out of scope.
        // Cancel only if Activate ran. .running and .runningPartial both imply
        // an activated manager.
        switch status {
        case .running, .runningPartial:
            IOHIDManagerCancel(mgr)
        default:
            break
        }
        manager = nil
        deviceRefsByID.removeAll()
        status = .idle
    }

    func clearFires() {
        lastFiresByDevice.removeAll()
        lastFireCookieByDevice.removeAll()
        fireCountsByDevice.removeAll()
        rawReportsByDevice.removeAll()
    }

    /// Toggles the matching breadth and restarts the manager so vendor-only
    /// interfaces (HID++ / MX Master DPI / gesture button) become visible.
    func setMatchAllDevices(_ on: Bool) {
        guard matchAllDevices != on else { return }
        matchAllDevices = on
        if manager != nil {
            stop()
            devices.removeAll()
            elementsByDevice.removeAll()
            clearFires()
            start()
        }
    }

    /// Snapshot one device's full state — descriptor + accumulated fire counts
    /// + recent live captures + raw reports. `fireCounts` is the authoritative
    /// "did element X ever fire" signal; `liveCaptures` is the bounded recent
    /// ring (newer entries at index 0).
    func snapshot(for device: HIDDeviceInfo) -> HIDDeviceSnapshot {
        let elements = elementsByDevice[device.id] ?? []
        let counts = fireCountsByDevice[device.id] ?? [:]
        let elementByCookie = Dictionary(uniqueKeysWithValues: elements.map { ($0.cookie, $0) })
        let fireCounts: [HIDFireCount] = counts
            .map { (cookie, count) in
                let el = elementByCookie[cookie]
                return HIDFireCount(
                    cookie: cookie,
                    usagePage: el?.usagePage ?? 0,
                    usage: el?.usage ?? 0,
                    count: count
                )
            }
            .sorted { $0.count > $1.count }
        return HIDDeviceSnapshot(
            capturedAt: Date(),
            device: device,
            elements: elements,
            fireCounts: fireCounts,
            liveCaptures: lastFiresByDevice[device.id] ?? [],
            rawReports: rawReportsByDevice[device.id] ?? [],
            matchAllDevices: matchAllDevices
        )
    }

    /// True if this device's element set contains any vendor-page entries
    /// (`0xFF00`+). Used by the picker label to mark HID++-capable devices.
    func hasVendorPipe(_ device: HIDDeviceInfo) -> Bool {
        guard let elements = elementsByDevice[device.id] else { return false }
        return elements.contains { $0.usagePage >= 0xFF00 }
    }

    // MARK: - Matching

    /// Standard "input devices we care about" set. Catches receiver-style
    /// devices that expose multiple application collections (e.g. Logitech
    /// Bolt: separate Mouse + Keyboard + Consumer interfaces on one dongle).
    private static func matchingPairs() -> [[String: Int]] {
        let pairs: [(page: Int, usage: Int)] = [
            (0x01, 0x02), // GenericDesktop / Mouse
            (0x01, 0x01), // GenericDesktop / Pointer
            (0x01, 0x06), // GenericDesktop / Keyboard
            (0x01, 0x07), // GenericDesktop / Keypad
            (0x0C, 0x01)  // Consumer / ConsumerControl
        ]
        return pairs.map { pair in
            [
                kIOHIDDeviceUsagePageKey: pair.page,
                kIOHIDDeviceUsageKey: pair.usage
            ]
        }
    }

    // MARK: - C Callbacks (run on `queue`)

    private static let deviceMatchingCallback: IOHIDDeviceCallback = { context, _, _, deviceRef in
        guard let context else { return }
        let inspector = Unmanaged<IOHIDDeviceInspector>.fromOpaque(context).takeUnretainedValue()
        let info = HIDIntrospect.deviceInfo(deviceRef)
        let elements = HIDIntrospect.elementInfos(deviceRef)
        Task { @MainActor in
            // Hot-plug path: device is already activated by the time this
            // fires (post-Activate), so we cannot register input-report
            // callbacks on it. Caller does element listing + value-callback
            // (which IS manager-level) only.
            inspector.handleDeviceMatched(info: info, elements: elements, ref: deviceRef, registerReports: false)
        }
    }

    private static let deviceRemovalCallback: IOHIDDeviceCallback = { context, _, _, deviceRef in
        guard let context else { return }
        let inspector = Unmanaged<IOHIDDeviceInspector>.fromOpaque(context).takeUnretainedValue()
        let info = HIDIntrospect.deviceInfo(deviceRef)
        Task { @MainActor in
            inspector.handleDeviceRemoved(id: info.id)
        }
    }

    private static let inputReportCallback: IOHIDReportCallback = { context, result, sender, reportType, reportID, report, reportLength in
        guard let context, result == kIOReturnSuccess, reportType == kIOHIDReportTypeInput else { return }
        let inspector = Unmanaged<IOHIDDeviceInspector>.fromOpaque(context).takeUnretainedValue()
        // Copy bytes synchronously — the buffer is reused on the next report.
        let bytes = Data(bytes: report, count: reportLength)
        let raw = HIDRawReport(timestamp: Date(), reportID: reportID, bytes: bytes)
        // sender is the IOHIDDevice that fired the report.
        let device = Unmanaged<IOHIDDevice>.fromOpaque(sender!).takeUnretainedValue()
        let deviceID = HIDIntrospect.deviceInfo(device).id
        Task { @MainActor in
            inspector.handleRawReport(deviceID: deviceID, report: raw)
        }
    }

    private static let inputValueCallback: IOHIDValueCallback = { context, _, _, valueRef in
        guard let context else { return }
        let inspector = Unmanaged<IOHIDDeviceInspector>.fromOpaque(context).takeUnretainedValue()
        // Extract everything we need synchronously — IOHIDValueRef is unretained
        // and only valid for the duration of this callback.
        let element = IOHIDValueGetElement(valueRef)
        let device = IOHIDElementGetDevice(element)
        let cookie = UInt32(IOHIDElementGetCookie(element))
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(valueRef)
        let deviceID = HIDIntrospect.deviceInfo(device).id
        let capture = HIDValueCapture(
            timestamp: Date(),
            cookie: cookie,
            usagePage: usagePage,
            usage: usage,
            integerValue: intValue
        )
        Task { @MainActor in
            inspector.handleValueFire(deviceID: deviceID, capture: capture)
        }
    }

    // MARK: - Main-actor handlers

    private func handleDeviceMatched(info: HIDDeviceInfo, elements: [HIDElementInfo], ref: IOHIDDevice, registerReports: Bool) {
        if !devices.contains(where: { $0.id == info.id }) {
            devices.append(info)
            devices.sort { lhs, rhs in
                if lhs.primaryUsagePage != rhs.primaryUsagePage {
                    return lhs.primaryUsagePage < rhs.primaryUsagePage
                }
                return lhs.displayName < rhs.displayName
            }
        }
        elementsByDevice[info.id] = elements
        deviceRefsByID[info.id] = ref

        // Register raw-report capture only when called pre-Activate.
        // Many vendor-protocol buttons (HID++ on Logitech) emit raw input
        // reports rather than parsed element values, so the value callback
        // alone will miss them.
        if registerReports && reportBuffers[info.id] == nil {
            let declaredMax = HIDIntrospect.maxInputReportSize(ref) ?? 64
            let length = min(maxReportSize, max(8, Int(declaredMax)))
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: length)
            reportBuffers[info.id] = (pointer, length)
            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputReportCallback(ref, pointer, length, Self.inputReportCallback, context)
        }
    }

    private func handleDeviceRemoved(id: HIDDeviceInfo.ID) {
        devices.removeAll { $0.id == id }
        elementsByDevice[id] = nil
        deviceRefsByID[id] = nil
        fireCountsByDevice[id] = nil
        lastFireCookieByDevice[id] = nil
        lastFiresByDevice[id] = nil
        rawReportsByDevice[id] = nil
    }

    private func handleRawReport(deviceID: HIDDeviceInfo.ID, report: HIDRawReport) {
        var list = rawReportsByDevice[deviceID, default: []]
        list.insert(report, at: 0)
        if list.count > rawReportsLimit {
            list = Array(list.prefix(rawReportsLimit))
        }
        rawReportsByDevice[deviceID] = list
    }

    private func handleValueFire(deviceID: HIDDeviceInfo.ID, capture: HIDValueCapture) {
        var ring = lastFiresByDevice[deviceID, default: []]
        ring.insert(capture, at: 0)
        if ring.count > lastFiresLimit {
            ring = Array(ring.prefix(lastFiresLimit))
        }
        lastFiresByDevice[deviceID] = ring
        lastFireCookieByDevice[deviceID] = capture.cookie
        var counts = fireCountsByDevice[deviceID, default: [:]]
        counts[capture.cookie, default: 0] += 1
        fireCountsByDevice[deviceID] = counts
    }
}

// MARK: - Sync introspection helpers (callable from any thread)

private enum HIDIntrospect {
    static func deviceInfo(_ device: IOHIDDevice) -> HIDDeviceInfo {
        HIDDeviceInfo(
            vendorID: numberProperty(device, kIOHIDVendorIDKey) ?? 0,
            productID: numberProperty(device, kIOHIDProductIDKey) ?? 0,
            locationID: UInt64(numberProperty(device, kIOHIDLocationIDKey) ?? 0),
            manufacturer: stringProperty(device, kIOHIDManufacturerKey),
            product: stringProperty(device, kIOHIDProductKey),
            transport: stringProperty(device, kIOHIDTransportKey),
            primaryUsagePage: numberProperty(device, kIOHIDPrimaryUsagePageKey) ?? 0,
            primaryUsage: numberProperty(device, kIOHIDPrimaryUsageKey) ?? 0
        )
    }

    static func elementInfos(_ device: IOHIDDevice) -> [HIDElementInfo] {
        guard let array = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
            return []
        }
        return array.map { element in
            HIDElementInfo(
                cookie: UInt32(IOHIDElementGetCookie(element)),
                usagePage: IOHIDElementGetUsagePage(element),
                usage: IOHIDElementGetUsage(element),
                type: typeName(IOHIDElementGetType(element)),
                logicalMin: IOHIDElementGetLogicalMin(element),
                logicalMax: IOHIDElementGetLogicalMax(element),
                reportID: IOHIDElementGetReportID(element),
                reportSize: IOHIDElementGetReportSize(element),
                reportCount: IOHIDElementGetReportCount(element),
                isRelative: IOHIDElementIsRelative(element),
                isArray: IOHIDElementIsArray(element),
                name: IOHIDElementGetProperty(element, kIOHIDElementNameKey as CFString) as? String
            )
        }
    }

    private static func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private static func numberProperty(_ device: IOHIDDevice, _ key: String) -> UInt32? {
        guard let raw = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        if let n = raw as? NSNumber { return n.uint32Value }
        return nil
    }

    static func maxInputReportSize(_ device: IOHIDDevice) -> UInt32? {
        numberProperty(device, kIOHIDMaxInputReportSizeKey)
    }

    private static func typeName(_ type: IOHIDElementType) -> String {
        switch type {
        case kIOHIDElementTypeInput_Misc:    return "input.misc"
        case kIOHIDElementTypeInput_Button:  return "input.button"
        case kIOHIDElementTypeInput_Axis:    return "input.axis"
        case kIOHIDElementTypeInput_ScanCodes: return "input.scanCodes"
        case kIOHIDElementTypeOutput:        return "output"
        case kIOHIDElementTypeFeature:       return "feature"
        case kIOHIDElementTypeCollection:    return "collection"
        default:                             return "type(\(type.rawValue))"
        }
    }
}
