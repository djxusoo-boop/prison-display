#include "prison/agent.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <openssl/evp.h>
#include <sstream>

namespace prison {
namespace {
struct Entry { std::uint8_t mac; std::uint16_t scan; bool extended; };
// Physical positions. Mac ISO: 10 is the key left of 1 (º on Spanish), 50 the
// key right of the left Shift (<>).
constexpr Entry keys[] = {
    {0,0x1E,false},{1,0x1F,false},{2,0x20,false},{3,0x21,false},{4,0x23,false},{5,0x22,false},
    {6,0x2C,false},{7,0x2D,false},{8,0x2E,false},{9,0x2F,false},{10,0x29,false},{11,0x30,false},
    {12,0x10,false},{13,0x11,false},{14,0x12,false},{15,0x13,false},{16,0x15,false},{17,0x14,false},
    {18,0x02,false},{19,0x03,false},{20,0x04,false},{21,0x05,false},{22,0x07,false},{23,0x06,false},
    {24,0x0D,false},{25,0x0A,false},{26,0x08,false},{27,0x0C,false},{28,0x09,false},{29,0x0B,false},
    {30,0x1B,false},{31,0x18,false},{32,0x16,false},{33,0x1A,false},{34,0x17,false},{35,0x19,false},
    {36,0x1C,false},{37,0x26,false},{38,0x24,false},{39,0x28,false},{40,0x25,false},{41,0x27,false},
    {42,0x2B,false},{43,0x33,false},{44,0x35,false},{45,0x31,false},{46,0x32,false},{47,0x34,false},
    {48,0x0F,false},{49,0x39,false},{50,0x56,false},{51,0x0E,false},{53,0x01,false},
    {54,0x1D,true},  // right Command → right Ctrl
    {55,0x1D,false}, // Command → Ctrl
    {56,0x2A,false},{57,0x3A,false},
    {58,0x38,true},  // left Option → AltGr (@, #, € on Spanish layouts)
    {59,0x1D,false},{60,0x36,false},
    {61,0x38,false}, // right Option → Alt (Alt+Tab, menus)
    {62,0x1D,true},
    {65,0x53,false},{67,0x37,false},{69,0x4E,false},{71,0x45,false},{75,0x35,true},{76,0x1C,true},
    {78,0x4A,false},{82,0x52,false},{83,0x4F,false},{84,0x50,false},{85,0x51,false},{86,0x4B,false},
    {87,0x4C,false},{88,0x4D,false},{89,0x47,false},{91,0x48,false},{92,0x49,false},
    {96,0x3F,false},{97,0x40,false},{98,0x41,false},{99,0x3D,false},{100,0x42,false},{101,0x43,false},
    {103,0x57,false},{105,0x37,true}, // F13 → Print Screen
    {109,0x44,false},{111,0x58,false},{114,0x52,true},{115,0x47,true},{116,0x49,true},{117,0x53,true},
    {118,0x3E,false},{119,0x4F,true},{120,0x3C,false},{121,0x51,true},{122,0x3B,false},
    {123,0x4B,true},{124,0x4D,true},{125,0x50,true},{126,0x48,true},
};
constexpr std::uint64_t shift_mask = 1ull << 17, control_mask = 1ull << 18, option_mask = 1ull << 19,
                        command_mask = 1ull << 20, caps_mask = 1ull << 16;
std::uint64_t modifier_mask(std::uint16_t code) {
    switch (code) {
    case 56: case 60: return shift_mask;
    case 59: case 62: return control_mask;
    case 58: case 61: return option_mask;
    case 55: case 54: return command_mask;
    case 57: return caps_mask;
    default: return 0;
    }
}
}

int compare_versions(const std::string& a, const std::string& b) {
    auto parts = [](const std::string& v) { std::vector<long> out; std::stringstream in(v); std::string item; while (std::getline(in, item, '.')) out.push_back(std::strtol(item.c_str(), nullptr, 10)); return out; };
    const auto x = parts(a), y = parts(b);
    for (std::size_t i = 0; i < std::max(x.size(), y.size()); ++i) {
        const long l = i < x.size() ? x[i] : 0, r = i < y.size() ? y[i] : 0;
        if (l != r) return l < r ? -1 : 1;
    }
    return 0;
}
namespace {
std::string sha256_hex(const Bytes& data) {
    unsigned char digest[32]; unsigned int length = 0;
    if (EVP_Digest(data.data(), data.size(), digest, &length, EVP_sha256(), nullptr) != 1 || length != 32) throw Error("Digest failed");
    static const char hex[] = "0123456789abcdef"; std::string out;
    for (auto b : digest) { out.push_back(hex[b >> 4]); out.push_back(hex[b & 15]); }
    return out;
}
}

Bytes encode_clipboard_text(const std::string& text) {
    if (text.empty() || text.size() > max_clipboard_text) throw Error("Invalid clipboard text");
    Bytes out{1}; out.insert(out.end(), text.begin(), text.end()); return out;
}

std::optional<ScanKey> windows_key(std::uint16_t mac_code) {
    for (const auto& entry : keys) if (entry.mac == mac_code) return ScanKey{entry.scan, entry.extended};
    return std::nullopt;
}

InputAgent::InputAgent(InputSink& sink, std::string name, std::string version, std::uint32_t width, std::uint32_t height)
    : sink_(sink), name_(std::move(name)), version_(std::move(version)), width_(width), height_(height) {}

void InputAgent::set_enabled(bool mouse, bool keyboard) {
    mouse_ = mouse; keyboard_ = keyboard;
    if (!mouse_) end_lease();
    if (!keyboard_) for (auto code : std::vector<std::uint16_t>(held_.begin(), held_.end())) press(code, false);
}

void InputAgent::press(std::uint16_t code, bool down) {
    const auto key = windows_key(code);
    if (!key) return;
    if (down) held_.insert(code); else if (!held_.erase(code)) return;
    sink_.key(*key, down);
}

void InputAgent::keyboard(const Keyboard& message) {
    using A = Keyboard::Action;
    if (message.action == A::release_all) {
        for (auto code : std::vector<std::uint16_t>(held_.begin(), held_.end())) press(code, false);
        return;
    }
    if (!keyboard_) return;
    if (message.action == A::modifiers) {
        const auto mask = modifier_mask(message.code);
        if (!mask) return;
        if (message.code == 57) { // Caps Lock toggles on every press.
            if (const auto key = windows_key(57)) { sink_.key(*key, true); sink_.key(*key, false); }
            return;
        }
        const bool down = (message.flags & mask) != 0 && !held_.count(message.code);
        if (down) press(message.code, true);
        else if (held_.count(message.code)) press(message.code, false);
        return;
    }
    const bool down = message.action == A::down;
    if (down && held_.count(message.code) && !message.repeated) return;
    if (down) { if (const auto key = windows_key(message.code)) { held_.insert(message.code); sink_.key(*key, true); } }
    else press(message.code, false);
}

void InputAgent::end_lease() {
    if (left_) sink_.button(InputSink::Button::left, false);
    if (right_) sink_.button(InputSink::Button::right, false);
    if (middle_) sink_.button(InputSink::Button::middle, false);
    left_ = right_ = middle_ = false;
    for (auto code : std::vector<std::uint16_t>(held_.begin(), held_.end())) press(code, false);
    token_ = 0; expires_ = 0;
}

void InputAgent::disconnect() { end_lease(); greeted_ = false; update_only_ = false; updating_ = false; update_.clear(); peer_.clear(); }

std::vector<Packet> InputAgent::receive(const Packet& packet, std::uint64_t now) {
    if (!greeted_) {
        if (packet.kind != Kind::hello) throw Error("Expected hello");
        // Another protocol revision can still update this app; nothing else.
        Bytes body = packet.body;
        if (body.size() >= 2) {
            update_only_ = ((body[0] << 8) | body[1]) != wire_revision;
            body[0] = static_cast<std::uint8_t>(wire_revision >> 8); body[1] = static_cast<std::uint8_t>(wire_revision & 255);
        }
        const auto hello = decode_hello(body, "pc-controller", "");
        greeted_ = true; peer_ = hello.name;
        return {{Kind::hello, encode(Hello{"pc", version_, name_})}};
    }
    if (update_only_ && packet.kind != Kind::update_offer && packet.kind != Kind::update_chunk && packet.kind != Kind::update_done
        && packet.kind != Kind::ping) return {};
    switch (packet.kind) {
    case Kind::ping: return {{Kind::pong, {}}};
    case Kind::pong: return {};
    case Kind::desktop_control: {
        const auto control = decode_desktop_control(packet.body);
        using A = DesktopControl::Action;
        auto reply = [&](A action) {
            DesktopControl c{action, control.token, 0, 0};
            if (action == A::accepted) { c.width = std::clamp<std::uint32_t>(width_, 4, 32768); c.height = std::clamp<std::uint32_t>(height_, 4, 32768); }
            return std::vector<Packet>{{Kind::desktop_control, encode(c)}};
        };
        if (control.action == A::end) { if (control.token == token_) end_lease(); return {}; }
        if (control.action == A::begin) {
            if (!mouse_ || !sink_.available()) return reply(A::rejected);
            end_lease(); token_ = control.token; expires_ = now + lease_ms; return reply(A::accepted);
        }
        if (control.action == A::heartbeat) {
            if (control.token != token_ || !token_) return reply(A::rejected);
            expires_ = now + lease_ms; return reply(A::accepted);
        }
        return reply(A::rejected); // begin_global and replies are not for a PC.
    }
    case Kind::desktop_pointer: case Kind::desktop_keyboard: {
        if (packet.body.size() < 8) throw Error("Missing lease token");
        std::uint64_t token = 0;
        for (int i = 0; i < 8; ++i) token = (token << 8) | packet.body[static_cast<std::size_t>(i)];
        const Bytes body(packet.body.begin() + 8, packet.body.end());
        if (packet.kind == Kind::desktop_keyboard) {
            const auto message = decode_keyboard(body);
            if (token && token == token_) keyboard(message);
            return {};
        }
        const auto p = decode_pointer(body);
        if (!token || token != token_ || !mouse_) return {};
        using P = Pointer::Action;
        using B = InputSink::Button;
        switch (p.action) {
        case P::move: sink_.move(p.x, p.y); break;
        case P::left_down: sink_.move(p.x, p.y); left_ = true; sink_.button(B::left, true); break;
        case P::left_up: sink_.move(p.x, p.y); if (left_) sink_.button(B::left, false); left_ = false; break;
        case P::right_down: sink_.move(p.x, p.y); right_ = true; sink_.button(B::right, true); break;
        case P::right_up: sink_.move(p.x, p.y); if (right_) sink_.button(B::right, false); right_ = false; break;
        case P::middle_down: sink_.move(p.x, p.y); middle_ = true; sink_.button(B::middle, true); break;
        case P::middle_up: sink_.move(p.x, p.y); if (middle_) sink_.button(B::middle, false); middle_ = false; break;
        case P::scroll: {
            // Mac pixel deltas; a mouse notch (~10 px) becomes one Windows notch (120).
            const int vertical = static_cast<int>(std::lround(std::clamp(p.delta * 12.0, -1200.0, 1200.0)));
            const int horizontal = static_cast<int>(std::lround(std::clamp(-p.delta_x * 12.0, -1200.0, 1200.0)));
            if (vertical || horizontal) sink_.wheel(vertical, horizontal);
            break;
        }
        case P::move_by: break; // Relative movement is only for Mac displays.
        }
        return {};
    }
    case Kind::clipboard: {
        if (packet.body.size() < 2 || packet.body.size() > max_clipboard_text + 1) throw Error("Invalid clipboard");
        if (packet.body[0] == 1) sink_.set_clipboard(std::string(packet.body.begin() + 1, packet.body.end()));
        else if (packet.body[0] != 2) throw Error("Invalid clipboard");
        return {};
    }
    case Kind::update_offer: {
        // "version|size|sha256" from the paired Mac; only a newer build.
        const std::string text(packet.body.begin(), packet.body.end());
        const auto a = text.find('|'), b = a == std::string::npos ? a : text.find('|', a + 1);
        if (packet.body.size() > 256 || b == std::string::npos) throw Error("Invalid update offer");
        update_version_ = text.substr(0, a); update_sha_ = text.substr(b + 1);
        update_size_ = static_cast<std::size_t>(std::strtoull(text.substr(a + 1, b - a - 1).c_str(), nullptr, 10));
        if (update_size_ == 0 || update_size_ > 64u * 1024 * 1024 || update_sha_.size() != 64 || compare_versions(update_version_, version_) <= 0) throw Error("Update not accepted");
        update_.clear(); update_.reserve(update_size_); update_next_ = 0; updating_ = true;
        return {};
    }
    case Kind::update_chunk: {
        if (!updating_ || packet.body.size() < 5) throw Error("Unexpected update data");
        std::uint32_t sequence = 0; for (int i = 0; i < 4; ++i) sequence = (sequence << 8) | packet.body[static_cast<std::size_t>(i)];
        if (sequence != update_next_ || update_.size() + packet.body.size() - 4 > update_size_) throw Error("Update out of order");
        update_.insert(update_.end(), packet.body.begin() + 4, packet.body.end()); ++update_next_;
        return {};
    }
    case Kind::update_done: {
        if (!updating_) throw Error("Unexpected update end");
        updating_ = false;
        if (update_.size() != update_size_ || sha256_hex(update_) != update_sha_) { update_.clear(); throw Error("Update damaged"); }
        end_lease();
        sink_.install_update(update_, update_version_);
        update_.clear();
        return {};
    }
    case Kind::update_request: return {};
    case Kind::pointer: case Kind::keyboard: return {}; // Never outside a lease.
    default: throw Error("Unexpected packet for the PC");
    }
}

std::vector<Packet> InputAgent::tick(std::uint64_t now) {
    std::vector<Packet> out;
    if (greeted_) {
        if (auto text = sink_.clipboard_changed(); text && !text->empty() && text->size() <= max_clipboard_text)
            out.push_back({Kind::clipboard, encode_clipboard_text(*text)});
    }
    if (!token_ || now < expires_) return out;
    const auto token = token_;
    end_lease();
    out.push_back({Kind::desktop_control, encode(DesktopControl{DesktopControl::Action::rejected, token, 0, 0})});
    return out;
}
}
