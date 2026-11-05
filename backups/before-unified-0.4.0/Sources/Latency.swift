import Foundation

// Evaluate a second of frame acknowledgements instead of reacting to a handful
// of frames. The median rejects brief stalls; sustained overload still backs off.
struct AdaptiveQuality {
    private(set) var ceiling: Int
    private(set) var bitrate: Int
    private var lastChange: UInt64 = 0
    private var goodSince: UInt64?
    private var congestedSince: UInt64?
    private var windowStart: UInt64?
    private var lastObservation: UInt64?
    private var samples: [Double] = []
    private var recoveryUntil: UInt64 = 0
    init(ceiling: Int) {
        self.ceiling = ceiling
        // The explicitly selected quality profiles use their available budget.
        // Starting Maximum at 12 Mb/s starved RTVC under detailed motion, while
        // its conservative RTT recovery could never reach the selected ceiling.
        // Automatic/slow retain their smaller startup; congestion still backs off.
        bitrate = min(ceiling, ceiling >= 20_000_000 ? 40_000_000 : 6_000_000)
    }
    // Changing a ceiling retains the settled rate and the overload cooldown.
    mutating func reconfigure(ceiling: Int) {
        self.ceiling = ceiling; bitrate = min(bitrate, ceiling)
        samples.removeAll(keepingCapacity: true); windowStart = nil
        goodSince = nil; congestedSince = nil
    }
    mutating func observe(roundTripMS: Double, now: UInt64) -> Int? {
        guard roundTripMS.isFinite, roundTripMS >= 0,
              lastObservation.map({ now >= $0 }) ?? true else { return nil }
        lastObservation = now
        if windowStart == nil { windowStart = now }
        samples.append(roundTripMS)
        if samples.count > 512 { samples.removeFirst(samples.count - 512) }
        guard let start = windowStart, now - start >= 1_000_000_000 else { return nil }
        let sorted = samples.sorted()
        let typical = sorted[sorted.count / 2]
        let upper = sorted[min(sorted.count-1, sorted.count * 3 / 4)]
        let sufficient = sorted.count >= 8
        samples.removeAll(keepingCapacity: true); windowStart = now
        if typical > 80 {
            goodSince = nil
            if congestedSince == nil { congestedSince = now }
            let severe = typical >= 250
            let interval: UInt64 = severe ? 2_000_000_000 : 3_000_000_000
            guard severe || now - congestedSince! >= 2_000_000_000,
                  now >= lastChange, now - lastChange >= interval else { return nil }
            let next = max(min(ceiling, 1_500_000), bitrate * (severe ? 75 : 90) / 100)
            guard next < bitrate else { return nil }
            bitrate = next; lastChange = now; recoveryUntil = now + 20_000_000_000; return next
        }
        congestedSince = nil
        guard sufficient, typical < 45, upper < 60, now >= recoveryUntil else { goodSince = nil; return nil }
        if goodSince == nil { goodSince = now }
        guard let good = goodSince, now - good >= 4_000_000_000,
              now >= lastChange, now - lastChange >= 4_000_000_000 else { return nil }
        let next = min(ceiling, bitrate + max(500_000, bitrate / 4))
        guard next > bitrate else { return nil }
        bitrate = next; lastChange = now; goodSince = now; return next
    }
}

// Capture may outpace the network. Retain one recent image, never a FIFO of old images.
struct LatestFrame<Value> {
    private var value: Value?
    mutating func offer(_ value: Value) { self.value = value }
    mutating func take() -> Value? { defer { value = nil }; return value }
    mutating func clear() { value = nil }
}
