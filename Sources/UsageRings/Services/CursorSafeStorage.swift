import CommonCrypto
import Foundation
import Security

enum CursorSafeStorage {
    enum Failure: Error, Equatable {
        case permissionRequired, invalidCiphertext, keyUnavailable
    }

    private static let prefix = "cursor-safe-storage:v1:"
    private static let liveKeyCache = KeyCache()

    static func decode(_ stored: String, allowingInteraction: Bool = false) throws -> String {
        guard let ciphertext = try ciphertext(in: stored) else { return stored }
        liveKeyCache.lock.lock()
        defer { liveKeyCache.lock.unlock() }
        if let key = liveKeyCache.key {
            do {
                return try decrypt(ciphertext, key: key)
            } catch {
                liveKeyCache.key = nil
                throw error
            }
        }
        var password = try readPassword(allowingInteraction: allowingInteraction)
        defer { password.resetBytes(in: 0..<password.count) }
        let key = try deriveKey(password)
        let plaintext = try decrypt(ciphertext, key: key)
        // A one-time macOS grant must also cover later silent polls in this process.
        liveKeyCache.key = key
        return plaintext
    }

    static func decode(_ stored: String, readPassword: () throws -> Data) throws -> String {
        guard let ciphertext = try ciphertext(in: stored) else { return stored }
        var password = try readPassword()
        defer { password.resetBytes(in: 0..<password.count) }
        return try decrypt(ciphertext, key: deriveKey(password))
    }

    static func keychainQuery(allowingInteraction: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Cursor Safe Storage",
            kSecAttrAccount as String: "Cursor",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationUI as String: allowingInteraction
                ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        ]
    }

    private static func readPassword(allowingInteraction: Bool) throws -> Data {
        var result: CFTypeRef?
        let query = keychainQuery(allowingInteraction: allowingInteraction) as CFDictionary
        let status: OSStatus
        if allowingInteraction {
            status = SecItemCopyMatching(query, &result)
        } else {
            // Cursor uses the legacy keychain, whose ACL prompts ignore the query's UI policy.
            var previous: DarwinBoolean = false
            guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
                  SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else {
                throw Failure.keyUnavailable
            }
            var restored = false
            do {
                defer { restored = SecKeychainSetUserInteractionAllowed(previous.boolValue) == errSecSuccess }
                status = SecItemCopyMatching(query, &result)
            }
            guard restored else { throw Failure.keyUnavailable }
        }
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, !data.isEmpty, data.count <= 4096 else {
                throw Failure.keyUnavailable
            }
            return data
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw Failure.permissionRequired
        default:
            throw Failure.keyUnavailable
        }
    }

    private static func ciphertext(in stored: String) throws -> Data? {
        guard stored.hasPrefix("cursor-safe-storage:") else { return nil }
        guard stored.hasPrefix(prefix), stored.utf8.count <= 65_536,
              let encrypted = Data(base64Encoded: String(stored.dropFirst(prefix.count))),
              encrypted.starts(with: Data("v10".utf8)) else { throw Failure.invalidCiphertext }
        let ciphertext = Data(encrypted.dropFirst(3))
        guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: kCCBlockSizeAES128) else {
            throw Failure.invalidCiphertext
        }
        return ciphertext
    }

    private static func deriveKey(_ password: Data) throws -> [UInt8] {
        guard !password.isEmpty, password.count <= 4096 else { throw Failure.keyUnavailable }
        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        // These parameters are Chromium's macOS v10 format, not new encryption choices.
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBufferPointer { saltBytes in
                key.withUnsafeMutableBufferPointer { keyBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                        passwordBytes.baseAddress!.assumingMemoryBound(to: CChar.self), password.count,
                                        saltBytes.baseAddress!, salt.count,
                                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                        keyBytes.baseAddress!, kCCKeySizeAES128)
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.keyUnavailable }
        return key
    }

    private static func decrypt(_ ciphertext: Data, key: [UInt8]) throws -> String {
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var plaintext = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let capacity = plaintext.count
        var written = 0
        let status = key.withUnsafeBufferPointer { keyBytes in
            iv.withUnsafeBufferPointer { ivBytes in
                ciphertext.withUnsafeBytes { ciphertextBytes in
                    plaintext.withUnsafeMutableBytes { plaintextBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding), keyBytes.baseAddress!, key.count,
                                ivBytes.baseAddress!, ciphertextBytes.baseAddress!, ciphertext.count,
                                plaintextBytes.baseAddress!, capacity, &written)
                    }
                }
            }
        }
        defer { plaintext.resetBytes(in: 0..<plaintext.count) }
        guard status == kCCSuccess,
              let result = String(data: plaintext.prefix(written), encoding: .utf8), !result.isEmpty else {
            throw Failure.invalidCiphertext
        }
        return result
    }

    private final class KeyCache: @unchecked Sendable {
        let lock = NSLock()
        var key: [UInt8]?
    }
}
