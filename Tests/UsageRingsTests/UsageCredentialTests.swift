import Foundation
import Testing
@testable import UsageRings

struct UsageCredentialTests {
    @Test func cursorCookieRejectsTokensThatCanAddHTTPHeaderContent() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let data = try JSONSerialization.data(withJSONObject: [
            "sub": "auth0|user_test", "exp": now.timeIntervalSince1970 + 600
        ])
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        for token in [
            "test.\(payload).signature; injected=bad",
            "test.\(payload).signature\r\nInjected: bad",
            "header bad.\(payload).signature",
            ".\(payload).signature",
            "test.\(payload)."
        ] {
            #expect(throws: (any Error).self) {
                try UsageCredentialReader.cursorCookie(token: token, now: now)
            }
        }
        #expect(try UsageCredentialReader.cursorCookie(token: "test.\(payload).signature", now: now)
                == "WorkosCursorSessionToken=user_test%3A%3Atest.\(payload).signature")
    }
}
