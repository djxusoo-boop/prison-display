#pragma once
#include "prison/agent.hpp"
#include <atomic>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>

namespace prison {
constexpr std::uint16_t pc_input_port = 37941;
// Encrypted listener for the controlling Mac: TLS 1.2 PSK with the same
// derivation as the Mac app (the key is shown on the PC and typed on the Mac
// once). One controller at a time; a new connection replaces a stale one.
class AgentServer {
public:
    using Status = std::function<void(const std::string&)>;
    AgentServer(InputAgent& agent, std::string key, std::uint16_t port = pc_input_port);
    // Blocks until stop becomes true. Returns false if the port cannot be opened.
    bool run(const std::atomic<bool>& stop, const Status& status);
    // Thread-safe access to the agent from the interface thread.
    template<class F> void with_agent(F&& f) { std::lock_guard<std::mutex> lock(mutex_); f(agent_); }
    std::uint16_t port() const { return port_; }
    // Pairing without typing the key: asks the person at the PC (blocking).
    std::function<bool(const std::string& mac, const std::string& code)> confirm_pairing;
    std::uint16_t pairing_port = 37942, announce_port = 37930;
    bool announce = true;
    std::uint32_t announce_address = 0xFFFFFFFFu; // Broadcast; tests use 127.0.0.1.
private:
    InputAgent& agent_;
    std::string key_;
    std::uint16_t port_;
    std::mutex mutex_;
};
// 32 random hexadecimal characters, the same format as the Mac pairing key.
std::string new_pc_key();
std::string grouped_key(const std::string& key);
}
