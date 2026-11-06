// Simulated PC for end-to-end tests on macOS. Prints every injected event.
#include "prison/server.hpp"
#include <csignal>
#include <cstdio>
#include <cstdlib>
using namespace prison;
static std::atomic<bool> stop{false};
struct Printer : InputSink {
    void move(double x, double y) override { std::printf("EVENT move %.4f %.4f\n", x, y); std::fflush(stdout); }
    void button(Button b, bool down) override { std::printf("EVENT %s %s\n", b == Button::left ? "left" : b == Button::right ? "right" : "middle", down ? "down" : "up"); std::fflush(stdout); }
    void wheel(int v, int h) override { std::printf("EVENT wheel %d %d\n", v, h); std::fflush(stdout); }
    void key(ScanKey k, bool down) override { std::printf("EVENT key %02X%s %s\n", k.scan, k.extended ? "e" : "", down ? "down" : "up"); std::fflush(stdout); }
};
int main(int argc, char** argv) {
    if (argc < 3) { std::fprintf(stderr, "usage: prison_agent_host KEY PORT\n"); return 2; }
    std::signal(SIGTERM, [](int) { stop = true; });
    Printer sink; InputAgent agent(sink, "Torre simulada", "0.2.0", 2560, 1440);
    AgentServer server(agent, argv[1], static_cast<std::uint16_t>(std::atoi(argv[2])));
    return server.run(stop, [](const std::string& s) { std::printf("STATUS %s\n", s.c_str()); std::fflush(stdout); }) ? 0 : 1;
}
