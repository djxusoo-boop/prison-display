#pragma once
#include <cstdint>
#include <functional>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace prison {
using Bytes = std::vector<std::uint8_t>;
struct Error : std::runtime_error { using std::runtime_error::runtime_error; };
constexpr std::uint16_t wire_revision = 11;
constexpr std::size_t max_packet = 4 * 1024 * 1024;
constexpr std::uint64_t allowed_input_flags = 0x00bf0000; // Caps, Shift, Ctrl, Alt, Cmd, NumPad, Fn.
enum class Kind : std::uint8_t {
    hello=1, video, ack, ping, pong, failure, pointer, cursor, cursor_offer,
    keyboard, cursor_mode, desktop_control, desktop_pointer, desktop_keyboard,
    presented, brightness_command, brightness_result, fullscreen_command, screen_edges
};
struct Packet { Kind kind; Bytes body; };
Bytes frame(const Packet& packet);
// Mutable protocol state is owned by one session queue, not shared across threads.
class Parser {
    Bytes buffer_;
    bool failed_ = false;
public:
    // Feed directly to a bounded downstream consumer: no unbounded list of frames.
    void feed(const Bytes& data, const std::function<void(Packet)>& receive);
    std::size_t buffered() const { return buffer_.size(); }
};
struct Hello { std::string role, version, name; };
Bytes encode(const Hello& message);
// An empty expected_version accepts any version (the PC link checks only the revision).
Hello decode_hello(const Bytes&, const std::string& expected_role, const std::string& expected_version);
struct Pointer {
    enum class Action : std::uint8_t { move, left_down, left_up, right_down, right_up, scroll, move_by, middle_down, middle_up };
    Action action = Action::move;
    double x = 0.5, y = 0.5, delta = 0;
    std::uint8_t clicks = 1;
    double delta_x = 0;
    std::uint64_t flags = 0;
};
Bytes encode(const Pointer&);
Pointer decode_pointer(const Bytes&);
struct Keyboard {
    enum class Action : std::uint8_t { down, up, modifiers, release_all };
    Action action = Action::release_all;
    std::uint16_t code = 0;
    std::uint64_t flags = 0;
    bool repeated = false;
};
Bytes encode(const Keyboard&);
Keyboard decode_keyboard(const Bytes&);
struct DesktopControl {
    enum class Action : std::uint8_t { begin, end, heartbeat, accepted, rejected, begin_global, returned };
    Action action = Action::begin;
    std::uint64_t token = 0;
    std::uint32_t width = 0, height = 0;
};
Bytes encode(const DesktopControl&);
DesktopControl decode_desktop_control(const Bytes&);
struct VideoFrame { std::uint64_t sequence=0, timestamp=0; Bytes sps, pps, avcc; };
Bytes encode(const VideoFrame&);
VideoFrame decode_video(const Bytes&);
std::string normalized_key(const std::string&);
Bytes psk_secret(const std::string& key);
std::string base64(const Bytes&);
Bytes unbase64(const std::string&);
// Bounded single-value mailbox. An input barrier must be drained separately;
// this type is exclusively for cursor positions, never clicks or key events.
class LatestCursor {
    std::optional<Pointer> value_;
public:
    void offer(Pointer value);
    std::optional<Pointer> take();
    void clear() { value_.reset(); }
};
// Protocol-level releases only. The native backend alone owns OS injection.
class InputPolicy {
    bool mouse_ = true, keyboard_ = false;
    bool left_ = false, right_ = false, keys_ = false;
    Pointer position_;
public:
    std::vector<Packet> configure(bool mouse, bool keyboard);
    std::optional<Packet> accept(const Packet&);
    std::vector<Packet> disconnect();
};
}
