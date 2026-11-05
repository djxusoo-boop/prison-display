#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <algorithm>
#include <cstring>
#include <sstream>
#include "prison/discovery.hpp"

namespace prison {
struct Discovery::Impl {
    SOCKET socket = INVALID_SOCKET;
    sockaddr_in destination{};
    std::string name;
    std::string version;
    std::uint16_t port = 37930;
};

namespace {
constexpr char magic[] = "PRISON-DISPLAY/1";
bool parse(const char* data, std::size_t size, Peer& peer) {
    std::string text(data, data + size);
    if (text.rfind(magic, 0) != 0) return false;
    std::istringstream fields(text);
    std::string header, name, version;
    if (!std::getline(fields, header, '|') || !std::getline(fields, name, '|') || !std::getline(fields, version, '|')) return false;
    if (name.empty() || name.size() > 128 || version.empty() || version.size() > 32) return false;
    peer.name = std::move(name);
    peer.version = std::move(version);
    return true;
}
}

Discovery::Discovery() : impl_(new Impl) {}
Discovery::~Discovery() { stop(); delete impl_; }
bool Discovery::start(std::string name, std::string version, std::uint16_t port) {
    stop();
    WSADATA data{};
    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) return false;
    impl_->socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (impl_->socket == INVALID_SOCKET) { WSACleanup(); return false; }
    BOOL yes = TRUE;
    setsockopt(impl_->socket, SOL_SOCKET, SO_BROADCAST, reinterpret_cast<const char*>(&yes), sizeof(yes));
    u_long nonblocking = 1;
    ioctlsocket(impl_->socket, FIONBIO, &nonblocking);
    sockaddr_in local{};
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_ANY);
    local.sin_port = htons(port);
    if (bind(impl_->socket, reinterpret_cast<sockaddr*>(&local), sizeof(local)) == SOCKET_ERROR) { stop(); return false; }
    impl_->destination.sin_family = AF_INET;
    impl_->destination.sin_addr.s_addr = htonl(INADDR_BROADCAST);
    impl_->destination.sin_port = htons(port);
    impl_->name = std::move(name);
    impl_->version = std::move(version);
    impl_->port = port;
    return true;
}
void Discovery::stop() {
    if (!impl_ || impl_->socket == INVALID_SOCKET) return;
    closesocket(impl_->socket);
    impl_->socket = INVALID_SOCKET;
    WSACleanup();
}
void Discovery::announce() {
    if (!active()) return;
    const std::string message = std::string(magic) + "|" + impl_->name + "|" + impl_->version + "|" + std::to_string(impl_->port);
    sendto(impl_->socket, message.data(), static_cast<int>(message.size()), 0,
           reinterpret_cast<const sockaddr*>(&impl_->destination), sizeof(impl_->destination));
}
std::vector<Peer> Discovery::poll() {
    std::vector<Peer> peers;
    if (!active()) return peers;
    for (;;) {
        char buffer[512]{};
        sockaddr_in source{};
        int length = sizeof(source);
        const int received = recvfrom(impl_->socket, buffer, sizeof(buffer), 0,
                                      reinterpret_cast<sockaddr*>(&source), &length);
        if (received == SOCKET_ERROR) break;
        Peer peer;
        if (!parse(buffer, static_cast<std::size_t>(received), peer)) continue;
        char address[INET_ADDRSTRLEN]{};
        inet_ntop(AF_INET, &source.sin_addr, address, sizeof(address));
        peer.address = address;
        peer.port = ntohs(source.sin_port);
        if (peer.name == impl_->name && peer.address == "127.0.0.1") continue;
        if (std::none_of(peers.begin(), peers.end(), [&](const Peer& other) { return other.address == peer.address && other.port == peer.port; })) peers.push_back(std::move(peer));
    }
    return peers;
}
bool Discovery::active() const noexcept { return impl_ && impl_->socket != INVALID_SOCKET; }
}
#endif
