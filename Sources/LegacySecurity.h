#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
void * _Nullable ADP256New(void);
void ADP256Free(void *key);
NSData * _Nullable ADP256Public(void *key);
BOOL ADP256Validate(NSData *publicKey);
NSData * _Nullable ADP256Shared(void *key, NSData *publicKey);
NSData * _Nullable ADSHA256(NSData *data);
NSData * _Nullable ADHKDF(NSData *secret, NSData *salt, NSData *info, NSUInteger length);
NSData * _Nullable ADEncrypt(NSData *data, NSData *key, NSData *aad);
NSData * _Nullable ADDecrypt(NSData *data, NSData *key, NSData *aad);
NSString *ADOpenSSLVersion(void);
// Nonblocking return codes: >0 progress; 0 closed; -2 read; -3 write; -1 error.
void * _Nullable ADTLSNew(int fd, BOOL server, NSData *key);
int ADTLSHandshake(void *tls);
int ADTLSRead(void *tls, void *buffer, int length);
int ADTLSWrite(void *tls, const void *buffer, int length);
void ADTLSFree(void *tls);
NS_ASSUME_NONNULL_END
