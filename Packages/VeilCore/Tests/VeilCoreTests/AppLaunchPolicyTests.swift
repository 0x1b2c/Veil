import Testing
import VeilCore

struct AppLaunchPolicyTests {
    @Test func anOrdinaryLaunchBehavesAsTheApp() {
        let policy = AppLaunchPolicy(environment: ["HOME": "/Users/someone"])
        #expect(policy.forwardsToRunningInstance)
        #expect(policy.comesToFront)
        #expect(policy.opensDefaultWindow)
        #expect(policy.checksForUpdates)
        #expect(policy.showsInDock)
    }

    /// XCTest sets this variable in the host app it launches. Parallel
    /// testing launches several hosts at once; one that forwarded to
    /// another and quit would never check in, failing the whole run.
    @Test func aTestHostStaysOutOfTheWay() {
        let policy = AppLaunchPolicy(environment: [
            "XCTestConfigurationFilePath": "/tmp/Veil.xctestconfiguration"
        ])
        #expect(!policy.forwardsToRunningInstance)
        #expect(!policy.comesToFront)
        #expect(!policy.opensDefaultWindow)
        #expect(!policy.checksForUpdates)
        #expect(!policy.showsInDock)
    }

    @Test func anEmptyTestConfigurationPathStillMarksATestHost() {
        let policy = AppLaunchPolicy(environment: ["XCTestConfigurationFilePath": ""])
        #expect(!policy.forwardsToRunningInstance)
    }
}
