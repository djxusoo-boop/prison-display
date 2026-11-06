import AppKit
// Two update sessions wired back to back (as over a connection). Installation
// is replaced; real signature checks run separately with the signed apps.
setbuf(stdout, nil)
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS:" : "FAIL:", name); if !value { failures += 1 } }
func pump(_ condition: () -> Bool, timeout: Double = 8) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    return condition()
}
let queue = DispatchQueue(label: "update-test")
var newer: UpdateSession!, older: UpdateSession!
var olderStatus: [String] = [], newerStatus: [String] = [], failuresSent: [String] = []
var installed: (Data, String)?, relaunched: URL?
let payload = Data((0..<3_200_000).map { UInt8(($0 * 7) % 256) })
let file = FileManager.default.temporaryDirectory.appendingPathComponent("update-test-\(getpid()).zip")
try payload.write(to: file)
newer = UpdateSession(send: { kind, data in queue.async { if kind == .failure { failuresSent.append(String(data: data, encoding: .utf8) ?? "") } else { try? older.handle(kind, data) } } }, status: { s in DispatchQueue.main.async { newerStatus.append(s) } })
older = UpdateSession(send: { kind, data in queue.async { try? newer.handle(kind, data) } }, status: { s in DispatchQueue.main.async { olderStatus.append(s) } })
newer.package = { identifier in guard identifier == "local.airedisplay.Receiver" else { throw AireError("sin paquete") }; return file }
older.identifier = "local.airedisplay.Receiver"
older.install = { zip, version in installed = (try Data(contentsOf: zip), version); return URL(fileURLWithPath: "/Applications/PRISON DISPLAY iMac.app") }
older.relaunch = { relaunched = $0 }
let future = "9.0.0"
// The older app sees a newer peer: it asks; the newer one sends.
check(older.mismatch(VersionMismatch(remote: future)), "an older app keeps the connection to update itself")
// The test's "newer" side is this same build; pretend the request came from an older version.
queue.async { try? newer.handle(.updateRequest, try! UpdateRequest(identifier: "local.airedisplay.Receiver", version: "0.0.1").data) }
// Its offer carries AppVersion.current, which the older session must find newer than itself.
check(pump({ newerStatus.contains { $0.contains("enviada") } }), "the newer Mac packages and sends the update in 1 MB pieces")
// AppVersion.current is not newer than itself, so the older side refuses it: correct.
check(installed == nil, "an offer that is not newer than this app is refused")
// Now as a genuinely older receiver.
let old2 = UpdateSession(send: { _, _ in }, status: { _ in }); old2.identifier = "x"
var got: (Data, String)?
old2.install = { zip, version in got = (try Data(contentsOf: zip), version); return file }
old2.relaunch = { _ in }
let offer = try UpdateOffer(version: "99.0.0", size: payload.count, sha256: (try AppUpdater.sha256(file)).hex)
try old2.handle(.updateOffer, offer.data)
var seq: UInt32 = 0, offset = 0
while offset < payload.count { let end = min(payload.count, offset + UpdateOffer.chunkSize); try old2.handle(.updateChunk, Wire.updateChunk(sequence: seq, payload.subdata(in: offset..<end))); seq += 1; offset = end }
try old2.handle(.updateDone, Data())
check(pump({ got != nil }) && got!.0 == payload && got!.1 == "99.0.0", "a complete, verified download is installed")
let old3 = UpdateSession(send: { _, _ in }, status: { _ in })
var installedBad = false; old3.install = { _, _ in installedBad = true; return file }
try old3.handle(.updateOffer, try UpdateOffer(version: "99.0.0", size: payload.count, sha256: String(repeating: "0", count: 64)).data)
try old3.handle(.updateChunk, Wire.updateChunk(sequence: 0, payload))
var damaged = false; do { try old3.handle(.updateDone, Data()) } catch { damaged = true }
check(damaged && !installedBad, "a damaged download is refused")
let old4 = UpdateSession(send: { _, _ in }, status: { _ in })
var unsolicited = false; do { try old4.handle(.updateChunk, Wire.updateChunk(sequence: 0, Data([1]))) } catch { unsolicited = true }
check(unsolicited, "data without an offer is refused")
var older5 = false; do { try UpdateSession(send: { _, _ in }, status: { _ in }).handle(.updateOffer, try UpdateOffer(version: "0.0.1", size: 10, sha256: String(repeating: "a", count: 64)).data) } catch { older5 = true }
check(older5, "an older version is never offered for installation")
check(AppVersion.compare("0.4.10", "0.4.9") == 1 && AppVersion.compare("0.4.25", "0.4.25") == 0 && AppVersion.compare("1.0", "1.0.1") == -1, "versions compare numerically")
check((try? UpdateRequest(identifier: "bad id|x", version: "1.0")) == nil && (try? UpdateOffer(version: "1.0", size: 0, sha256: "")) == nil, "malformed update messages are rejected")
try? FileManager.default.removeItem(at: file)
print("RESULT: \(failures) failures; nothing installed")
exit(failures == 0 ? 0 : 1)
