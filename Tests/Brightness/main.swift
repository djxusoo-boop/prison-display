import Foundation
var checks = 0, failures = 0
func check(_ value: Bool, _ title: String) { checks += 1; if !value { failures += 1; print("FAIL", title) } }
for percent in [5, 50, 100] {
    let command = try BrightnessCommand(percent: percent)
    let decoded = try BrightnessCommand(data: command.data)
    check(decoded.id == command.id && decoded.percent == percent, "brightness request round trip")
    var parser = PacketParser()
    let packets = try parser.feed(Wire.packet(.brightnessCommand, command.data))
    check(packets.count == 1 && packets[0].0 == .brightnessCommand, "brightness request packet")
}
for percent in [-1, 0, 4, 101, Int.max] { check((try? BrightnessCommand(percent: percent)) == nil, "reject unsafe brightness") }
let id = UUID(), node = UUID()
for level: Int? in [nil, 0, 5, 100] {
    let result = BrightnessResult(id: id, node: node, name: "Mac\n\u{0}Name", percent: level)
    let decoded = try BrightnessResult(data: result.data)
    check(decoded.id == id && decoded.node == node && decoded.percent == level && decoded.name == "MacName", "brightness confirmation validated")
}
for kind in [Wire.Kind.brightnessCommand, .brightnessResult] {
    var parser = PacketParser(); let payload = Wire.packet(kind, Data([1,2,3]))
    check(try parser.feed(payload.prefix(3)).isEmpty, "fragmented brightness header")
    check(try parser.feed(payload.dropFirst(3)).first?.0 == kind, "fragmented brightness result")
}
do {
    var parser = PacketParser()
    let packet = try parser.feed(Wire.packet(.fullscreenCommand))
    check(packet.count == 1 && packet[0].0 == .fullscreenCommand && packet[0].1.isEmpty, "remote fullscreen command packet")
    check((try? Wire.validateFullscreenCommand(Data())) != nil, "accept empty fullscreen command")
    check((try? Wire.validateFullscreenCommand(Data([1]))) == nil, "reject malformed fullscreen command")
}
check((try? BrightnessCommand(data: Data(repeating: 0, count: 1025))) == nil, "reject oversized request")
check((try? BrightnessResult(data: Data(repeating: 0, count: 1025))) == nil, "reject oversized result")
check((try? BrightnessCommand(data: Data("{\"id\":\"\(id)\",\"percent\":0}".utf8))) == nil, "decoded request cannot bypass range check")
check((try? BrightnessResult(data: BrightnessResult(id: id, node: node, name: "Mac", percent: 101).data)) == nil, "decoded confirmation cannot bypass range check")
print("RESULT \(checks) checks \(failures) failures")
exit(failures == 0 ? 0 : 1)
