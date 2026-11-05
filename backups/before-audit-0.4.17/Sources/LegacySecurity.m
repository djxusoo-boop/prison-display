#import "LegacySecurity.h"
#include <openssl/evp.h>
#include <openssl/core_names.h>
#include <openssl/kdf.h>
#include <openssl/rand.h>
#include <openssl/ssl.h>
#include <openssl/crypto.h>
#include <limits.h>

void *ADP256New(void) { return EVP_PKEY_Q_keygen(NULL, NULL, "EC", "prime256v1"); }
void ADP256Free(void *key) { EVP_PKEY_free(key); }
NSData *ADP256Public(void *key) {
    unsigned char bytes[65]; size_t length = sizeof(bytes);
    if (EVP_PKEY_get_octet_string_param(key, OSSL_PKEY_PARAM_PUB_KEY, bytes, sizeof(bytes), &length) != 1 || length != 65) return nil;
    return [NSData dataWithBytes:bytes length:length];
}
static EVP_PKEY *ADPublic(NSData *data) {
    if (data.length != 65 || ((const unsigned char *)data.bytes)[0] != 4) return NULL;
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_from_name(NULL, "EC", NULL);
    EVP_PKEY *key = NULL; char group[] = "prime256v1";
    OSSL_PARAM params[] = { OSSL_PARAM_construct_utf8_string(OSSL_PKEY_PARAM_GROUP_NAME, group, 0), OSSL_PARAM_construct_octet_string(OSSL_PKEY_PARAM_PUB_KEY, (void *)data.bytes, data.length), OSSL_PARAM_construct_end() };
    if (!ctx || EVP_PKEY_fromdata_init(ctx) != 1 || EVP_PKEY_fromdata(ctx, &key, EVP_PKEY_PUBLIC_KEY, params) != 1) { EVP_PKEY_CTX_free(ctx); EVP_PKEY_free(key); return NULL; }
    EVP_PKEY_CTX_free(ctx);
    ctx = EVP_PKEY_CTX_new_from_pkey(NULL, key, NULL);
    int valid = ctx && EVP_PKEY_public_check(ctx) == 1;
    EVP_PKEY_CTX_free(ctx);
    if (!valid) { EVP_PKEY_free(key); return NULL; }
    return key;
}
BOOL ADP256Validate(NSData *data) { EVP_PKEY *key = ADPublic(data); if (!key) return NO; EVP_PKEY_free(key); return YES; }
NSData *ADP256Shared(void *key, NSData *data) {
    EVP_PKEY *peer = ADPublic(data); EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_from_pkey(NULL, key, NULL);
    unsigned char secret[32]; size_t length = sizeof(secret); NSData *result = nil;
    if (peer && ctx && EVP_PKEY_derive_init(ctx) == 1 && EVP_PKEY_derive_set_peer(ctx, peer) == 1 && EVP_PKEY_derive(ctx, secret, &length) == 1 && length == 32) result = [NSData dataWithBytes:secret length:length];
    OPENSSL_cleanse(secret, sizeof(secret)); EVP_PKEY_CTX_free(ctx); EVP_PKEY_free(peer); return result;
}
NSData *ADSHA256(NSData *data) {
    unsigned char bytes[32]; size_t length = sizeof(bytes);
    if (EVP_Q_digest(NULL, "SHA256", NULL, data.bytes, data.length, bytes, &length) != 1 || length != 32) return nil;
    return [NSData dataWithBytes:bytes length:length];
}
NSData *ADHKDF(NSData *secret, NSData *salt, NSData *info, NSUInteger length) {
    if (!length || length > 255 * 32) return nil;
    EVP_KDF *algorithm = EVP_KDF_fetch(NULL, "HKDF", NULL);
    EVP_KDF_CTX *ctx = algorithm ? EVP_KDF_CTX_new(algorithm) : NULL;
    EVP_KDF_free(algorithm); if (!ctx) return nil;
    char digest[] = "SHA256";
    OSSL_PARAM params[] = {
        OSSL_PARAM_construct_utf8_string(OSSL_KDF_PARAM_DIGEST, digest, 0),
        OSSL_PARAM_construct_octet_string(OSSL_KDF_PARAM_KEY, (void *)secret.bytes, secret.length),
        OSSL_PARAM_construct_octet_string(OSSL_KDF_PARAM_SALT, (void *)salt.bytes, salt.length),
        OSSL_PARAM_construct_octet_string(OSSL_KDF_PARAM_INFO, (void *)info.bytes, info.length),
        OSSL_PARAM_construct_end()
    };
    NSMutableData *result = [NSMutableData dataWithLength:length];
    int ok = EVP_KDF_derive(ctx, result.mutableBytes, length, params); EVP_KDF_CTX_free(ctx);
    if (ok != 1) { OPENSSL_cleanse(result.mutableBytes, length); return nil; } return result;
}
NSData *ADEncrypt(NSData *data, NSData *key, NSData *aad) {
    if (key.length != 32 || data.length > INT_MAX || aad.length > INT_MAX) return nil;
    NSMutableData *result = [NSMutableData dataWithLength:12 + data.length + 16]; unsigned char *out = result.mutableBytes;
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new(); int written = 0, final = 0;
    int ok = ctx && RAND_bytes(out, 12) == 1 && EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, key.bytes, out) == 1 && EVP_EncryptUpdate(ctx, NULL, &written, aad.bytes, (int)aad.length) == 1 && EVP_EncryptUpdate(ctx, out + 12, &written, data.bytes, (int)data.length) == 1 && written == data.length && EVP_EncryptFinal_ex(ctx, out + 12 + written, &final) == 1 && final == 0 && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, out + 12 + data.length) == 1;
    EVP_CIPHER_CTX_free(ctx); return ok ? result : nil;
}
NSData *ADDecrypt(NSData *data, NSData *key, NSData *aad) {
    if (key.length != 32 || data.length < 28 || data.length > INT_MAX || aad.length > INT_MAX) return nil;
    NSUInteger count = data.length - 28; const unsigned char *bytes = data.bytes;
    NSMutableData *result = [NSMutableData dataWithLength:count + 16];
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new(); int written = 0, final = 0;
    int ok = ctx && EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, key.bytes, bytes) == 1 && EVP_DecryptUpdate(ctx, NULL, &written, aad.bytes, (int)aad.length) == 1 && EVP_DecryptUpdate(ctx, result.mutableBytes, &written, bytes + 12, (int)count) == 1 && written == count && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, (void *)(bytes + 12 + count)) == 1 && EVP_DecryptFinal_ex(ctx, (unsigned char *)result.mutableBytes + written, &final) == 1 && final == 0;
    EVP_CIPHER_CTX_free(ctx);
    if (!ok) { OPENSSL_cleanse(result.mutableBytes, result.length); return nil; }
    result.length = count; return result;
}
NSString *ADOpenSSLVersion(void) { return [NSString stringWithUTF8String:OpenSSL_version(OPENSSL_VERSION)]; }

