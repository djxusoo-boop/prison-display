import Foundation

// Own one assertion only for an authenticated stream, never while discovering
// peers or waiting to reconnect. Allow normal idle sleep and release on cuts.
// Access is confined to the owning engine's serial queue.
final class StreamActivity {
    private var token: NSObjectProtocol?
    private let begin: (ProcessInfo.ActivityOptions, String) -> NSObjectProtocol
    private let end: (NSObjectProtocol) -> Void
    var isActive: Bool { token != nil }
    init(begin: @escaping (ProcessInfo.ActivityOptions, String) -> NSObjectProtocol = {
        ProcessInfo.processInfo.beginActivity(options: $0, reason: $1)
    }, end: @escaping (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }) {
        self.begin = begin; self.end = end
    }
    func start() {
        guard token == nil else { return }
        token = begin([.userInitiatedAllowingIdleSystemSleep, .latencyCritical], "PRISON DISPLAY: pantalla y entrada en directo")
    }
    func stop() {
        guard let current = token else { return }
        token = nil; end(current)
    }
    deinit { stop() }
}
import Darwin

// Ignore brief display reconfiguration bursts. Sustained load must pause the
// application's own virtual display instead of repeatedly recreating it.
struct GraphicsLoadProtection {
    let threshold: Double
    let sustainedNS: UInt64
    private var hotSince: UInt64?
    private var previous: UInt64?
    private var reported = false
    init(threshold: Double = 85, sustainedNS: UInt64 = 5_000_000_000) {
        self.threshold = threshold; self.sustainedNS = sustainedNS
    }
    mutating func observe(_ load: Double?, now: UInt64) -> Bool {
        guard !reported else { return false }
        guard let load = load, load.isFinite, load >= 0 else { hotSince = nil; return false }
        if let previous = previous, now < previous { hotSince = nil }
        previous = now
        guard load >= threshold else { hotSince = nil; return false }
        if hotSince == nil { hotSince = now }
        guard let since = hotSince, now >= since, now-since >= sustainedNS else { return false }
        reported = true; return true
    }
}

final class GraphicsLoadMonitor {
    private let queue = DispatchQueue(label: "PrisonDisplay.graphics-health", qos: .utility)
    private let reader: () -> Double?
    private let interval: Double
    private let makeProtection: () -> GraphicsLoadProtection
    private var timer: DispatchSourceTimer?
    private var protection = GraphicsLoadProtection()
    private var onOverload: (() -> Void)?
    init(interval: Double = 1, reader: @escaping () -> Double? = GraphicsLoadMonitor.systemLoad,
         makeProtection: @escaping () -> GraphicsLoadProtection = { GraphicsLoadProtection() }) {
        self.interval = interval; self.reader = reader; self.makeProtection = makeProtection
    }
    func start(onOverload: @escaping () -> Void) {
        queue.async {
            self.onOverload = onOverload
            guard self.timer == nil else { return } // Do not reset on every settings change.
            self.protection = self.makeProtection()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.interval, leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                if self.protection.observe(self.reader(), now: DispatchTime.now().uptimeNanoseconds) {
                    let callback = self.onOverload; self.timer?.cancel(); self.timer = nil; self.onOverload = nil
                    callback?()
                }
            }
            self.timer = timer; timer.resume()
        }
    }
    func stop() { queue.async { self.timer?.cancel(); self.timer = nil; self.onOverload = nil } }
    deinit { timer?.cancel() }
    static func systemLoad() -> Double? {
        // Read process metadata only, with a deadline, on the utility queue.
        // This never signals either system colour service or WindowServer.
        let task = Process(), pipe = Pipe(), lock = NSLock()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-c", "-axo", "%cpu=,comm="]
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        var data = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            lock.lock(); if data.count+chunk.count <= 128*1024 { data.append(chunk) }; lock.unlock()
        }
        do { try task.run() } catch { pipe.fileHandleForReading.readabilityHandler = nil; return nil }
        let deadline = ProcessInfo.processInfo.systemUptime+1
        while task.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if task.isRunning {
            kill(task.processIdentifier, SIGKILL) // Only our own metadata query.
            pipe.fileHandleForReading.readabilityHandler = nil; return nil
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock(); data.append(remainder); let snapshot = data; lock.unlock()
        guard task.terminationStatus == 0, let output = String(data: snapshot, encoding: .utf8) else { return nil }
        var total = 0.0
        for line in output.split(separator: "\n") {
            let fields = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            if fields.count == 2, ["colorsync.displayservices", "colorsyncd"].contains(String(fields[1]).trimmingCharacters(in: .whitespaces)), let value = Double(fields[0]) { total += value }
        }
        return total
    }
}

// Only unavailable capture sources are transient. Revoked permission and explicit
// user stop must never trigger an automatic restart.
enum CaptureFailure {
    static func isTransient(_ error: Error) -> Bool {
        let e = error as NSError
        return e.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && [-3813, -3814, -3815, -3821].contains(e.code)
    }
    static var unavailable: NSError { NSError(domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain", code: -3815, userInfo: [NSLocalizedDescriptionKey: "La pantalla todavía no está disponible para capturar."]) }
}

final class RetriedOperation<Value> {
    private let queue: DispatchQueue
    private let maximumAttempts: Int
    private let delay: (Int) -> Double
    private let shouldRetry: (Error) -> Bool
    private let request: (@escaping (Result<Value, Error>) -> Void) -> Void
    private let completion: (Result<Value, Error>) -> Void
    var onRetry: ((Int) -> Void)?
    private var attempt = 0
    private var active = true
    private var started = false
    private var ticket: UUID?
    private var pending: DispatchWorkItem?
    init(queue: DispatchQueue, maximumAttempts: Int = 6, delay: @escaping (Int) -> Double = { min(2, 0.25 * pow(2, Double($0))) }, shouldRetry: @escaping (Error) -> Bool, request: @escaping (@escaping (Result<Value, Error>) -> Void) -> Void, completion: @escaping (Result<Value, Error>) -> Void) {
        self.queue = queue; self.maximumAttempts = max(1, maximumAttempts); self.delay = delay
        self.shouldRetry = shouldRetry; self.request = request; self.completion = completion
    }
    func start() { queue.async { guard self.active, !self.started else { return }; self.started = true; self.perform() } }
    func cancel() { queue.async { self.active = false; self.ticket = nil; self.pending?.cancel(); self.pending = nil } }
    private func perform() {
        guard active else { return }
        attempt += 1; let token = UUID(); ticket = token
        request { [weak self] result in self?.queue.async {
            guard let self = self, self.active, self.ticket == token else { return }
            self.ticket = nil
            if case .failure(let error) = result, self.attempt < self.maximumAttempts, self.shouldRetry(error) {
                self.onRetry?(self.attempt)
                let work = DispatchWorkItem { [weak self] in self?.pending = nil; self?.perform() }
                self.pending = work; self.queue.asyncAfter(deadline: .now() + self.delay(self.attempt - 1), execute: work)
            } else { self.active = false; self.completion(result) }
        } }
    }
}
