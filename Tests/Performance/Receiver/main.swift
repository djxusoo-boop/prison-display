import Foundation
import Network
let url = try String(contentsOfFile: CommandLine.arguments[1]).trimmingCharacters(in: .whitespacesAndNewlines)
let link = try ConnectionLink(URL(string: url)!)
let decoder = H264Decoder()
let cursor = CursorChannel()
let cursorLock = NSLock()
var cursorTimes: [UInt64] = []
var cursorDedicated = false
func recordCursor(_ data: Data, dedicated: Bool) {
    cursorLock.lock(); defer { cursorLock.unlock() }
    if dedicated { if !cursorDedicated { cursorTimes.removeAll() }; cursorDedicated = true } else if cursorDedicated { return }
    cursorTimes.append(monotonicNS())
}
cursor.onReady = { print("CURSOR dedicated TLS ready") }
cursor.onUnavailable = { print("CURSOR unavailable",$0) }
// Diagnostic only: compare a lightly active return path with one-way movement.
var probe: Timer?
if CommandLine.arguments.contains("probe") {
    probe = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
        if cursor.isReady { cursor.sendInput(.ping, Data()) }
    }
}
let resolver = VideoRouteResolver()
var selected: NWEndpoint?
let routerOnly = CommandLine.arguments.contains("router") || CommandLine.arguments.contains("host")
resolver.resolve(routerOnly ? link.hostEndpoint : link.endpoint, queue: .main) { selected = $0 }
while selected == nil { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
if !routerOnly, !prefersSharedLAN(selected!) { selected = link.hostEndpoint }
let parameters = try networkParameters(key: link.key)
if routerOnly { parameters.includePeerToPeer = false }
if CommandLine.arguments.contains("host"), let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
configureStreamRoute(parameters, endpoint: selected!)
let peer = Peer(NWConnection(to: selected!, using: parameters), queue: .main)
var finished = false
var frames = 0
var decodeMS: [Double] = []
var pixels = 0
var begun: UInt64?
decoder.onPixel = { _ in pixels += 1 }
peer.onReady = { print("ROUTE", peer.connection.currentPath?.remoteEndpoint as Any, peer.connection.currentPath?.availableInterfaces.map { $0.name } as Any); peer.send(.hello, Wire.hello(role: "receiver")) }
peer.onPacket = { kind, data in
    if kind == .cursorOffer {
        do { try cursor.startClient(offer: CursorOffer(data), video: peer.connection) { recordCursor($0, dedicated: true) } }
        catch { print("CURSOR ERROR",error) }
        return
    }
    if kind == .cursor { recordCursor(data,dedicated: false); return }
    guard kind == .video else { return }
    do {
        let frame = try VideoFrame(data)
        let start = monotonicNS()
        if begun == nil { begun = start }
        try decoder.decode(frame)
        let decode = monotonicNS() - start
        decodeMS.append(Double(decode) / 1e6)
        frames += 1
        var ack = Data(); ack.u64(frame.sequence); ack.u64(frame.timestamp)
        if AppVersion.current != "0.2.5" { ack.u64(decode) }
        peer.send(.ack, ack)
    } catch { print("ERROR", error); finished = true }
}
peer.onEnd = { print("END", $0); finished = true }
peer.start()
let deadline = Date().addingTimeInterval(60)
while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
let elapsed = begun.map { Double(monotonicNS() - $0) / 1e9 } ?? 1
decodeMS.sort()
print("RESULT version=\(AppVersion.current) frames=\(frames) decoded=\(pixels) fps=\(Double(frames) / elapsed) hw=\(decoder.hardware) decodeMedianMS=\(decodeMS.isEmpty ? 0 : decodeMS[decodeMS.count/2]) decodeP95MS=\(decodeMS.isEmpty ? 0 : decodeMS[min(decodeMS.count-1,Int(Double(decodeMS.count)*0.95))])")
probe?.invalidate(); cursor.stop()
cursorLock.lock()
let times = cursorTimes; let dedicated = cursorDedicated
cursorLock.unlock()
let gaps = zip(times.dropFirst(),times).map { Double($0.0-$0.1)/1e6 }.sorted()
print("CURSOR RESULT dedicated=\(dedicated) samples=\(times.count) medianGapMS=\(gaps.isEmpty ? 0 : gaps[gaps.count/2]) p95GapMS=\(gaps.isEmpty ? 0 : gaps[min(gaps.count-1,Int(Double(gaps.count)*0.95))]) maxGapMS=\(gaps.last ?? 0)")

peer.end(); decoder.stop()
exit(frames > 0 && frames == pixels ? 0 : 1)
