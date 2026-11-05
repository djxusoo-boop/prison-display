#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace prison {
struct Peer {
    std::string name;
    std::string address;
    std::uint16_t port = 0;
    std::string version;
};

class Discovery {
public:
    Discovery();
    ~Discovery();
    Discovery(const Discovery&) = delete;
    Discovery& operator=(const Discovery&) = delete;
    bool start(std::string name, std::string version, std::uint16_t port = 37930);
    void stop();
    void announce();
    std::vector<Peer> poll();
    bool active() const noexcept;
private:
    struct Impl;
    Impl* impl_ = nullptr;
};
}
