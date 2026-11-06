#include "prison/pairing.hpp"
#include "prison/server.hpp"
#include <openssl/core_names.h>
#include <openssl/evp.h>
#include <openssl/kdf.h>
#include <openssl/params.h>
#include <openssl/rand.h>
#include <cstdio>
#include <cstring>

namespace prison {
namespace {
constexpr char protocol_label[] = "pc-pair-v1";
using Key = std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)>;
using Context = std::unique_ptr<EVP_PKEY_CTX, decltype(&EVP_PKEY_CTX_free)>;
Bytes public_point(EVP_PKEY* key) {
    Bytes out(65); std::size_t length = 0;
    if (EVP_PKEY_get_octet_string_param(key, OSSL_PKEY_PARAM_ENCODED_PUBLIC_KEY, out.data(), out.size(), &length) != 1 || length != 65) throw Error("Public key export failed");
    return out;
}
Key import_point(const Bytes& point) {
    if (point.size() != 65 || point[0] != 4) throw Error("Invalid public key");
    char group[] = "prime256v1";
    OSSL_PARAM params[] = {
        OSSL_PARAM_construct_utf8_string(OSSL_PKEY_PARAM_GROUP_NAME, group, 0),
        OSSL_PARAM_construct_octet_string(OSSL_PKEY_PARAM_PUB_KEY, const_cast<std::uint8_t*>(point.data()), point.size()),
        OSSL_PARAM_construct_end()};
    Context context(EVP_PKEY_CTX_new_from_name(nullptr, "EC", nullptr), EVP_PKEY_CTX_free);
    EVP_PKEY* key = nullptr;
    if (!context || EVP_PKEY_fromdata_init(context.get()) != 1 || EVP_PKEY_fromdata(context.get(), &key, EVP_PKEY_PUBLIC_KEY, params) != 1) throw Error("Invalid public key");
    Key result(key, EVP_PKEY_free);
    Context check(EVP_PKEY_CTX_new_from_pkey(nullptr, key, nullptr), EVP_PKEY_CTX_free);
    if (!check || EVP_PKEY_public_check(check.get()) != 1) throw Error("Public key not on curve");
    return result;
}
}

struct PairingSession::Keys {
    Key own{EVP_PKEY_Q_keygen(nullptr, nullptr, "EC", "P-256"), EVP_PKEY_free};
    Bytes key, transcript;
};

std::string pc_announcement(const std::string& name, const std::string& version, std::uint16_t input_port, std::uint16_t pairing_port) {
    return "PRISON-PC/1|" + name + "|" + version + "|" + std::to_string(input_port) + "|" + std::to_string(pairing_port);
}

Bytes PairingMath::derive(const Bytes& shared, const Bytes& transcript) {
    Bytes out(32);
    Context context(EVP_PKEY_CTX_new_id(EVP_PKEY_HKDF, nullptr), EVP_PKEY_CTX_free);
    static const char salt[] = "AireDisplay pairing";
    std::size_t length = out.size();
    if (!context || EVP_PKEY_derive_init(context.get()) != 1 || EVP_PKEY_CTX_set_hkdf_md(context.get(), EVP_sha256()) != 1
        || EVP_PKEY_CTX_set1_hkdf_salt(context.get(), reinterpret_cast<const unsigned char*>(salt), static_cast<int>(std::strlen(salt))) != 1
        || EVP_PKEY_CTX_set1_hkdf_key(context.get(), shared.data(), static_cast<int>(shared.size())) != 1
        || EVP_PKEY_CTX_add1_hkdf_info(context.get(), transcript.data(), static_cast<int>(transcript.size())) != 1
        || EVP_PKEY_derive(context.get(), out.data(), &length) != 1 || length != 32) throw Error("Key derivation failed");
    return out;
}
std::string PairingMath::code(const Bytes& key) {
    Bytes input = key; const char verify[] = "verify"; input.insert(input.end(), verify, verify + 6);
    unsigned char digest[32]; unsigned int length = 0;
    if (EVP_Digest(input.data(), input.size(), digest, &length, EVP_sha256(), nullptr) != 1) throw Error("Digest failed");
    const std::uint32_t value = (std::uint32_t(digest[0]) << 24) | (std::uint32_t(digest[1]) << 16) | (std::uint32_t(digest[2]) << 8) | digest[3];
    char text[8]; std::snprintf(text, sizeof text, "%06u", value % 1000000u); return text;
}
Bytes PairingMath::seal(const Bytes& key, const Bytes& plaintext, const Bytes& aad) {
    Bytes out(12); if (RAND_bytes(out.data(), 12) != 1) throw Error("No random nonce");
    std::unique_ptr<EVP_CIPHER_CTX, decltype(&EVP_CIPHER_CTX_free)> c(EVP_CIPHER_CTX_new(), EVP_CIPHER_CTX_free);
    int length = 0; Bytes cipher(plaintext.size()); Bytes tag(16);
    if (!c || EVP_EncryptInit_ex(c.get(), EVP_aes_256_gcm(), nullptr, key.data(), out.data()) != 1
        || EVP_EncryptUpdate(c.get(), nullptr, &length, aad.data(), static_cast<int>(aad.size())) != 1
        || EVP_EncryptUpdate(c.get(), cipher.data(), &length, plaintext.data(), static_cast<int>(plaintext.size())) != 1
        || EVP_EncryptFinal_ex(c.get(), cipher.data() + length, &length) != 1
        || EVP_CIPHER_CTX_ctrl(c.get(), EVP_CTRL_GCM_GET_TAG, 16, tag.data()) != 1) throw Error("Encryption failed");
    out.insert(out.end(), cipher.begin(), cipher.end()); out.insert(out.end(), tag.begin(), tag.end());
    return out; // nonce | ciphertext | tag, as CryptoKit's AES.GCM combined form.
}
Bytes PairingMath::open(const Bytes& key, const Bytes& sealed, const Bytes& aad) {
    if (sealed.size() < 28) throw Error("Sealed data too short");
    std::unique_ptr<EVP_CIPHER_CTX, decltype(&EVP_CIPHER_CTX_free)> c(EVP_CIPHER_CTX_new(), EVP_CIPHER_CTX_free);
    const std::size_t body = sealed.size() - 28; Bytes plain(body); int length = 0;
    Bytes tag(sealed.end() - 16, sealed.end());
    if (!c || EVP_DecryptInit_ex(c.get(), EVP_aes_256_gcm(), nullptr, key.data(), sealed.data()) != 1
        || EVP_DecryptUpdate(c.get(), nullptr, &length, aad.data(), static_cast<int>(aad.size())) != 1
        || EVP_DecryptUpdate(c.get(), plain.data(), &length, sealed.data() + 12, static_cast<int>(body)) != 1
        || EVP_CIPHER_CTX_ctrl(c.get(), EVP_CTRL_GCM_SET_TAG, 16, tag.data()) != 1
        || EVP_DecryptFinal_ex(c.get(), plain.data() + length, &length) != 1) throw Error("Authentication failed");
    return plain;
}

