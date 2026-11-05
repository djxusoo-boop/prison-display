import Foundation
#if SENDER
import ScreenCaptureKit
#endif
var failures = 0
func check(_ ok: Bool, _ name: String) { print(ok ? "PASS: \(name)" : "FAIL: \(name)"); if !ok { failures += 1 } }
var activityBegins = 0, activityEnds = 0
let activityToken = NSObject()
var activity: StreamActivity? = StreamActivity(begin: { options, reason in
    activityBegins += 1
    check(options.contains(.latencyCritical) && !options.contains(.idleSystemSleepDisabled) && !options.contains(.idleDisplaySleepDisabled) && !reason.isEmpty, "stream precision allows normal idle sleep")
    return activityToken
}, end: { token in
    check(token === activityToken, "release exactly the acquired activity token")
    activityEnds += 1
})
check(activity?.isActive == false, "discovery does not hold a streaming activity")
activity?.start(); activity?.start()
check(activityBegins == 1 && activity?.isActive == true, "configuration updates share one activity")
activity?.stop(); activity?.stop()
check(activityEnds == 1 && activity?.isActive == false, "disconnect releases activity once")
activity?.start(); activity = nil
check(activityBegins == 2 && activityEnds == 2, "reconnect and destruction leave no activity held")
func pump(_ condition: () -> Bool) -> Bool { let end = Date().addingTimeInterval(2); while !condition() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }; return condition() }
#if SENDER
check(CaptureFailure.unavailable.domain == SCStreamErrorDomain, "capture error domain matches SDK")
#endif
let q = DispatchQueue.main
var attempts = 0; var completed = 0; var recovered = false
let retry = RetriedOperation<Int>(queue: q, delay: { _ in 0.01 }, shouldRetry: CaptureFailure.isTransient, request: { done in
    attempts += 1
    if attempts < 3 { done(.failure(CaptureFailure.unavailable)); done(.failure(CaptureFailure.unavailable)) }
    else { done(.success(42)); done(.success(43)) }
}, completion: { result in completed += 1; if case .success(42) = result { recovered = true } })
retry.start(); retry.start()
check(pump({ recovered }) && attempts == 3 && completed == 1, "source becomes available; duplicate replies/start ignored")
var boundedAttempts = 0; var boundedEnd = false
let bounded = RetriedOperation<Int>(queue: q, maximumAttempts: 3, delay: { _ in 0.01 }, shouldRetry: CaptureFailure.isTransient, request: { done in boundedAttempts += 1; done(.failure(CaptureFailure.unavailable)) }, completion: { _ in boundedEnd = true })
bounded.start(); check(pump({ boundedEnd }) && boundedAttempts == 3, "missing source retries are bounded")
for code in [-3801, -3817, -3812] {
    var count = 0; var ended = false
    let denied = RetriedOperation<Int>(queue: q, delay: { _ in 0 }, shouldRetry: CaptureFailure.isTransient, request: { done in count += 1; done(.failure(NSError(domain: CaptureFailure.unavailable.domain, code: code))) }, completion: { _ in ended = true })
    denied.start(); check(pump({ ended }) && count == 1, "permission denial, user stop and invalid parameter never retried \(code)")
}
var reply: ((Result<Int,Error>) -> Void)?; var canceledCompletion = false
let canceled = RetriedOperation<Int>(queue: q, shouldRetry: CaptureFailure.isTransient, request: { reply = $0 }, completion: { _ in canceledCompletion = true })
canceled.start(); check(pump({ reply != nil }), "request pending before cancellation")
canceled.cancel(); RunLoop.current.run(until: Date().addingTimeInterval(0.02)); reply?(.success(1))
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
check(!canceledCompletion, "late availability reply cannot restart canceled capture")
print("RESULT", failures, "failures; no screen captured")
exit(failures == 0 ? 0 : 1)
