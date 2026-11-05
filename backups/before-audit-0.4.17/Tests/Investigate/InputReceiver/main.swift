import Foundation
let url = URL(string:try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8))!
let link = try ConnectionLink(url)
let engine = ReceiverEngine()
engine.onStatus = { print("STATUS", $0) }
engine.pointerDelayMS = Int(CommandLine.arguments[2])!
let lock = NSLock()
var started: UInt64 = 0
var sent: [Int:UInt64] = [:]
var rtts: [Double] = []
var index = 0, frames = 0
var ready = false
engine.onInteractiveReady = { engine.sendDesktopControl(DesktopControlMessage(action:.begin,token:123)) }
engine.onDesktopControl = { m in if m.action == .accepted { lock.lock(); if started == 0 { started = monotonicNS() }; ready = true; lock.unlock() } }
engine.onPixel = { _,done in lock.lock();frames += 1;lock.unlock();done(.accepted) }
engine.onCursor = { x,_,_,_ in
    let index = Int((x*100000).rounded()); lock.lock(); if let time = sent.removeValue(forKey:index) { rtts.append(Double(monotonicNS()-time)/1e6) }; lock.unlock()
}
let input = DispatchSource.makeTimerSource(queue:DispatchQueue(label:"PrisonFakePointer",qos:.userInteractive))
input.schedule(deadline:.now(),repeating:.microseconds(8333))
input.setEventHandler {
    lock.lock(); let active = ready
    if active { index += 1; sent[index] = monotonicNS() }
    let sample = index; lock.unlock()
    if active { engine.sendPointer(PointerMessage(action:.move,x:Double(sample)/100000,y:0.5)) }
}
try engine.connect(endpoint:link.hostEndpoint,key:link.key,previouslyApproved:true)
input.resume(); let deadline = Date().addingTimeInterval(40)
while Date() < deadline {
    RunLoop.current.run(until:Date().addingTimeInterval(0.01))
    lock.lock(); let origin = started; lock.unlock()
    if origin != 0 && monotonicNS()-origin > 15_000_000_000 { break }
}
input.cancel(); engine.stop()
RunLoop.current.run(until:Date().addingTimeInterval(0.2))
lock.lock(); let values = rtts.sorted(); let count = index, videoFrames = frames; lock.unlock()
func percentile(_ p:Double)->Double { values.isEmpty ? 0 : values[min(values.count-1,Int(Double(values.count)*p))] }
print("INPUT RTT delayMS=\(engine.pointerDelayMS) sent=\(count) echoed=\(values.count) medianMS=\(percentile(0.5)) p95MS=\(percentile(0.95)) maxMS=\(values.last ?? 0) videoFrames=\(videoFrames)")
exit(values.count >= 100 && videoFrames > 0 ? 0:1)
