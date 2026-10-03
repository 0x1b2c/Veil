import Testing
import VeilCore

struct VeilAppleEventProtocolTests {
    @Test func deniedAutomationPointsToSettings() {
        let message = VeilAppleEventProtocol.failureMessage(forStatus: -1743)
        #expect(message.contains("System Settings > Privacy & Security > Automation"))
    }

    @Test func unrequestedAutomationPointsToSettings() {
        let message = VeilAppleEventProtocol.failureMessage(forStatus: -1744)
        #expect(message.contains("System Settings > Privacy & Security > Automation"))
    }

    @Test func otherFailuresReportTheirCode() {
        let message = VeilAppleEventProtocol.failureMessage(forStatus: -600)
        #expect(message.contains("-600"))
        #expect(!message.contains("Automation"))
    }
}
