import Foundation
import IOKit

/* The MacBook's ambient light sensor, the one auto-brightness reads.

   There is no public API for it on Apple Silicon: the sensor is an HID
   service on the always-on processor ("als" on AppleSPUVD6286), reachable
   only through IOHIDEventSystemClient, which IOKit exports but doesn't
   declare. The symbols are resolved at runtime like SkyLight's in
   AppearanceSwitcher; if any is missing, or the Mac has no sensor (desktops,
   external displays don't expose theirs), `isAvailable` is false and the
   setting stays off and disabled. No permission prompt is involved. */
enum AmbientLight {
    private typealias CreateFunction = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFunction = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServicesFunction = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEventFunction =
        @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatValueFunction = @convention(c) (AnyObject, Int32) -> Double

    /* kIOHIDEventTypeAmbientLightSensor, and its level field
       (kIOHIDEventFieldAmbientLightSensorLevel = type << 16), in lux. */
    private static let eventType: Int64 = 12
    private static let levelField: Int32 = 12 << 16

    private static let sensor:
        (
            client: AnyObject, service: AnyObject,
            copyEvent: CopyEventFunction, getFloat: GetFloatValueFunction
        )? = {
            guard
                let handle = dlopen(
                    "/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
                let create = dlsym(handle, "IOHIDEventSystemClientCreate"),
                let setMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
                let copyServices = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
                let copyEvent = dlsym(handle, "IOHIDServiceClientCopyEvent"),
                let getFloat = dlsym(handle, "IOHIDEventGetFloatValue"),
                let client = unsafeBitCast(create, to: CreateFunction.self)(kCFAllocatorDefault)?
                    .takeRetainedValue()
            else { return nil }
            /* Vendor page 0xFF00, usage 4: the ambient light sensor. */
            unsafeBitCast(setMatching, to: SetMatchingFunction.self)(
                client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 4] as CFDictionary)
            guard
                let services = unsafeBitCast(copyServices, to: CopyServicesFunction.self)(client)?
                    .takeRetainedValue() as? [AnyObject],
                let service = services.first
            else { return nil }
            /* Kept with the service: the client owns its connection. */
            return (
                client, service,
                unsafeBitCast(copyEvent, to: CopyEventFunction.self),
                unsafeBitCast(getFloat, to: GetFloatValueFunction.self)
            )
        }()

    static var isAvailable: Bool { sensor != nil }

    /// The light around the Mac in lux, or nil while there's nothing to read
    /// (no sensor, or the lid is closed and the sensor sees only the keyboard).
    static func lux() -> Double? {
        guard let sensor, !isLidClosed,
            let event = sensor.copyEvent(sensor.service, eventType, 0, 0)?.takeRetainedValue()
        else { return nil }
        let lux = sensor.getFloat(event, levelField)
        return lux.isFinite && lux >= 0 ? lux : nil
    }

    /* Closed in clamshell mode (an external display keeps the Mac awake). */
    static var isLidClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        let state = IORegistryEntryCreateCFProperty(
            root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return state as? Bool ?? false
    }
}

/* Decides when the light has really changed. Pure, so it can be tested:
   readings go in with their time, and out comes a zone only when the light
   has just settled into it.

   Two thresholds with a gap between them (hysteresis): darker than
   `darkBelow` is dark, brighter than `ratio` times that is light, and in
   between nothing changes. A zone counts only after the light has stayed in
   it for `dwell`, so a passing shadow or a hand over the sensor does nothing.

   It acts on changes, never on states. A settled zone is reported once;
   whatever the user does by hand afterwards (the shortcut, the menu bar
   icon) stands until the light settles into the other zone. */
struct AmbientTracker {
    enum Zone: Equatable {
        case dark, light
    }

    static let ratio = 4.0
    static let dwell: TimeInterval = 30
    /* Nothing to undo the first time (after launch, turning the feature
       on, or moving the slider), so a few readings are enough. */
    static let firstDwell: TimeInterval = 6
    /* Readings further apart than this mean the Mac slept or the lid was
       closed: the light before the gap says nothing about now. */
    static let maxGap: TimeInterval = 15

    let darkBelow: Double
    private(set) var settled: Zone?
    private var candidate: Zone?
    private var candidateSince: Date?
    private var lastReading: Date?

    init(darkBelow: Double) {
        self.darkBelow = darkBelow
    }

    static func zone(lux: Double, darkBelow: Double) -> Zone? {
        if lux < darkBelow { return .dark }
        if lux > darkBelow * ratio { return .light }
        return nil
    }

    mutating func feed(lux: Double, at now: Date) -> Zone? {
        if let lastReading, now.timeIntervalSince(lastReading) > Self.maxGap {
            candidateSince = nil
        }
        lastReading = now
        let zone = Self.zone(lux: lux, darkBelow: darkBelow)
        if candidateSince == nil || zone != candidate {
            candidate = zone
            candidateSince = now
        }
        guard let zone, zone != settled, let candidateSince,
            now.timeIntervalSince(candidateSince) >= (settled == nil ? Self.firstDwell : Self.dwell)
        else { return nil }
        settled = zone
        return zone
    }

    /// No reading for a while (lid closed, displays asleep): start over
    /// counting, but remember what was last settled.
    mutating func interrupt() {
        candidateSince = nil
        lastReading = nil
    }
}
