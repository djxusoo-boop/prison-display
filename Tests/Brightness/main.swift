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
// Targets: every screen, one Mac, one screen; queries change nothing.
do {
    let mac = UUID(), other = UUID()
    let all = try BrightnessCommand(percent: 40)
    check(all.applies(node: mac, panel: "a") && all.applies(node: other, panel: "b"), "no target reaches every screen")
    let one = try BrightnessCommand(data: try BrightnessCommand(percent: 40, target: mac.uuidString).data)
    check(one.target == mac.uuidString && one.applies(node: mac, panel: "a") && one.applies(node: mac, panel: "b") && !one.applies(node: other, panel: "a"), "a Mac target reaches only that Mac")
    let screen = try BrightnessCommand(data: try BrightnessCommand(percent: 40, target: mac.uuidString + "/610-a064-0").data)
    check(screen.applies(node: mac, panel: "610-a064-0") && !screen.applies(node: mac, panel: "25ce-27-0") && !screen.applies(node: other, panel: "610-a064-0"), "a screen target reaches only that screen")
    let query = try BrightnessCommand(data: BrightnessCommand.query().data)
    check(query.isQuery && !query.applies(node: mac, panel: "a"), "a query changes nothing")
    let legacy = try BrightnessCommand(data: Data("{\"id\":\"\(UUID())\",\"percent\":30}".utf8))
    check(legacy.target == nil && !legacy.isQuery && legacy.applies(node: mac, panel: "a"), "commands from older versions still apply to all")
    for bad in ["", "a b", "x\n", String(repeating: "a", count: 121)] { check((try? BrightnessCommand(percent: 40, target: bad)) == nil, "reject unsafe target") }
    let long = String(repeating: "Ñ", count: 80)
    let panels = (0..<6).map { BrightnessPanel(id: String(repeating: "f", count: 60) + "/\($0)", name: long, percent: 100, software: $0 % 2 == 0) }
    let result = BrightnessResult(id: UUID(), node: mac, name: long, percent: 100, panels: panels)
    check(result.panels?.count == BrightnessResult.maxPanels && result.data.count <= 1024, "largest report fits the limit (\(result.data.count) bytes)")
    let decoded = try BrightnessResult(data: result.data)
    check(decoded.panels == result.panels && decoded.panels!.allSatisfy { $0.id.count <= 40 && !$0.id.contains("/") && $0.name.count <= 40 }, "screens round trip and are bounded")
    let old = try BrightnessResult(data: BrightnessResult(id: UUID(), node: mac, name: "Mac", percent: 50).data)
    check(old.panels == nil, "reports from older versions still decode")
    let badPanel = Data("{\"id\":\"\(UUID())\",\"node\":\"\(mac)\",\"name\":\"M\",\"panels\":[{\"id\":\"a\",\"name\":\"b\",\"percent\":140,\"software\":true}]}".utf8)
    check((try? BrightnessResult(data: badPanel)) == nil, "decoded screen cannot bypass range check")
}
print("RESULT \(checks) checks \(failures) failures")
exit(failures == 0 ? 0 : 1)
