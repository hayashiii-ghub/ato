import CryptoKit
import Foundation

// Verification needs only the bundled public key; it never reads a keychain
// account or a private signing key.
let arguments = CommandLine.arguments
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
guard arguments.count == 4,
      let keyBytes = Data(base64Encoded: arguments[1]), keyBytes.count == 32,
      let signature = Data(base64Encoded: arguments[2]), signature.count == 64 else {
    fail("Invalid Sparkle verification input.")
}
do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
    let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[3]))
    guard key.isValidSignature(signature, for: archive) else {
        fail("Sparkle update signature does not match the bundled public key.")
    }
} catch {
    fail("Could not verify the Sparkle update signature.")
}
