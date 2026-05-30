import Foundation

/// Static descriptor + live-fire snapshot for one HID device. Format is the
/// fixture schema agreed in plan A — `B` will read this back to map silent
/// MX Master buttons (thumb / gesture / wheel-mode) to usage-page+usage pairs.
struct HIDDeviceSnapshot: Codable, Equatable {
    var schemaVersion: Int = 3
    var capturedAt: Date
    var device: HIDDeviceInfo
    var elements: [HIDElementInfo]
    /// Per-element accumulated fire count for the entire capture session.
    /// Survives across the live-capture ring's overflow — the authoritative
    /// answer to "did this element ever fire" lives here, not in `liveCaptures`.
    var fireCounts: [HIDFireCount] = []
    /// Recent value-fires for this device, newest first. Bounded ring buffer;
    /// for "did button X ever fire?" use `fireCounts` instead.
    var liveCaptures: [HIDValueCapture]
    var rawReports: [HIDRawReport] = []
    /// Capture-time setting of the Inspector's match-all toggle. Tells future
    /// readers whether the device list came from the curated (page, usage)
    /// matching set or every HID device the system exposes. Optional so older
    /// schema-2 files still decode.
    var matchAllDevices: Bool? = nil
}

struct HIDFireCount: Codable, Equatable, Hashable, Identifiable {
    var id: UInt32 { cookie }
    var cookie: UInt32
    var usagePage: UInt32
    var usage: UInt32
    var count: Int
}

struct HIDDeviceInfo: Codable, Equatable, Hashable, Identifiable {
    /// Composite identity — `(vid, pid, locationID, primary)` is unique within a session.
    var id: String { "\(vendorID)-\(productID)-\(locationID)-\(primaryUsagePage):\(primaryUsage)" }

    var vendorID: UInt32
    var productID: UInt32
    var locationID: UInt64
    var manufacturer: String?
    var product: String?
    var transport: String?
    var primaryUsagePage: UInt32
    var primaryUsage: UInt32

    /// Human label combining manufacturer + product, falling back to VID/PID hex.
    var displayName: String {
        let base: String
        if let manufacturer, let product {
            base = "\(manufacturer) \(product)"
        } else if let product {
            base = product
        } else {
            base = String(format: "VID 0x%04X PID 0x%04X", vendorID, productID)
        }
        return "\(base) — \(usagePairLabel)"
    }

    var usagePairLabel: String {
        "\(HIDNaming.pageName(primaryUsagePage))/\(HIDNaming.usageName(page: primaryUsagePage, usage: primaryUsage))"
    }
}

struct HIDElementInfo: Codable, Equatable, Identifiable, Hashable {
    var id: UInt32 { cookie }

    var cookie: UInt32
    var usagePage: UInt32
    var usage: UInt32
    var type: String              // e.g. "input.button", "input.misc"
    var logicalMin: Int
    var logicalMax: Int
    var reportID: UInt32
    var reportSize: UInt32
    var reportCount: UInt32
    var isRelative: Bool
    var isArray: Bool
    var name: String?             // optional kIOHIDElementNameKey

    var humanLabel: String {
        "\(HIDNaming.pageName(usagePage))/\(HIDNaming.usageName(page: usagePage, usage: usage))"
    }
}

struct HIDValueCapture: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var timestamp: Date
    var cookie: UInt32
    var usagePage: UInt32
    var usage: UInt32
    var integerValue: Int
}

/// Raw HID input report — used to catch HID++ / vendor-protocol button events
/// that don't decompose into IOHIDValue element changes (MX Master DPI button,
/// thumb gesture button, anything riding the receiver's vendor pipe).
struct HIDRawReport: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var timestamp: Date
    var reportID: UInt32
    var bytes: Data

    var hex: String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

/// Tiny lookup for the handful of HID pages/usages this app cares about.
/// Anything unknown returns a hex label — exploratory tooling, not a full table.
enum HIDNaming {
    static func pageName(_ page: UInt32) -> String {
        switch page {
        case 0x01: return "GenericDesktop"
        case 0x02: return "Simulation"
        case 0x07: return "KeyboardOrKeypad"
        case 0x08: return "LEDs"
        case 0x09: return "Button"
        case 0x0C: return "Consumer"
        case 0x0D: return "Digitizer"
        case 0x0E: return "Haptics"
        case 0x20: return "Sensor"
        case 0xFF00...0xFFFF: return String(format: "Vendor(0x%04X)", page)
        default:   return String(format: "Page(0x%04X)", page)
        }
    }

    static func usageName(page: UInt32, usage: UInt32) -> String {
        switch page {
        case 0x01:
            switch usage {
            case 0x01: return "Pointer"
            case 0x02: return "Mouse"
            case 0x06: return "Keyboard"
            case 0x07: return "Keypad"
            case 0x30: return "X"
            case 0x31: return "Y"
            case 0x32: return "Z"
            case 0x38: return "Wheel"
            case 0x80: return "SystemControl"
            default:   return String(format: "GD_0x%02X", usage)
            }
        case 0x09:
            return "Button\(usage)"
        case 0x0C:
            switch usage {
            case 0x01: return "ConsumerControl"
            case 0xB5: return "ScanNextTrack"
            case 0xB6: return "ScanPrevTrack"
            case 0xCD: return "PlayPause"
            case 0xE9: return "VolumeIncrement"
            case 0xEA: return "VolumeDecrement"
            case 0x221: return "ACSearch"
            case 0x223: return "ACHome"
            case 0x224: return "ACBack"
            case 0x225: return "ACForward"
            case 0x279: return "ACRedo"
            case 0x27A: return "ACUndo"
            default:   return String(format: "Csmr_0x%04X", usage)
            }
        default:
            return String(format: "0x%04X", usage)
        }
    }
}
