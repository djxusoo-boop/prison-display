#include "prison/server.hpp"
#include <openssl/err.h>
#include <openssl/rand.h>
#include <openssl/ssl.h>
#include <chrono>
#include <cstring>
#include <memory>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
using Socket = SOCKET;
constexpr Socket invalid_socket = INVALID_SOCKET;
static void close_socket(Socket s) { closesocket(s); }
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
using Socket = int;
constexpr Socket invalid_socket = -1;
static void close_socket(Socket s) { close(s); }
#endif

namespace prison {
namespace {
std::uint64_t now_ms() {
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count());
}
unsigned int server_psk(SSL* ssl, const char* identity, unsigned char* key, unsigned int key_max) {
    const auto* secret = static_cast<const Bytes*>(SSL_CTX_get_app_data(SSL_get_SSL_CTX(ssl)));
    if (!identity || std::strcmp(identity, "AireDisplay-v1") || !secret || key_max < secret->size()) return 0;
    std::copy(secret->begin(), secret->end(), key);
    return static_cast<unsigned int>(secret->size());
}
bool readable(Socket a, Socket b, int timeout_ms, bool& a_ready, bool& b_ready) {
    fd_set set; FD_ZERO(&set);
    if (a != invalid_socket) FD_SET(a, &set);
    if (b != invalid_socket) FD_SET(b, &set);
    timeval tv{timeout_ms / 1000, (timeout_ms % 1000) * 1000};
    const int highest = static_cast<int>(a > b || b == invalid_socket ? a : b);
    const int result = select(highest + 1, &set, nullptr, nullptr, &tv);
    a_ready = result > 0 && a != invalid_socket && FD_ISSET(a, &set);
    b_ready = result > 0 && b != invalid_socket && FD_ISSET(b, &set);
    return result >= 0;
}
struct Connection {
    Socket socket = invalid_socket;
    SSL* ssl = nullptr;
    Parser parser;
    std::uint64_t last_receive = 0;
    ~Connection() { if (ssl) { SSL_shutdown(ssl); SSL_free(ssl); } if (socket != invalid_socket) close_socket(socket); }
    bool write(const std::vector<Packet>& packets) {
        for (const auto& packet : packets) {
            const auto bytes = frame(packet);
            std::size_t offset = 0;
            while (offset < bytes.size()) {
                const int written = SSL_write(ssl, bytes.data() + offset, static_cast<int>(bytes.size() - offset));
                if (written <= 0) return false;
                offset += static_cast<std::size_t>(written);
            }
        }
        return true;
    }
};
}

std::string new_pc_key() {
    unsigned char bytes[16];
    if (RAND_bytes(bytes, sizeof bytes) != 1) throw Error("No random key");
    static const char digits[] = "0123456789ABCDEF";
    std::string key;
    for (auto b : bytes) { key.push_back(digits[b >> 4]); key.push_back(digits[b & 15]); }
    return key;
}
std::string grouped_key(const std::string& key) {
    std::string out;
    for (std::size_t i = 0; i < key.size(); ++i) { if (i && i % 4 == 0) out.push_back('-'); out.push_back(key[i]); }
    return out;
}

AgentServer::AgentServer(InputAgent& agent, std::string key, std::uint16_t port)
    : agent_(agent), key_(normalized_key(key)), port_(port) {}

