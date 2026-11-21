import Foundation
import Security

enum ProviderKeychain {
    private static let lock = NSLock()

    static func read(_ query: CFDictionary, allowingInteraction: Bool) -> (OSStatus, Data?) {
        lock.withLock {
            var result: CFTypeRef?
            if allowingInteraction {
                return (SecItemCopyMatching(query, &result), result as? Data)
            }
            // Legacy Keychain ACLs can prompt even when the query disables interaction.
            var previous: DarwinBoolean = false
            guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
                  SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else {
                return (errSecNotAvailable, nil)
            }
            let status = SecItemCopyMatching(query, &result)
            guard SecKeychainSetUserInteractionAllowed(previous.boolValue) == errSecSuccess else {
                return (errSecNotAvailable, nil)
            }
            return (status, result as? Data)
        }
    }
}
