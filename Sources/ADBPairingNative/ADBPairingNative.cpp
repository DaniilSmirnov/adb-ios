#include "ADBPairingNative.h"

#if defined(ADBKit_BoringSSL_ENABLED)

#include <openssl/aead.h>
#include <openssl/curve25519.h>
#include <openssl/evp.h>
#include <openssl/hkdf.h>

#include <cstring>
#include <new>

struct ADBPairingCryptoContext {
    SPAKE2_CTX* spake = nullptr;
    EVP_AEAD_CTX* aead = nullptr;
    uint64_t encrypt_sequence = 0;
    uint64_t decrypt_sequence = 0;
};

namespace {

constexpr uint8_t kClientName[] = "adb pair client";
constexpr uint8_t kServerName[] = "adb pair server";
constexpr char kHKDFInfo[] = "adb pairing_auth aes-128-gcm key";
constexpr size_t kAESKeyLength = 16;
constexpr size_t kMaxSpakeMessageLength = 32;
constexpr size_t kMaxSpakeKeyLength = 64;

void destroy_context(ADBPairingCryptoContext* context) {
    if (context == nullptr) return;
    SPAKE2_CTX_free(context->spake);
    EVP_AEAD_CTX_free(context->aead);
    delete context;
}

bool initialize_cipher(ADBPairingCryptoContext* context, const uint8_t* key_material,
                       size_t key_material_len) {
    uint8_t key[kAESKeyLength];
    if (HKDF(key, sizeof(key), EVP_sha256(), key_material, key_material_len, nullptr, 0,
             reinterpret_cast<const uint8_t*>(kHKDFInfo), sizeof(kHKDFInfo) - 1) != 1) {
        return false;
    }
    context->aead = EVP_AEAD_CTX_new(EVP_aead_aes_128_gcm(), key, sizeof(key),
                                     EVP_AEAD_DEFAULT_TAG_LENGTH);
    return context->aead != nullptr;
}

bool crypt(ADBPairingCryptoContext* context, bool encrypt, const uint8_t* input,
           size_t input_len, uint8_t* output, size_t output_capacity, size_t* output_len) {
    if (context == nullptr || context->aead == nullptr || input == nullptr || input_len == 0 ||
        output == nullptr || output_len == nullptr) {
        return false;
    }
    const size_t required = encrypt ? input_len + EVP_AEAD_max_overhead(EVP_aead_aes_128_gcm())
                                    : input_len;
    if (output_capacity < required) return false;

    uint8_t nonce[12] = {};
    uint64_t& sequence = encrypt ? context->encrypt_sequence : context->decrypt_sequence;
    std::memcpy(nonce, &sequence, sizeof(sequence));
    size_t written = 0;
    const int ok = encrypt
        ? EVP_AEAD_CTX_seal(context->aead, output, &written, output_capacity, nonce, sizeof(nonce),
                            input, input_len, nullptr, 0)
        : EVP_AEAD_CTX_open(context->aead, output, &written, output_capacity, nonce, sizeof(nonce),
                            input, input_len, nullptr, 0);
    if (!ok) return false;
    ++sequence;
    *output_len = written;
    return true;
}

}  // namespace

