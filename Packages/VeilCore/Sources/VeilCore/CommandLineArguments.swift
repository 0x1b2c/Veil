import Foundation

public enum VeilRendererOption: String, Codable {
    case metal
    case coretext
}

public enum VeilCommandLine {
    public struct ParsedArguments {
        public var nvimArgs: [String] = []
        public var renderer: VeilRendererOption = .metal
        /// Remote nvim address from --connect ("host:port").
        public var remoteAddress: String?
        /// Workspace name from --workspace; pairs with --connect.
        public var workspace: String?
        /// --workspaces: list registered workspace servers and exit.
        public var listWorkspaces = false
        /// --veil-local: open on this machine even when the keyboard behind
        /// the command is on another one.
        public var forceLocal = false

        /// Whether the CLI may ask wezterm where the viewer sits and send
        /// the request to a workspace. `--connect` requests come from that
        /// flow's handler and must never recurse into it; `--veil-local`
        /// opts out of it.
        public var mayDivertToWorkspace: Bool {
            remoteAddress == nil && !forceLocal
        }

        /// Why this combination cannot be honored, nil when it can. File
        /// arguments next to --connect name paths on this machine, which
        /// mean nothing to the nvim at the remote address, so they are
        /// refused instead of silently dropped.
        public var usageError: String? {
            guard let remoteAddress, let argument = nvimArgs.first else { return nil }
            return "--connect takes no files or nvim arguments (got '\(argument)'): paths name "
                + "files on this machine, not on the nvim at \(remoteAddress); open files with "
                + "veil on the machine running that nvim"
        }
    }

    public static func parse(_ rawArgs: [String]) -> ParsedArguments {
        var result = ParsedArguments()
        var remaining = rawArgs.dropFirst()
        while let arg = remaining.popFirst() {
            if arg.hasPrefix("-NS") || arg.hasPrefix("-Apple") {
                // Cocoa launch flags often carry a value (e.g.
                // `-NSDocumentRevisionsDebugMode YES`). Only swallow the
                // next token when it looks like a value (does not start
                // with `-`); otherwise leave it for the next iteration so
                // a following flag like `--veil-renderer` is not lost.
                if let next = remaining.first, !next.hasPrefix("-") {
                    _ = remaining.popFirst()
                }
                continue
            }
            // Veil-owned flags for scriptable remote connections. Consumed
            // here so they never leak into nvimArgs; nvim has no flags with
            // these names.
            if arg == "--workspaces" {
                result.listWorkspaces = true
                continue
            }
            if arg == "--connect" || arg.hasPrefix("--connect=")
                || arg == "--workspace" || arg.hasPrefix("--workspace=")
            {
                let parts = splitFlag(arg)
                let value = parts.value ?? remaining.popFirst()
                switch parts.name {
                case "--connect": result.remoteAddress = value
                case "--workspace": result.workspace = value
                default: break
                }
                continue
            }
            if arg.hasPrefix("--veil-") {
                let parts = splitFlag(arg)
                switch parts.name {
                case "--veil-renderer":
                    let raw = parts.value ?? remaining.popFirst()
                    if let value = raw?.lowercased(),
                        let renderer = VeilRendererOption(rawValue: value)
                    {
                        result.renderer = renderer
                    }
                case "--veil-local":
                    result.forceLocal = true
                default:
                    break
                }
                continue
            }
            result.nvimArgs.append(arg)
        }
        return result
    }

    private static func splitFlag(_ arg: String) -> (name: String, value: String?) {
        guard let eqIndex = arg.firstIndex(of: "=") else { return (arg, nil) }
        let name = String(arg[..<eqIndex])
        let value = String(arg[arg.index(after: eqIndex)...])
        return (name, value)
    }
}
