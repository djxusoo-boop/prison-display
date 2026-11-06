#pragma once
#include "prison/protocol.hpp"
#include <cstdint>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace prison {
// A key as Windows SendInput expects it: set-1 scan code plus extended flag.
struct ScanKey { std::uint16_t scan = 0; bool extended = false; };
// Mac virtual key code (physical position, ISO Spanish keyboards included) to
// Windows scan code. Windows then applies its own layout, so characters match
// when both computers use the same layout. Command maps to Ctrl (⌘C → Ctrl+C)
// and the left Option to AltGr (⌥2 → @ on Spanish layouts).
std::optional<ScanKey> windows_key(std::uint16_t mac_code);

// Operating-system side effects. The Win32 backend posts real input; tests
// record calls. Coordinates are normalized to the whole virtual desktop.
struct InputSink {
    enum class Button { left, right, middle };
    virtual ~InputSink() = default;
    virtual void move(double x, double y) = 0;
    virtual void button(Button button, bool down) = 0;
    virtual void wheel(int vertical, int horizontal) = 0;
    virtual void key(ScanKey key, bool down) = 0;
    virtual bool available() { return true; }
    // Shared clipboard (UTF-8 text). clipboard_changed returns text copied on
    // this PC since the last call, excluding text set by set_clipboard.
    virtual void set_clipboard(const std::string&) {}
    virtual std::optional<std::string> clipboard_changed() { return std::nullopt; }
    // A verified newer build of this app (Windows: replace the .exe and restart).
    virtual void install_update(const Bytes&, const std::string& /*version*/) {}
};
// -1, 0 or 1 comparing "1.2.3" versions numerically.
int compare_versions(const std::string& a, const std::string& b);
constexpr std::size_t max_clipboard_text = 1000000;
// Wire form: 1 = UTF-8 text (images from the Mac are ignored on the PC).
Bytes encode_clipboard_text(const std::string& text);

// One controlling Mac at a time. The Mac requests a short lease (begin),
// keeps it alive with heartbeats and ends it when the mouse comes back. Input
// outside a valid lease is ignored; every held button/key is released when
// the lease ends, expires or the connection drops.
class InputAgent {
public:
    static constexpr std::uint64_t lease_ms = 3000;
    InputAgent(InputSink& sink, std::string name, std::string version, std::uint32_t width, std::uint32_t height);
    std::vector<Packet> receive(const Packet& packet, std::uint64_t now_ms);
    std::vector<Packet> tick(std::uint64_t now_ms);
    void disconnect();
    void set_screen(std::uint32_t width, std::uint32_t height) { width_ = width; height_ = height; }
    void set_enabled(bool mouse, bool keyboard);
    bool greeted() const { return greeted_; }
    bool controlling() const { return token_ != 0; }
    const std::string& peer_name() const { return peer_; }
    const std::string& name() const { return name_; }
    const std::string& version() const { return version_; }
private:
    void end_lease();
    void keyboard(const Keyboard& message);
    void press(std::uint16_t code, bool down);
    InputSink& sink_;
    std::string name_, version_, peer_;
    std::uint32_t width_, height_;
    bool greeted_ = false, mouse_ = true, keyboard_ = true;
    std::uint64_t token_ = 0, expires_ = 0;
    bool left_ = false, right_ = false, middle_ = false;
    std::string update_version_, update_sha_;
    std::size_t update_size_ = 0; std::uint32_t update_next_ = 0; Bytes update_;
    bool updating_ = false;
    bool update_only_ = false; // Different protocol revision: accept only an update.
    std::set<std::uint16_t> held_;
};
}