PairingSession::PairingSession(std::string name, std::string version, std::string key, std::uint16_t input_port, Confirm confirm)
    : keys_(std::make_unique<Keys>()), name_(std::move(name)), version_(std::move(version)), key_(normalized_key(key)), input_port_(input_port), confirm_(std::move(confirm)) {
    if (!keys_->own) throw Error("Key generation failed");
}
PairingSession::~PairingSession() = default;

std::vector<Packet> PairingSession::send_credentials() {
    if (!local_ok_ || !remote_ok_ || finished_) return {};
    finished_ = true;
    const std::string text = key_ + "|" + std::to_string(input_port_) + "|" + version_;
    return {{Kind::video, PairingMath::seal(keys_->key, Bytes(text.begin(), text.end()), keys_->transcript)}};
}

std::vector<Packet> PairingSession::decide() {
    if (!awaiting_decision_) return {};
    awaiting_decision_ = false;
    local_ok_ = confirm_ ? confirm_(mac_, code_) : false;
    if (!local_ok_) { finished_ = true; const std::string no = "Rechazado en el PC."; return {{Kind::failure, Bytes(no.begin(), no.end())}}; }
    return send_credentials();
}

std::vector<Packet> PairingSession::receive(const Packet& packet) {
    if (packet.kind == Kind::ping) return {{Kind::pong, {}}};
    if (packet.kind == Kind::pong) return {};
    if (finished_) return {};
    if (packet.kind == Kind::hello) {
        if (!keys_->key.empty() || packet.body.size() > 1024) throw Error("Unexpected pairing hello");
        const std::string text(packet.body.begin(), packet.body.end());
        const auto a = text.find('|'), b = a == std::string::npos ? a : text.find('|', a + 1);
        if (b == std::string::npos || text.substr(0, a) != protocol_label) throw Error("Not a PRISON DISPLAY Mac");
        mac_ = text.substr(a + 1, b - a - 1);
        if (mac_.empty() || mac_.size() > 128) throw Error("Invalid Mac name");
        const Bytes mac_public = unbase64(text.substr(b + 1));
        auto remote = import_point(mac_public);
        const Bytes own_public = public_point(keys_->own.get());
        Context derive(EVP_PKEY_CTX_new_from_pkey(nullptr, keys_->own.get(), nullptr), EVP_PKEY_CTX_free);
        std::size_t length = 0;
        if (!derive || EVP_PKEY_derive_init(derive.get()) != 1 || EVP_PKEY_derive_set_peer(derive.get(), remote.get()) != 1
            || EVP_PKEY_derive(derive.get(), nullptr, &length) != 1) throw Error("Key agreement failed");
        Bytes shared(length);
        if (EVP_PKEY_derive(derive.get(), shared.data(), &length) != 1) throw Error("Key agreement failed");
        const std::string label = "PRISON-PC-pair-v1";
        Bytes& transcript = keys_->transcript;
        transcript.assign(label.begin(), label.end());
        transcript.insert(transcript.end(), mac_public.begin(), mac_public.end());
        transcript.insert(transcript.end(), own_public.begin(), own_public.end());
        keys_->key = PairingMath::derive(shared, transcript);
        code_ = PairingMath::code(keys_->key);
        const std::string reply = std::string(protocol_label) + "|" + name_ + "|" + base64(own_public);
        awaiting_decision_ = true;
        return {{Kind::hello, Bytes(reply.begin(), reply.end())}};
    }
    if (packet.kind == Kind::ack) {
        if (keys_->key.empty() || remote_ok_ || !packet.body.empty()) throw Error("Unexpected confirmation");
        remote_ok_ = true; return send_credentials();
    }
    if (packet.kind == Kind::failure) { finished_ = true; return {}; }
    throw Error("Unexpected pairing message");
}
}
