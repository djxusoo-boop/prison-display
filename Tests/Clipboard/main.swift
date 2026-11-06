import AppKit
// Clipboard relay with a private pasteboard: the user's clipboard is untouched.
setbuf(stdout, nil)
var failures = 0
func check(_ value: Bool, _ name: String) { print(value ? "PASS:" : "FAIL:", name); if !value { failures += 1 } }
func pump(_ seconds: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
let suite = "PrisonDisplayClipboardTests." + UUID().uuidString
let sync = ClipboardSync()
sync.pasteboard = NSPasteboard(name: NSPasteboard.Name(suite))
sync.defaults = UserDefaults(suiteName: suite)!
defer { sync.pasteboard.releaseGlobally(); sync.defaults.removePersistentDomain(forName: suite) }
var pro: [Data] = [], imac: [Data] = [], pc: [Data] = []
let proID = sync.register { pro.append($0) }
let imacID = sync.register { imac.append($0) }
_ = sync.register { pc.append($0) }
pump()
check(sync.enabled, "shared clipboard is on by default")
sync.pasteboard.clearContents(); sync.pasteboard.setString("Copiado en el Air", forType: .string)
sync.poll()
let expected = try! ClipboardPayload(text: "Copiado en el Air").serialized
check(pro == [expected] && imac == [expected] && pc == [expected], "a copy on this Mac reaches every connected computer")
sync.poll()
check(pro.count == 1, "an unchanged clipboard is not resent")
sync.receive(try! ClipboardPayload(text: "Desde el iMac").serialized, from: imacID); pump()
check(sync.pasteboard.string(forType: .string) == "Desde el iMac", "a copy from another computer is ready to paste here")
check(imac.count == 1 && pro.count == 2 && pc.count == 2, "it is relayed to the others, not echoed to its source")
sync.poll()
check(pro.count == 2, "pasting a remote copy does not bounce it back")
let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2])
sync.receive(try! ClipboardPayload(kind: .png, data: png).serialized, from: proID); pump()
check(sync.pasteboard.data(forType: .png) == png && imac.count == 2, "images are shared too")
sync.pasteboard.clearContents()
sync.pasteboard.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
sync.pasteboard.setString("contraseña-secreta", forType: .string)
sync.poll()
check(pro.count == 2 && imac.count == 2 && pc.count == 3, "passwords marked by password managers are never shared")
sync.enabled = false
sync.pasteboard.clearContents(); sync.pasteboard.setString("No compartir", forType: .string); sync.poll()
sync.receive(try! ClipboardPayload(text: "Ignorado").serialized, from: proID); pump()
check(imac.count == 2 && sync.pasteboard.string(forType: .string) == "No compartir", "turning it off stops sending and receiving")
check((try? ClipboardPayload(Data([1]))) == nil && (try? ClipboardPayload(Data([2, 1, 2, 3]))) == nil && (try? ClipboardPayload(Data([1] + [UInt8](repeating: 65, count: ClipboardPayload.maxText + 1)))) == nil, "empty, fake images and oversized text are rejected")
print("RESULT: \(failures) failures; private pasteboard only")
exit(failures == 0 ? 0 : 1)
