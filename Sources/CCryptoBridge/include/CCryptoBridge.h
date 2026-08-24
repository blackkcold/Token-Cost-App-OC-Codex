#ifndef CCryptoBridge_h
#define CCryptoBridge_h

#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonKeyDerivation.h>

int cc_aes128cbc_decrypt(
    const void *key, const void *iv,
    const void *ct, size_t ctLen,
    void *pt, size_t *ptLen);

int cc_pbkdf2_sha1(
    const char *pw, size_t pwLen,
    const uint8_t *salt, size_t saltLen,
    int rounds,
    uint8_t *dk, size_t dkLen);

int cc_pbkdf2_sha256(
    const char *pw, size_t pwLen,
    const uint8_t *salt, size_t saltLen,
    int rounds,
    uint8_t *dk, size_t dkLen);

/// AES-CBC decrypt with arbitrary key size (16=B128, 24=B192, 32=B256).
/// Uses PKCS7 padding. Returns 0 on success, non-zero on failure.
int cc_aescbc_decrypt(
    const void *key, size_t keyLen,
    const void *iv,
    const void *ct, size_t ctLen,
    void *pt, size_t *ptLen);

size_t cc_zlib_compress_bound(size_t sourceLen);

int cc_zlib_compress(
    const uint8_t *source, size_t sourceLen,
    uint8_t *destination, size_t *destinationLen,
    int level);

int cc_zlib_decompress(
    const uint8_t *source, size_t sourceLen,
    uint8_t *destination, size_t *destinationLen);

#endif /* CCryptoBridge_h */
