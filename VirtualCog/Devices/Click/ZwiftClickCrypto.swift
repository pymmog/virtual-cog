import CryptoSwift
import Foundation
import Security

/// ECDH P-256 + HKDF-SHA256 + AES-CCM session used by classic Zwift Click / Play.
final class ZwiftClickCrypto {
    struct SessionKeys {
        let encryptionKey: [UInt8] // first 32 of HKDF
        let nonceSuffix: [UInt8]   // last 4 of HKDF
    }

    private(set) var keys: SessionKeys?
    private var txCounter: UInt32 = 0
    private var appPublicKeyRaw: [UInt8] = []
    private var privateKey: SecKey?
    private(set) var handshakeComplete = false
    private(set) var encryptionEnabled = true

    static let rideOnASCII: [UInt8] = Array("RideOn".utf8)

    func buildAppPublicKeyPayload() throws -> Data {
        let (privateKey, publicKey) = try Self.generateKeyPair()
        self.privateKey = privateKey
        let pub = try Self.exportUncompressedPublicKey(publicKey)
        // Drop leading 0x04 uncompressed marker for wire format.
        appPublicKeyRaw = Array(pub.dropFirst())
        var payload = Data(Self.rideOnASCII)
        payload.append(contentsOf: [0x01, 0x02])
        payload.append(contentsOf: appPublicKeyRaw)
        return payload
    }

    /// Returns true when encryption session established; false for plain RideOn (no keys).
    @discardableResult
    func processDeviceHandshakeResponse(_ data: Data) throws -> Bool {
        let bytes = Array(data)
        guard bytes.starts(with: Self.rideOnASCII) else {
            throw CryptoSessionError.invalidHandshake
        }
        // Plain Ride-style: "RideOn" only or short payload without keys.
        if bytes.count <= 8 {
            encryptionEnabled = false
            handshakeComplete = true
            keys = nil
            return false
        }
        guard bytes.count >= 8 + 64 else {
            // Some firmwares use RideOn + 2 byte header without full key → treat as plain.
            encryptionEnabled = false
            handshakeComplete = true
            keys = nil
            return false
        }
        let header0 = bytes[6]
        let header1 = bytes[7]
        _ = (header0, header1) // observed 0x00 0x09 or 0x01 0x03
        let devicePub = Array(bytes[8..<(8 + 64)])
        guard let privateKey else { throw CryptoSessionError.missingLocalKey }
        let shared = try Self.ecdhSharedSecret(privateKey: privateKey, devicePublicKeyX963: [0x04] + devicePub)
        let salt = devicePub + appPublicKeyRaw
        let derived = try Self.hkdfSHA256(ikm: shared, salt: salt, info: [], length: 36)
        keys = SessionKeys(
            encryptionKey: Array(derived[0..<32]),
            nonceSuffix: Array(derived[32..<36])
        )
        encryptionEnabled = true
        handshakeComplete = true
        txCounter = 0
        return true
    }

    func markPlainRideOn() {
        encryptionEnabled = false
        handshakeComplete = true
        keys = nil
    }

    func decrypt(_ packet: Data) throws -> Data {
        guard encryptionEnabled else { return packet }
        guard let keys else { throw CryptoSessionError.notReady }
        let bytes = Array(packet)
        guard bytes.count >= 8 else { throw CryptoSessionError.ciphertextTooShort }
        let counterBytes = Array(bytes[0..<4])
        let mic = Array(bytes[(bytes.count - 4)...])
        let ciphertext = Array(bytes[4..<(bytes.count - 4)])
        let nonce = keys.nonceSuffix + counterBytes
        let aes = try AES(
            key: keys.encryptionKey,
            blockMode: CCM(iv: nonce, tagLength: 4, messageLength: ciphertext.count, additionalAuthenticatedData: []),
            padding: .noPadding
        )
        let plain = try aes.decrypt(ciphertext + mic)
        return Data(plain)
    }

    func encrypt(_ plain: Data) throws -> Data {
        guard encryptionEnabled else { return plain }
        guard let keys else { throw CryptoSessionError.notReady }
        let counter = txCounter
        txCounter &+= 1
        var counterBytes: [UInt8] = [
            UInt8(counter & 0xFF),
            UInt8((counter >> 8) & 0xFF),
            UInt8((counter >> 16) & 0xFF),
            UInt8((counter >> 24) & 0xFF)
        ]
        let nonce = keys.nonceSuffix + counterBytes
        let aes = try AES(
            key: keys.encryptionKey,
            blockMode: CCM(iv: nonce, tagLength: 4, messageLength: plain.count, additionalAuthenticatedData: []),
            padding: .noPadding
        )
        let sealed = try aes.encrypt(Array(plain))
        // CryptoSwift CCM returns ciphertext || tag
        return Data(counterBytes + sealed)
    }

    // MARK: - Key utilities

    static func generateKeyPair() throws -> (SecKey, SecKey) {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: false]
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey)
        else {
            throw CryptoSessionError.keyGenerationFailed(error?.takeRetainedValue())
        }
        return (privateKey, publicKey)
    }

    static func exportUncompressedPublicKey(_ publicKey: SecKey) throws -> [UInt8] {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw CryptoSessionError.keyExportFailed(error?.takeRetainedValue())
        }
        // X9.63: 0x04 || X(32) || Y(32)
        guard data.count == 65, data[0] == 0x04 else {
            throw CryptoSessionError.unexpectedKeyFormat
        }
        return Array(data)
    }

    static func ecdhSharedSecret(privateKey: SecKey, devicePublicKeyX963: [UInt8]) throws -> [UInt8] {
        let pubAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256
        ]
        var error: Unmanaged<CFError>?
        guard let peer = SecKeyCreateWithData(Data(devicePublicKeyX963) as CFData, pubAttrs as CFDictionary, &error) else {
            throw CryptoSessionError.keyImportFailed(error?.takeRetainedValue())
        }
        guard let shared = SecKeyCopyKeyExchangeResult(
            privateKey,
            SecKeyAlgorithm.ecdhKeyExchangeStandard,
            peer,
            [SecKeyKeyExchangeParameter.requestedSize.rawValue as String: 32] as CFDictionary,
            &error
        ) as Data? else {
            throw CryptoSessionError.ecdhFailed(error?.takeRetainedValue())
        }
        // Raw ECDH shared secret (X coordinate); HKDF is applied separately per Zwift Click.
        return Array(shared.prefix(32))
    }

    static func hkdfSHA256(ikm: [UInt8], salt: [UInt8], info: [UInt8], length: Int) throws -> [UInt8] {
        try HKDF(password: ikm, salt: salt, info: info, keyLength: length, variant: .sha2(.sha256)).calculate()
    }

    /// Test helper: inject derived keys directly (golden vector tests).
    func installKeysForTesting(encryptionKey: [UInt8], nonceSuffix: [UInt8]) {
        precondition(encryptionKey.count == 32)
        precondition(nonceSuffix.count == 4)
        keys = SessionKeys(encryptionKey: encryptionKey, nonceSuffix: nonceSuffix)
        encryptionEnabled = true
        handshakeComplete = true
        txCounter = 0
    }
}

enum CryptoSessionError: Error {
    case invalidHandshake
    case missingLocalKey
    case notReady
    case ciphertextTooShort
    case keyGenerationFailed(CFError?)
    case keyExportFailed(CFError?)
    case keyImportFailed(CFError?)
    case unexpectedKeyFormat
    case ecdhFailed(CFError?)
}
