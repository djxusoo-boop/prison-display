#if LEGACY
import Foundation

enum SHA256 {
    static func hash(data: Data) -> Data {
        guard let digest = ADSHA256(data) else { preconditionFailure("SHA256 unavailable") }
        return digest as Data
    }
}
struct SymmetricKey {
    let data: Data
    func withUnsafeBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T { try data.withUnsafeBytes(body) }
}
enum P256 {
    enum KeyAgreement {
        struct PublicKey {
            let x963Representation: Data
            init(x963Representation: Data) throws {
                guard ADP256Validate(x963Representation) else { throw AireError("Clave pública P256 inválida.") }
                self.x963Representation = x963Representation
            }
        }
        final class PrivateKey {
            private let key: UnsafeMutableRawPointer
            init() {
                guard let key = ADP256New() else { preconditionFailure("Secure P256 key generation failed") }
                self.key = key
            }
            deinit { ADP256Free(key) }
            var publicKey: PublicKey {
                guard let publicBytes = ADP256Public(key) else { preconditionFailure("P256 public key unavailable") }
                return try! PublicKey(x963Representation: publicBytes as Data)
            }
            func sharedSecretFromKeyAgreement(with peer: PublicKey) throws -> SharedSecret {
                guard let bytes = ADP256Shared(key, peer.x963Representation) else { throw AireError("No se pudo acordar la conexión cifrada.") }
                return SharedSecret(data: bytes as Data)
            }
        }
    }
}
struct SharedSecret {
    let data: Data
    func hkdfDerivedSymmetricKey(using: SHA256.Type, salt: Data, sharedInfo: Data, outputByteCount: Int) -> SymmetricKey {
        guard let bytes = ADHKDF(data, salt, sharedInfo, UInt(outputByteCount)) else { preconditionFailure("HKDF unavailable") }
        return SymmetricKey(data: bytes as Data)
    }
}
enum AES {
    enum GCM {
        struct SealedBox {
            let combined: Data?
            init(combined: Data) throws {
                guard combined.count >= 28, combined.count <= Wire.maxPacket else { throw AireError("Mensaje cifrado inválido.") }
                self.combined = combined
            }
        }
        static func seal(_ data: Data, using key: SymmetricKey, authenticating aad: Data) throws -> SealedBox {
            guard let result = ADEncrypt(data, key.data, aad) else { throw AireError("No se pudo cifrar la conexión.") }
            return try SealedBox(combined: result as Data)
        }
        static func open(_ box: SealedBox, using key: SymmetricKey, authenticating aad: Data) throws -> Data {
            guard let bytes = box.combined, let result = ADDecrypt(bytes, key.data, aad) else { throw AireError("La autenticación del mensaje cifrado ha fallado.") }
            return result as Data
        }
    }
}
#endif
