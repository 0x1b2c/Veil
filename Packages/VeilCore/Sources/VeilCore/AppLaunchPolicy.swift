import Foundation

/// What Veil does as it finishes launching, which depends on whether it was
/// launched as an app or as the host of an XCTest run.
///
/// A test host must stay out of the way. Parallel testing launches several
/// hosts at once, and one that found another running would forward to it
/// and quit before checking in, failing the run. A host that came to the
/// front or opened a window would also take focus from whatever the user
/// is doing each time the tests run.
public struct AppLaunchPolicy: Equatable {
    /// Hand the launch over to an already running Veil and quit.
    public let forwardsToRunningInstance: Bool
    /// Activate the app, taking focus.
    public let comesToFront: Bool
    /// Open a window when nothing else asked for one.
    public let opensDefaultWindow: Bool
    public let checksForUpdates: Bool
    public let showsInDock: Bool

    /// XCTest sets `XCTestConfigurationFilePath` in the environment of every
    /// host app it launches; an app launched any other way lacks it.
    public init(environment: [String: String]) {
        let isTestHost = environment["XCTestConfigurationFilePath"] != nil
        forwardsToRunningInstance = !isTestHost
        comesToFront = !isTestHost
        opensDefaultWindow = !isTestHost
        checksForUpdates = !isTestHost
        showsInDock = !isTestHost
    }
}
