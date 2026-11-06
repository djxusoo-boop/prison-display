#include "prison/agent.hpp"
#include <cstdio>
#include <string>
#include <vector>
using namespace prison;
static int failures = 0;
static void check(bool ok, const char* name) { std::printf("%s: %s\n", ok ? "PASS" : "FAIL", name); if (!ok) ++failures; }
struct Recorder : InputSink {
    std::vector<std::string> events;
    void move(double x, double y) override { char b[64]; std::snprintf(b, sizeof b, "move %.3f %.3f", x, y); events.push_back(b); }
    void button(Button b, bool down) override { events.push_back(std::string(b == Button::left ? "left" : b == Button::right ? "right" : "middle") + (down ? " down" : " up")); }
    void wheel(int v, int h) override { events.push_back("wheel " + std::to_string(v) + " " + std::to_string(h)); }
    void key(ScanKey k, bool down) override { char b[64]; std::snprintf(b, sizeof b, "key %02X%s %s", k.scan, k.extended ? "e" : "", down ? "down" : "up"); events.push_back(b); }
};
static Packet tagged(Kind kind, std::uint64_t token, const Bytes& body) {
    Bytes data; for (int i = 7; i >= 0; --i) data.push_back(static_cast<std::uint8_t>(token >> (i * 8)));
    data.insert(data.end(), body.begin(), body.end()); return {kind, data};
}
static DesktopControl control(const std::vector<Packet>& out) { return out.empty() ? DesktopControl{} : decode_desktop_control(out.back().body); }
int main() {
    check(windows_key(0)->scan == 0x1E && windows_key(55)->scan == 0x1D && !windows_key(55)->extended, "A and Command→Ctrl");
    check(windows_key(58)->scan == 0x38 && windows_key(58)->extended, "left Option → AltGr for @ on Spanish layout");
    check(windows_key(10)->scan == 0x29 && windows_key(50)->scan == 0x56, "ISO keys (º and <>) keep their position");
    check(windows_key(123)->extended && windows_key(117)->scan == 0x53 && windows_key(117)->extended, "arrows and forward delete are extended keys");
    check(!windows_key(63), "Fn is not sent");
    Recorder sink; InputAgent agent(sink, "Torre", "0.2.0", 1920, 1080);
    bool rejected = false; try { agent.receive({Kind::desktop_control, encode(DesktopControl{DesktopControl::Action::begin, 1, 0, 0})}, 0); } catch (const Error&) { rejected = true; }
    check(rejected, "nothing accepted before the hello");
    InputAgent wrong(sink, "Torre", "0.2.0", 1920, 1080); rejected = false;
    try { wrong.receive({Kind::hello, encode(Hello{"sender", "0.4.24", "Air"})}, 0); } catch (const Error&) { rejected = true; }
    check(rejected, "a screen-sharing Mac cannot pose as the controller");
    auto out = agent.receive({Kind::hello, encode(Hello{"pc-controller", "0.4.24", "MacBook Air"})}, 0);
    check(out.size() == 1 && decode_hello(out[0].body, "pc", "0.2.0").name == "Torre" && agent.peer_name() == "MacBook Air", "hello answered with the PC role");
    Pointer click; click.action = Pointer::Action::left_down; click.x = 0.5; click.y = 0.25;
    agent.receive(tagged(Kind::desktop_pointer, 7, encode(click)), 0);
    check(sink.events.empty(), "input without a lease is ignored");
    out = agent.receive({Kind::desktop_control, encode(DesktopControl{DesktopControl::Action::begin, 7, 0, 0})}, 1000);
    check(control(out).action == DesktopControl::Action::accepted && control(out).width == 1920 && control(out).height == 1080, "lease accepted with the desktop size");
    agent.receive(tagged(Kind::desktop_pointer, 7, encode(click)), 1000);
    check(sink.events.size() == 2 && sink.events[0] == "move 0.500 0.250" && sink.events[1] == "left down", "click lands at the normalized position");
    Keyboard cmd{Keyboard::Action::modifiers, 55, 1ull << 20, false}; Keyboard c{Keyboard::Action::down, 8, 1ull << 20, false};
    agent.receive(tagged(Kind::desktop_keyboard, 7, encode(cmd)), 1000);
    agent.receive(tagged(Kind::desktop_keyboard, 7, encode(c)), 1000);
    check(sink.events[2] == "key 1D down" && sink.events[3] == "key 2E down", "⌘C becomes Ctrl+C");
    Keyboard caps{Keyboard::Action::modifiers, 57, 1ull << 16, false};
    agent.receive(tagged(Kind::desktop_keyboard, 7, encode(caps)), 1000);
    check(sink.events[4] == "key 3A down" && sink.events[5] == "key 3A up", "Caps Lock toggles with one press");
    Pointer wheel; wheel.action = Pointer::Action::scroll; wheel.delta = 10;
    agent.receive(tagged(Kind::desktop_pointer, 7, encode(wheel)), 1000);
    check(sink.events.back() == "wheel 120 0", "one mouse notch is one Windows notch");
    agent.receive(tagged(Kind::desktop_pointer, 8, encode(click)), 1000);
    check(sink.events.back() == "wheel 120 0", "stale token ignored");
    out = agent.receive({Kind::desktop_control, encode(DesktopControl{DesktopControl::Action::heartbeat, 7, 0, 0})}, 3500);
    check(control(out).action == DesktopControl::Action::accepted && agent.tick(5000).empty(), "heartbeat extends the lease");
    sink.events.clear();
    out = agent.tick(7000);
    check(control(out).action == DesktopControl::Action::rejected && !agent.controlling(), "missing heartbeat expires the lease");
    bool released_click = false, released_c = false, released_ctrl = false;
    for (auto& e : sink.events) { released_click |= e == "left up"; released_c |= e == "key 2E up"; released_ctrl |= e == "key 1D up"; }
    check(released_click && released_c && released_ctrl, "expiry releases the held click and keys");
    out = agent.receive({Kind::desktop_control, encode(DesktopControl{DesktopControl::Action::begin_global, 9, 0, 0})}, 8000);
    check(control(out).action == DesktopControl::Action::rejected, "continuous Mac-only mode is refused by the PC");
    agent.set_enabled(false, true);
    out = agent.receive({Kind::desktop_control, encode(DesktopControl{DesktopControl::Action::begin, 10, 0, 0})}, 8000);
    check(control(out).action == DesktopControl::Action::rejected, "lease refused while the mouse is disabled on the PC");
    agent.set_enabled(true, true);
    agent.receive({Kind::desktop_control, encode(DesktopControl{DesktopControl::Action::begin, 11, 0, 0})}, 9000);
    agent.receive(tagged(Kind::desktop_keyboard, 11, encode(Keyboard{Keyboard::Action::down, 0, 0, false})), 9000);
    sink.events.clear(); agent.disconnect();
    check(sink.events.size() == 1 && sink.events[0] == "key 1E up" && !agent.greeted(), "disconnect releases keys and requires a new hello");
    std::printf("RESULT: %d failures; recorded input only\n", failures);
    return failures ? 1 : 0;
}
