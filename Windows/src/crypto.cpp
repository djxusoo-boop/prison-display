#include "prison/protocol.hpp"
#include <openssl/evp.h>
#include <algorithm>
#include <cctype>
#include <memory>
namespace prison {
std::string normalized_key(const std::string& input) {
    if (input.size() > 256) throw Error("Invalid key");
    std::string value;
    for (unsigned char c : input) {
        if (std::isspace(c) || c == '-') continue;
        c = static_cast<unsigned char>(std::toupper(c));
        if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'))) throw Error("Invalid key");
        value.push_back(static_cast<char>(c));
    }
    if (value.size() != 32) throw Error("Invalid key");
    return value;
}
Bytes psk_secret(const std::string& key) {
    const auto input = std::string("AireDisplay:") + normalized_key(key);
    Bytes output(32); unsigned int count = 0;
    if (EVP_Digest(input.data(), input.size(), output.data(), &count, EVP_sha256(), nullptr) != 1 || count != 32)
        throw Error("PSK derivation failed");
    return output;
}
std::string base64(const Bytes& bytes) {
    if (bytes.size() > max_packet) throw Error("Base64 input too large");
    if (bytes.empty()) return {};
    std::string result(4 * ((bytes.size() + 2) / 3), '\0');
    const auto count = EVP_EncodeBlock(reinterpret_cast<unsigned char*>(result.data()), bytes.data(), static_cast<int>(bytes.size()));
    if (count < 0) throw Error("Base64 encoding failed");
    result.resize(static_cast<std::size_t>(count)); return result;
}
Bytes unbase64(const std::string& input) {
    if (input.empty()) return {};
    if (input.size() > max_packet || input.size() % 4) throw Error("Invalid base64");
    Bytes result(3 * (input.size()/4));
    const auto count = EVP_DecodeBlock(result.data(), reinterpret_cast<const unsigned char*>(input.data()), static_cast<int>(input.size()));
    if (count < 0) throw Error("Invalid base64");
    std::size_t padding = input.back() == '=' ? 1 : 0;
    if (input.size() >= 2 && input[input.size()-2] == '=') ++padding;
    if (static_cast<std::size_t>(count) < padding) throw Error("Invalid base64");
    result.resize(static_cast<std::size_t>(count)-padding);
    if (base64(result) != input) throw Error("Non-canonical base64");
    return result;
}
}
