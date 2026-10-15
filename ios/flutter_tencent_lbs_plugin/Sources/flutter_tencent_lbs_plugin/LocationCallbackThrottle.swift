import Foundation

/// Throttles fresh SDK callbacks without restarting the location manager or
/// scheduling a timer that could replay an old fix while the device is still.
struct LocationCallbackThrottle {
    private(set) var intervalMilliseconds: Int64 = 1000
    private var intervalSeconds: TimeInterval { Double(intervalMilliseconds) / 1000 }
    private var lastDeliveryUptime: TimeInterval?

    mutating func updateInterval(milliseconds: Int64) {
        if milliseconds != intervalMilliseconds {
            intervalMilliseconds = milliseconds
            reset()
        }
    }

    mutating func reset() {
        lastDeliveryUptime = nil
    }

    mutating func shouldDeliver(at uptime: TimeInterval) -> Bool {
        if let lastDeliveryUptime, uptime - lastDeliveryUptime < intervalSeconds {
            return false
        }
        lastDeliveryUptime = uptime
        return true
    }
}
