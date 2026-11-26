import Foundation
import Sparkle
import Testing
@testable import UsageRings

struct AppUpdateControllerTests {
    @Test @MainActor func downloadReportsProgressAndInstallAnswersSparkle() {
        let updates = AppUpdateController()
        updates.showDownloadInitiated(cancellation: {})
        #expect(updates.status == .downloading(fraction: nil))
        updates.showDownloadDidReceiveExpectedContentLength(200)
        updates.showDownloadDidReceiveData(ofLength: 50)
        #expect(updates.status == .downloading(fraction: 0.25))

        var choice: SPUUserUpdateChoice?
        updates.showReady(toInstallAndRelaunch: { choice = $0 })
        #expect(updates.status == .readyToInstall)
        updates.install()
        #expect(choice == .install)
    }

    @Test @MainActor func aResultStaysReadableAfterSparkleEndsTheSession() {
        let updates = AppUpdateController()
        var acknowledged = false
        let upToDate = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "You’re up to date!"])
        updates.showUpdateNotFoundWithError(upToDate) { acknowledged = true }
        updates.dismissUpdateInstallation()
        #expect(acknowledged)
        #expect(updates.status == .message("You’re up to date!", isError: false))

        var cancelled = false
        updates.showUserInitiatedUpdateCheck(cancellation: { cancelled = true })
        #expect(updates.status == .checking)
        updates.cancel()
        updates.dismissUpdateInstallation()
        #expect(cancelled)
        #expect(updates.status == .idle)
    }
}
