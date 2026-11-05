import Foundation
import CryptoKit
var failures = 0, checks = 0
func check(_ valid: Bool, _ message: String) { checks += 1; if !valid { failures += 1; print("FAIL", message) } }
let key = Data((0..<32).map(UInt8.init))
let aad = Data("PRISON DISPLAY interop fixture".utf8)
check(SHA256.hash(data: aad) == Data(CryptoKit.SHA256.hash(data: aad)), "SHA256 agrees with CryptoKit")
let old = P256.KeyAgreement.PrivateKey(), new = CryptoKit.P256.KeyAgreement.PrivateKey()
let remote = try P256.KeyAgreement.PublicKey(x963Representation: new.publicKey.x963Representation)
let legacyShared = try old.sharedSecretFromKeyAgreement(with: remote)
let modernShared = try new.sharedSecretFromKeyAgreement(with: CryptoKit.P256.KeyAgreement.PublicKey(x963Representation: old.publicKey.x963Representation))
let modernBytes = modernShared.withUnsafeBytes { Data($0) }
check(legacyShared.data == modernBytes, "P256 agrees across implementations")
for length in [16, 32, 42, 64] {
    let oldKey = legacyShared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: aad, sharedInfo: key, outputByteCount: length)
    let newKey = modernShared.hkdfDerivedSymmetricKey(using: CryptoKit.SHA256.self, salt: aad, sharedInfo: key, outputByteCount: length)
    check(oldKey.data == newKey.withUnsafeBytes({ Data($0) }), "HKDF output agrees at \(length) bytes")
}
for size in [0, 1, 16, 4096, 65536, 1_048_576] {
    let input = Data((0..<size).map { UInt8(truncatingIfNeeded: $0) })
    let native = try CryptoKit.AES.GCM.seal(input, using: CryptoKit.SymmetricKey(data: key), authenticating: aad)
    let legacyBox = try AES.GCM.SealedBox(combined: native.combined!)
    check(try AES.GCM.open(legacyBox, using: SymmetricKey(data: key), authenticating: aad) == input, "decrypts CryptoKit payload size \(size)")
    let oldBox = try AES.GCM.seal(input, using: SymmetricKey(data: key), authenticating: aad)
    check(try CryptoKit.AES.GCM.open(CryptoKit.AES.GCM.SealedBox(combined: oldBox.combined!), using: CryptoKit.SymmetricKey(data: key), authenticating: aad) == input, "CryptoKit decrypts legacy payload size \(size)")
    var corrupt = oldBox.combined!; corrupt[corrupt.count-1] ^= 1
    do { _ = try AES.GCM.open(AES.GCM.SealedBox(combined: corrupt), using: SymmetricKey(data: key), authenticating: aad); check(false, "corrupt tag rejected") } catch { check(true, "corrupt tag rejected") }
    do { _ = try AES.GCM.open(oldBox, using: SymmetricKey(data: key), authenticating: Data()); check(false, "wrong transcript rejected") } catch { check(true, "wrong transcript rejected") }
}
for invalid in [Data(), Data(repeating: 0, count: 65), Data([4])+Data(repeating: 255, count: 64)] {
    do { _ = try P256.KeyAgreement.PublicKey(x963Representation: invalid); check(false, "invalid curve point rejected") } catch { check(true, "invalid curve point rejected") }
}
print("RESULT", checks, "checks", failures, "failures", ADOpenSSLVersion())
exit(failures == 0 ? 0 : 1)