typedef struct { SSL_CTX *ctx; SSL *ssl; unsigned char key[32]; } ADTLS;
static unsigned int ADClientPSK(SSL *ssl, const char *hint, char *identity, unsigned int identityLength, unsigned char *key, unsigned int keyLength) {
    ADTLS *tls = SSL_get_app_data(ssl); const char *name = "AireDisplay-v1";
    if (!tls || identityLength <= strlen(name) || keyLength < 32) return 0;
    strcpy(identity, name); memcpy(key, tls->key, 32); return 32;
}
static unsigned int ADServerPSK(SSL *ssl, const char *identity, unsigned char *key, unsigned int keyLength) {
    ADTLS *tls = SSL_get_app_data(ssl);
    if (!tls || !identity || strcmp(identity, "AireDisplay-v1") || keyLength < 32) return 0;
    memcpy(key, tls->key, 32); return 32;
}
void *ADTLSNew(int fd, BOOL server, NSData *key) {
    if (key.length != 32) return NULL;
    ADTLS *tls = calloc(1, sizeof(ADTLS)); if (!tls) return NULL;
    memcpy(tls->key, key.bytes, 32); tls->ctx = SSL_CTX_new(TLS_method());
    if (!tls->ctx || !SSL_CTX_set_min_proto_version(tls->ctx, TLS1_2_VERSION) || !SSL_CTX_set_max_proto_version(tls->ctx, TLS1_2_VERSION) || !SSL_CTX_set_cipher_list(tls->ctx, "PSK-AES128-GCM-SHA256")) { ADTLSFree(tls); return NULL; }
    SSL_CTX_set_options(tls->ctx, SSL_OP_NO_COMPRESSION | SSL_OP_NO_TICKET);
    if (server) SSL_CTX_set_psk_server_callback(tls->ctx, ADServerPSK); else SSL_CTX_set_psk_client_callback(tls->ctx, ADClientPSK);
    tls->ssl = SSL_new(tls->ctx);
    if (!tls->ssl || SSL_set_fd(tls->ssl, fd) != 1) { ADTLSFree(tls); return NULL; }
    SSL_set_app_data(tls->ssl, tls); SSL_set_mode(tls->ssl, SSL_MODE_ENABLE_PARTIAL_WRITE | SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER);
    if (server) SSL_set_accept_state(tls->ssl); else SSL_set_connect_state(tls->ssl);
    return tls;
}
static int ADTLSResult(ADTLS *tls, int result) {
    if (result > 0) return result;
    switch (SSL_get_error(tls->ssl, result)) { case SSL_ERROR_WANT_READ: return -2; case SSL_ERROR_WANT_WRITE: return -3; case SSL_ERROR_ZERO_RETURN: return 0; default: return -1; }
}
int ADTLSHandshake(void *object) { ADTLS *tls = object; return ADTLSResult(tls, SSL_do_handshake(tls->ssl)); }
int ADTLSRead(void *object, void *buffer, int length) { ADTLS *tls = object; return ADTLSResult(tls, SSL_read(tls->ssl, buffer, length)); }
int ADTLSWrite(void *object, const void *buffer, int length) { ADTLS *tls = object; return ADTLSResult(tls, SSL_write(tls->ssl, buffer, length)); }
void ADTLSFree(void *object) { ADTLS *tls = object; if (!tls) return; SSL_free(tls->ssl); SSL_CTX_free(tls->ctx); OPENSSL_cleanse(tls, sizeof(*tls)); free(tls); }
