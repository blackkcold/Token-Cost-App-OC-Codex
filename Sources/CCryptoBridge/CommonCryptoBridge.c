#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonKeyDerivation.h>
#include <zlib.h>

int cc_aes128cbc_decrypt(
    const void *key, const void *iv,
    const void *ct, size_t ctLen,
    void *pt, size_t *ptLen)
{
    return CCCrypt(kCCDecrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
                   key, kCCKeySizeAES128, iv, ct, ctLen,
                   pt, *ptLen, ptLen);
}

int cc_pbkdf2_sha1(
    const char *pw, size_t pwLen,
    const uint8_t *salt, size_t saltLen,
    int rounds,
    uint8_t *dk, size_t dkLen)
{
    return CCKeyDerivationPBKDF(kCCPBKDF2, pw, pwLen,
        salt, saltLen, kCCPRFHmacAlgSHA1, rounds, dk, dkLen);
}

int cc_pbkdf2_sha256(
    const char *pw, size_t pwLen,
    const uint8_t *salt, size_t saltLen,
    int rounds,
    uint8_t *dk, size_t dkLen)
{
    return CCKeyDerivationPBKDF(kCCPBKDF2, pw, pwLen,
        salt, saltLen, kCCPRFHmacAlgSHA256, rounds, dk, dkLen);
}

int cc_aescbc_decrypt(
    const void *key, size_t keyLen,
    const void *iv,
    const void *ct, size_t ctLen,
    void *pt, size_t *ptLen)
{
    return CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                   key, keyLen, iv, ct, ctLen,
                   pt, *ptLen, ptLen);
}

size_t cc_zlib_compress_bound(size_t sourceLen)
{
    return (size_t)compressBound((uLong)sourceLen);
}

int cc_zlib_compress(
    const uint8_t *source, size_t sourceLen,
    uint8_t *destination, size_t *destinationLen,
    int level)
{
    uLongf outputLength = (uLongf)*destinationLen;
    int status = compress2(destination, &outputLength, source, (uLong)sourceLen, level);
    *destinationLen = (size_t)outputLength;
    return status;
}

int cc_zlib_decompress(
    const uint8_t *source, size_t sourceLen,
    uint8_t *destination, size_t *destinationLen)
{
    uLongf outputLength = (uLongf)*destinationLen;
    int status = uncompress(destination, &outputLength, source, (uLong)sourceLen);
    *destinationLen = (size_t)outputLength;
    return status;
}
