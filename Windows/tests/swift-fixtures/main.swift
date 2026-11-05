import Foundation
import CryptoKit
import CoreGraphics
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func save(_ name: String, _ bytes: Data) throws { try bytes.write(to: directory.appendingPathComponent(name)) }
try save("hello.bin", Wire.hello(role: "sender", name: "Mac de prueba ñ"))
try save("mouse.bin", PointerMessage(action: .leftDown, x: 0.25, y: 0.75, delta: -12, clicks: 2, deltaX: 7, flags: inputFlags).serialize())
try save("keyboard.bin", KeyboardMessage(action: .down, keyCode: 8, flags: CGEventFlags.maskCommand.rawValue, repeated: true).serialize())
try save("desktop.bin", DesktopControlMessage(action: .accepted, token: 123456789, width: 1920, height: 1080).serialize())
try save("packet.bin", Wire.packet(.hello, Wire.hello(role: "sender", name: "Mac de prueba ñ")))
let key = "0123456789ABCDEF0123456789ABCDEF"
try save("psk.bin", Data(SHA256.hash(data: Data(("AireDisplay:" + key).utf8))))
print("Swift fixtures generated from the current product serializers; no screen or input accessed")
