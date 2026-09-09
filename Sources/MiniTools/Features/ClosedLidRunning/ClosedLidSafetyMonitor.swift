import Foundation
import IOKit.ps

struct ClosedLidSafetySnapshot {
    let batteryPercent: Int?
}

enum ClosedLidSafetyMonitor {
    static func snapshot() -> ClosedLidSafetySnapshot {
        ClosedLidSafetySnapshot(batteryPercent: batteryPercent())
    }

    private static func batteryPercent() -> Int? {
        guard let information = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourceList = IOPSCopyPowerSourcesList(information)?.takeRetainedValue()
                as? [CFTypeRef] else {
            return nil
        }

        for source in sourceList {
            guard let description = IOPSGetPowerSourceDescription(information, source)?
                .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else {
                continue
            }
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            if let current, let maximum, maximum > 0 {
                return Int((Double(current) / Double(maximum) * 100).rounded())
            }
            return nil
        }
        return nil
    }
}
