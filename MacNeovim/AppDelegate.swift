import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSDocumentController.shared.newDocument(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
}
