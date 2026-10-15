import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

var throttle = LocationCallbackThrottle()
expect(throttle.shouldDeliver(at: 100), "The first fresh fix must be delivered")
expect(!throttle.shouldDeliver(at: 100.5), "Updates within the interval must be suppressed")
expect(throttle.shouldDeliver(at: 101), "An update at the interval boundary must be delivered")
throttle.updateInterval(milliseconds: 30000)
expect(throttle.shouldDeliver(at: 101.1), "Changing interval should accept the next fresh fix")
expect(!throttle.shouldDeliver(at: 130), "The longer interval must take effect without restart")
expect(throttle.shouldDeliver(at: 131.2), "A fresh fix after 30 seconds must be delivered")
throttle.updateInterval(milliseconds: 1000)
expect(throttle.shouldDeliver(at: 131.3), "Shortening interval must recover immediately")
expect(!throttle.shouldDeliver(at: 131.4), "Recovery must not disable throttling")
throttle.reset()
expect(throttle.shouldDeliver(at: 131.5), "A new recording session must receive its first fix")
print("9 iOS callback throttle checks passed")
