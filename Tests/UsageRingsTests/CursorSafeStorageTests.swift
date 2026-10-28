import Foundation
import Security
import Testing
@testable import UsageRings

struct CursorSafeStorageTests {
    // Generated independently with OpenSSL using Chromium's macOS v10 parameters.
    private let encrypted = "cursor-safe-storage:v1:djEwS82Gfco4lW9pZmw5YYhY4R+ZIm+YYpHIJ0ocyHAFqr8="
    private let password = Data("ato-synthetic-safe-storage-test".utf8)

    @Test func decodesChromiumCiphertextWithAnIndependentFixture() throws {
        let token = try CursorSafeStorage.decode(encrypted, readPassword: { password })
        #expect(token == "test.payload.signature")
    }

    @Test func plaintextSessionsDoNotReadKeychain() throws {
        var reads = 0
        let token = try CursorSafeStorage.decode("test.payload.signature", readPassword: {
            reads += 1
            throw CursorSafeStorage.Failure.keyUnavailable
        })
        #expect(token == "test.payload.signature")
        #expect(reads == 0)
    }

    @Test func malformedOrUnknownEncryptedFormatsNeverRequestAKey() {
        for stored in [
            "cursor-safe-storage:v2:anything",
            "cursor-safe-storage:v1:not base64!",
            "cursor-safe-storage:v1:",
            "cursor-safe-storage:v1:" + Data("v11".utf8).base64EncodedString(),
            "cursor-safe-storage:v1:" + Data("v10short".utf8).base64EncodedString(),
            "cursor-safe-storage:v1:" + String(repeating: "A", count: 65_536)
        ] {
            var reads = 0
            #expect(throws: CursorSafeStorage.Failure.invalidCiphertext) {
                try CursorSafeStorage.decode(stored, readPassword: {
                    reads += 1
                    return password
                })
            }
            #expect(reads == 0)
        }
    }

    @Test func deniedPermissionIsNotRetriedOrReportedAsAnExpiredSession() {
        var reads = 0
        #expect(throws: CursorSafeStorage.Failure.permissionRequired) {
            try CursorSafeStorage.decode(encrypted, readPassword: {
                reads += 1
                throw CursorSafeStorage.Failure.permissionRequired
            })
        }
        #expect(reads == 1)
    }

    @Test func wrongOrMissingKeysDoNotYieldAUsableToken() {
        #expect(throws: CursorSafeStorage.Failure.invalidCiphertext) {
            try CursorSafeStorage.decode(encrypted, readPassword: { Data("wrong-key".utf8) })
        }
        for invalid in [Data(), Data(repeating: 1, count: 4097)] {
            #expect(throws: CursorSafeStorage.Failure.keyUnavailable) {
                try CursorSafeStorage.decode(encrypted, readPassword: { invalid })
            }
        }
    }

    @Test func keychainQueriesAreLimitedToTheCursorEncryptionItem() {
        for allowsInteraction in [false, true] {
            let query = CursorSafeStorage.keychainQuery(allowingInteraction: allowsInteraction)
            #expect(query[kSecAttrService as String] as? String == "Cursor Safe Storage")
            #expect(query[kSecAttrAccount as String] as? String == "Cursor")
            #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
            #expect(query[kSecReturnData as String] as? Bool == true)
            #expect(query[kSecUseAuthenticationUI as String] as? String ==
                    (allowsInteraction ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail) as String)
        }
    }
}
