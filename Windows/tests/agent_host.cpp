// Simulated PC for end-to-end tests on macOS. Prints every injected event.
#include "prison/server.hpp"
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <mutex>
#include <thread>
using namespace prison;
static std::atomic<bool> stop{false};
std::mutex copy_mutex; std::optional<std::string> pending_copy;
struct Printer : InputSink {
    void install_update(const Bytes& b, const std::string& v) override { std::printf("UPDATE %s %zu\n", v.c_str(), b.size()); std::fflush(stdout); }
    void set_clipboard(const std::string& t) override { std::printf("CLIPBOARD %s\n", t.c_str()); std::fflush(stdout); }
    std::optional<std::string> clipboard_changed() override { std::lock_guard<std::mutex> l(copy_mutex); auto c = pending_copy; pending_copy.reset(); return c; }
    void move(double x, double y) override { std::printf("EVENT move %.4f %.4f\n", x, y); std::fflush(stdout); }
    void button(Button b, bool down) override { std::printf("EVENT %s %s\n", b == Button::left ? "left" : b == Button::right ? "right" : "middle", down ? "down" : "up"); std::fflush(stdout); }
    void wheel(int v, int h) override { std::printf("EVENT wheel %d %d\n", v, h); std::fflush(stdout); }
    void key(ScanKey k, bool down) override { std::printf("EVENT key %02X%s %s\n", k.scan, k.extended ? "e" : "", down ? "down" : "up"); std::fflush(stdout); }
};
int main(int argc, char** argv) {
    if (argc < 3) { std::fprintf(stderr, "usage: prison_agent_host KEY PORT\n"); return 2; }
    std::signal(SIGTERM, [](int) { stop = true; });
    // "COPY text" on standard input simulates copying on the PC.
    std::thread([] { std::string line; while (std::getline(std::cin, line)) if (line.rfind("COPY ", 0) == 0) { std::lock_guard<std::mutex> l(copy_mutex); pending_copy = line.substr(5); } }).detach();
    Printer sink; InputAgent agent(sink, "Torre simulada", "0.2.0", 2560, 1440);
    AgentServer server(agent, argv[1], static_cast<std::uint16_t>(std::atoi(argv[2])));
    // Optional: accept|reject PAIRPORT ANNOUNCEPORT for pairing tests.
    const std::string decision = argc > 3 ? argv[3] : "reject";
    server.pairing_port = static_cast<std::uint16_t>(argc > 4 ? std::atoi(argv[4]) : std::atoi(argv[2]) + 1);
    server.announce_port = static_cast<std::uint16_t>(argc > 5 ? std::atoi(argv[5]) : 0);
    server.announce = server.announce_port != 0;
    server.announce_address = 0x7F000001u; // Loopback: macOS does not deliver its own broadcasts.
    server.confirm_pairing = [decision](const std::string& mac, const std::string& code) {
        std::printf("PAIR %s %s\n", mac.c_str(), code.c_str()); std::fflush(stdout); return decision == "accept";
    };
    return server.run(stop, [](const std::string& s) { std::printf("STATUS %s\n", s.c_str()); std::fflush(stdout); }) ? 0 : 1;
}
