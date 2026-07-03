#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonKeyDerivation.h>

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