bool AgentServer::run(const std::atomic<bool>& stop, const Status& status) {
    auto secret = psk_secret(key_);
    std::unique_ptr<SSL_CTX, decltype(&SSL_CTX_free)> context(SSL_CTX_new(TLS_server_method()), SSL_CTX_free);
    if (!context || SSL_CTX_set_min_proto_version(context.get(), TLS1_2_VERSION) != 1 || SSL_CTX_set_max_proto_version(context.get(), TLS1_2_VERSION) != 1
        || SSL_CTX_set_cipher_list(context.get(), "PSK-AES128-GCM-SHA256") != 1) { status("No se pudo preparar el cifrado."); return false; }
    SSL_CTX_set_app_data(context.get(), &secret);
    SSL_CTX_set_psk_server_callback(context.get(), server_psk);

    Socket listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listener == invalid_socket) { status("No se pudo abrir la red."); return false; }
    int yes = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&yes), sizeof yes);
    sockaddr_in address{}; address.sin_family = AF_INET; address.sin_port = htons(port_); address.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(listener, reinterpret_cast<sockaddr*>(&address), sizeof address) != 0 || listen(listener, 4) != 0) {
        close_socket(listener); status("El puerto " + std::to_string(port_) + " está ocupado. ¿Hay otra copia abierta?"); return false;
    }
    status("Esperando al Mac. Escribe esta clave en PRISON DISPLAY del Mac.");
    std::unique_ptr<Connection> client;
    auto drop = [&](const std::string& reason) {
        { std::lock_guard<std::mutex> lock(mutex_); agent_.disconnect(); }
        client.reset(); status(reason);
    };
    while (!stop) {
        bool listen_ready = false, client_ready = false;
        if (!readable(listener, client ? client->socket : invalid_socket, 100, listen_ready, client_ready)) break;
        if (client && SSL_pending(client->ssl) > 0) client_ready = true;
        if (listen_ready) {
            Socket incoming = accept(listener, nullptr, nullptr);
            if (incoming != invalid_socket) {
                setsockopt(incoming, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&yes), sizeof yes);
#ifdef _WIN32
                DWORD timeout = 10000;
#else
                timeval timeout{10, 0};
#endif
                setsockopt(incoming, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout), sizeof timeout);
                auto next = std::make_unique<Connection>();
                next->socket = incoming; next->ssl = SSL_new(context.get());
                SSL_set_fd(next->ssl, static_cast<int>(incoming));
                if (SSL_accept(next->ssl) == 1) {
                    if (client) drop("Conexión anterior sustituida.");
                    client = std::move(next); client->last_receive = now_ms();
                    status("Mac conectado · comprobando versión…");
                } else { ERR_clear_error(); status("Un equipo intentó conectar con una clave incorrecta."); }
            }
        }
        if (client && client_ready) {
            std::uint8_t buffer[65536];
            const int count = SSL_read(client->ssl, buffer, sizeof buffer);
            if (count <= 0) { drop("El Mac se desconectó. Esperando…"); continue; }
            client->last_receive = now_ms();
            std::vector<Packet> replies;
            bool was_greeted = false, greeted = false, controlling = false; std::string peer;
            try {
                std::lock_guard<std::mutex> lock(mutex_);
                was_greeted = agent_.greeted();
                client->parser.feed(Bytes(buffer, buffer + count), [&](Packet packet) {
                    auto out = agent_.receive(packet, now_ms());
                    replies.insert(replies.end(), out.begin(), out.end());
                });
                greeted = agent_.greeted(); controlling = agent_.controlling(); peer = agent_.peer_name();
            } catch (const std::exception& error) {
                drop(std::string("Conexión rechazada: ") + error.what()); continue;
            }
            if (!client->write(replies)) { drop("Se perdió la conexión con el Mac."); continue; }
            if (greeted && !was_greeted) status("Conectado con " + peer + ". Lleva el ratón al borde elegido en el Mac.");
            (void)controlling;
        }
        if (client) {
            std::vector<Packet> expired;
            { std::lock_guard<std::mutex> lock(mutex_); expired = agent_.tick(now_ms()); }
            if (!expired.empty() && !client->write(expired)) { drop("Se perdió la conexión con el Mac."); continue; }
            if (now_ms() - client->last_receive > 12000) drop("El Mac dejó de responder. Esperando…");
        }
    }
    client.reset();
    { std::lock_guard<std::mutex> lock(mutex_); agent_.disconnect(); }
    close_socket(listener);
    return true;
}
}
