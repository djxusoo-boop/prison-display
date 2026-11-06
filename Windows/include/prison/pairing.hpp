#pragma once
#include "prison/protocol.hpp"
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace prison {
constexpr std::uint16_t pc_pairing_port = 37942;
constexpr std::uint16_t pc_announce_port = 37930;
// "PRISON-PC/1|name|version|input port|pairing port", broadcast on the LAN.
std::string pc_announcement(const std::string& name, const std::string& version, std::uint16_t input_port, std::uint16_t pairing_port);

// First connection without typing the key. Same construction as Mac pairing:
// P-256 key agreement, HKDF-SHA256 over a transcript of both public keys, a
// 6-digit code shown on both computers, and the PC key sent with AES-256-GCM
// only after both people confirm the code.
class PairingSession {
public:
    // confirm(mac name, code) asks the person at the PC; true = accepted.
    using Confirm = std::function<bool(const std::string&, const std::string&)>;
    PairingSession(std::string name, std::string version, std::string key, std::uint16_t input_port, Confirm confirm);
    ~PairingSession();
    std::vector<Packet> receive(const Packet& packet);
    // After the hello reply has been sent: ask the person (blocking) and answer.
    bool needs_decision() const { return awaiting_decision_; }
    std::vector<Packet> decide();
    bool finished() const { return finished_; }
    const std::string& code() const { return code_; }
private:
    std::vector<Packet> send_credentials();
    struct Keys;
    std::unique_ptr<Keys> keys_;
    std::string name_, version_, key_, code_, mac_;
    std::uint16_t input_port_;
    Confirm confirm_;
    bool local_ok_ = false, remote_ok_ = false, finished_ = false, awaiting_decision_ = false;
};
// Exposed for tests (Mac side is implemented in Swift with CryptoKit).
struct PairingMath {
    static Bytes derive(const Bytes& shared_secret, const Bytes& transcript);
    static std::string code(const Bytes& key);
    static Bytes seal(const Bytes& key, const Bytes& plaintext, const Bytes& aad);
    static Bytes open(const Bytes& key, const Bytes& sealed, const Bytes& aad);
};
}
