import Foundation
var failures = 0
func check(_ ok: Bool, _ name: String) { print(ok ? "PASS: \(name)" : "FAIL: \(name)"); if !ok { failures += 1 } }
var state = GraphicsLoadProtection()
check(!state.observe(95, now: 0), "one CPU burst never stops extension")
check(!state.observe(95, now: 4_000_000_000), "short overload stays below the sustained limit")
check(!state.observe(20, now: 4_500_000_000), "recovery cancels the overload streak")
check(!state.observe(95, now: 6_000_000_000), "another burst starts a new streak")
check(state.observe(95, now: 11_000_000_000), "five seconds of overload triggers protection")
check(!state.observe(95, now: 20_000_000_000), "protection fires once per monitoring session")
var invalid = GraphicsLoadProtection()
check(!invalid.observe(.nan, now: 0) && !invalid.observe(nil, now: 9_000_000_000), "missing or invalid metadata cannot trigger protection")
check(!invalid.observe(100, now: 10_000_000_000) && !invalid.observe(100, now: 1_000_000_000), "clock rollback restarts the streak")
var calls = 0
let monitor = GraphicsLoadMonitor(interval: 0.01, reader: { 100 }, makeProtection: { GraphicsLoadProtection(sustainedNS: 20_000_000) })
monitor.start { DispatchQueue.main.async { calls += 1 } }
let deadline = Date().addingTimeInterval(2)
while calls == 0 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
RunLoop.current.run(until: Date().addingTimeInterval(0.1))
check(calls == 1, "background monitor reports persistent load exactly once")
monitor.stop()
let stopped = GraphicsLoadMonitor(interval: 0.01, reader: { 100 }, makeProtection: { GraphicsLoadProtection(sustainedNS: 100_000_000) })
stopped.start { DispatchQueue.main.async { calls += 1 } }; stopped.stop()
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
check(calls == 1, "stopping monitoring cancels a pending report")
let real = GraphicsLoadMonitor.systemLoad()
print("METADATA colour service CPU percent", real as Any)
check(real != nil && real!.isFinite && real! >= 0, "bounded metadata reader works without signalling system processes")
print("RESULT", failures, "failures; no system colour service modified")
exit(failures == 0 ? 0 : 1)
