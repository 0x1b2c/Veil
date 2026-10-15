import Foundation

/// How a workspace, identified by its project root, is named to the user
/// and on disk.
public enum WorkspaceRoot {
    /// Shown in the window title while the viewer connects and in the
    /// CLI's messages: the root's directory name, or `~` for the default
    /// workspace rooted at `home`. Spelling that one out as "home" would
    /// give it the same title as a repository called `home`.
    public static func name(of root: String, home: String) -> String {
        root == home ? "~" : URL(fileURLWithPath: root).lastPathComponent
    }

    /// The server's log file, unique per root: the whole path with `/`
    /// turned into `%`, the way Vim names swap and undo files, so two
    /// repositories with the same directory name never share a log.
    public static func logFileName(of root: String) -> String {
        root.replacingOccurrences(of: "/", with: "%") + ".log"
    }
}
