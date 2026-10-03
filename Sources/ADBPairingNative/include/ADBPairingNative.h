#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ADBPairingCryptoContext ADBPairingCryptoContext;

/// Returns 1 when this target was built with the pinned BoringSSL headers and library.
int adb_pairing_boringssl_available(void);

/// Creates the AOSP pairing-auth client context and returns its SPAKE2 message.
ADBPairingCryptoContext* adb_pairing_crypto_client_new(
    const uint8_t* password, size_t password_len,
    uint8_t* message, size_t* message_len, size_t message_capacity);

ADBPairingCryptoContext* adb_pairing_crypto_server_new(
    const uint8_t* password, size_t password_len,
    uint8_t* message, size_t* message_len, size_t message_capacity);

/// Processes the peer SPAKE2 message and initializes the AOSP AES-128-GCM cipher.
int adb_pairing_crypto_process(
    ADBPairingCryptoContext* context,
    const uint8_t* peer_message, size_t peer_message_len);

size_t adb_pairing_crypto_encrypted_size(const ADBPairingCryptoContext* context, size_t length);

int adb_pairing_crypto_encrypt(
    ADBPairingCryptoContext* context,
    const uint8_t* input, size_t input_len,
    uint8_t* output, size_t output_capacity, size_t* output_len);

int adb_pairing_crypto_decrypt(
    ADBPairingCryptoContext* context,
    const uint8_t* input, size_t input_len,
    uint8_t* output, size_t output_capacity, size_t* output_len);

void adb_pairing_crypto_destroy(ADBPairingCryptoContext* context);

#ifdef __cplusplus
}
#endif