extern "C" {

int adb_pairing_boringssl_available(void) { return 1; }

ADBPairingCryptoContext* create_context(
    spake2_role_t role, const uint8_t* my_name, size_t my_name_len,
    const uint8_t* their_name, size_t their_name_len,
    const uint8_t* password, size_t password_len,
    uint8_t* message, size_t* message_len, size_t message_capacity) {
    if (password == nullptr || password_len == 0 || message == nullptr || message_len == nullptr ||
        message_capacity < kMaxSpakeMessageLength) {
        return nullptr;
    }
    auto* context = new (std::nothrow) ADBPairingCryptoContext();
    if (context == nullptr) return nullptr;
    context->spake = SPAKE2_CTX_new(role, my_name, my_name_len, their_name, their_name_len);
    if (context->spake == nullptr ||
        SPAKE2_generate_msg(context->spake, message, message_len, message_capacity,
                            password, password_len) != 1 || *message_len == 0) {
        destroy_context(context);
        return nullptr;
    }
    return context;
}

ADBPairingCryptoContext* adb_pairing_crypto_client_new(
    const uint8_t* password, size_t password_len,
    uint8_t* message, size_t* message_len, size_t message_capacity) {
    return create_context(spake2_role_alice, kClientName, sizeof(kClientName),
                          kServerName, sizeof(kServerName), password, password_len,
                          message, message_len, message_capacity);
}

ADBPairingCryptoContext* adb_pairing_crypto_server_new(
    const uint8_t* password, size_t password_len,
    uint8_t* message, size_t* message_len, size_t message_capacity) {
    return create_context(spake2_role_bob, kServerName, sizeof(kServerName),
                          kClientName, sizeof(kClientName), password, password_len,
                          message, message_len, message_capacity);
}

int adb_pairing_crypto_process(ADBPairingCryptoContext* context,
                               const uint8_t* peer_message, size_t peer_message_len) {
    if (context == nullptr || context->spake == nullptr || peer_message == nullptr ||
        peer_message_len == 0 || peer_message_len > kMaxSpakeMessageLength) {
        return 0;
    }
    uint8_t key_material[kMaxSpakeKeyLength];
    size_t key_material_len = 0;
    if (SPAKE2_process_msg(context->spake, key_material, &key_material_len,
                           sizeof(key_material), peer_message, peer_message_len) != 1) {
        return 0;
    }
    SPAKE2_CTX_free(context->spake);
    context->spake = nullptr;
    return initialize_cipher(context, key_material, key_material_len) ? 1 : 0;
}

size_t adb_pairing_crypto_encrypted_size(const ADBPairingCryptoContext* context, size_t length) {
    if (context == nullptr || context->aead == nullptr) return 0;
    return length + EVP_AEAD_max_overhead(EVP_aead_aes_128_gcm());
}

int adb_pairing_crypto_encrypt(ADBPairingCryptoContext* context, const uint8_t* input,
                               size_t input_len, uint8_t* output, size_t output_capacity,
                               size_t* output_len) {
    return crypt(context, true, input, input_len, output, output_capacity, output_len) ? 1 : 0;
}

int adb_pairing_crypto_decrypt(ADBPairingCryptoContext* context, const uint8_t* input,
                               size_t input_len, uint8_t* output, size_t output_capacity,
                               size_t* output_len) {
    return crypt(context, false, input, input_len, output, output_capacity, output_len) ? 1 : 0;
}

void adb_pairing_crypto_destroy(ADBPairingCryptoContext* context) { destroy_context(context); }

}  // extern "C"

#else

int adb_pairing_boringssl_available(void) { return 0; }

ADBPairingCryptoContext* adb_pairing_crypto_client_new(
    const uint8_t*, size_t, uint8_t*, size_t*, size_t) { return nullptr; }
ADBPairingCryptoContext* adb_pairing_crypto_server_new(
    const uint8_t*, size_t, uint8_t*, size_t*, size_t) { return nullptr; }
int adb_pairing_crypto_process(ADBPairingCryptoContext*, const uint8_t*, size_t) { return 0; }
size_t adb_pairing_crypto_encrypted_size(const ADBPairingCryptoContext*, size_t) { return 0; }
int adb_pairing_crypto_encrypt(ADBPairingCryptoContext*, const uint8_t*, size_t, uint8_t*, size_t,
                               size_t*) { return 0; }
int adb_pairing_crypto_decrypt(ADBPairingCryptoContext*, const uint8_t*, size_t, uint8_t*, size_t,
                               size_t*) { return 0; }
void adb_pairing_crypto_destroy(ADBPairingCryptoContext*) {}

#endif
