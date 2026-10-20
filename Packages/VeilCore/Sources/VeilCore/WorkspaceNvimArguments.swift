import Foundation

/// Carries a `veil` invocation's nvim arguments over to a workspace nvim
/// that is already running.
///
/// Locally those arguments go to a fresh nvim's command line. A workspace
/// server was started long before, so the files and the few arguments that
/// still mean something afterwards are translated into ex commands and
/// evaluated on the server in one `nvim --server <addr> --remote-expr`
/// call. `--remote` cannot do this: it treats every argument, `-d` and
/// `+10` included, as a file name to open.
///
/// Three arguments are translated: `+cmd` runs `cmd` once the files are
/// open, `-R` marks every given file read-only, and `-d` opens the files
/// side by side in diff mode in a new tab, as `nvim -d` lays them out.
/// Every other option only takes effect while nvim starts (`-u`, `-i`,
/// `--clean`, ...) or is not translated, and is refused rather than
/// silently dropped.
///
/// Only opening the files has to succeed. As with a local `nvim +cmd`, a
/// command that fails afterwards does not undo the open or stop the
/// commands after it: each failure is recorded in nvim's message history
/// and returned in the reply, one `<command>: <error>` per line.
///
/// A file whose swap file was left by an nvim that ended abnormally does
/// not fail the open. A local nvim would ask whether to recover it, but
/// the server has no one to ask, so the file opens read-only, the swap
/// file is kept, and the reply carries a line suggesting `:recover`. A
/// choice nvim already made for the swap file (for one an nvim still
/// running holds, it edits anyway with a warning) is left as it is.
public enum WorkspaceNvimArguments {
    public struct UnsupportedArgument: Error, Equatable {
        public var argument: String

        public init(argument: String) {
            self.argument = argument
        }

        public var message: String {
            "'\(argument)' cannot be applied to a workspace: files are sent to an nvim that is "
                + "already running, and only +cmd, -R and -d can be translated for it"
        }
    }

    /// The Vimscript expression that opens the files and applies the
    /// arguments on the server, or nil when there is nothing to send.
    /// Relative paths resolve against `cwd`, the directory `veil` ran in,
    /// since the server's own working directory may differ.
    public static func remoteExpression(
        for nvimArgs: [String], cwd: String
    ) throws(UnsupportedArgument) -> String? {
        let request = try parse(nvimArgs, cwd: cwd)
        var commands = request.openCommands() + request.readonlyCommands() + request.userCommands()
        guard !commands.isEmpty else { return nil }
        let open = request.files.isEmpty ? "''" : commands.removeFirst()
        return "luaeval(" + vimLiteral(openThenRunEach) + ", [" + open + ", ["
            + commands.joined(separator: ", ") + "]])"
    }

    /// The lines of a reply to `remoteExpression`: each failed command as
    /// `<command>: <error>`, after a line for each file opened read-only
    /// because of a swap file.
    public static func commandFailures(inReply reply: String) -> [String] {
        reply.split(separator: "\n").map(String.init)
    }

    /// Takes `[open, cmds]` in `_A`. Runs `open` (skipped when empty),
    /// whose error fails the whole call, then each ex command in `cmds` on
    /// its own, so one failure leaves the rest to run. Throughout, a swap
    /// file nvim has not decided on opens its file read-only and is noted.
    /// Returns the notes and failures joined by newlines.
    private static let openThenRunEach = """
        (function(a) local open, cmds = a[1], a[2] local lines = {} \
        local group = vim.api.nvim_create_augroup("veil_workspace_swap", {clear = true}) \
        vim.api.nvim_create_autocmd("SwapExists", {group = group, callback = function(ev) \
        if vim.v.swapchoice ~= "" then return end \
        vim.v.swapchoice = "o" \
        table.insert(lines, ev.file .. ": opened read-only, a swap file was left by an " \
        .. "nvim that ended abnormally; run :recover in it to restore unsaved changes") \
        end}) \
        if open ~= "" then \
        local ok, err = pcall(vim.cmd, open) \
        if not ok then vim.api.nvim_del_augroup_by_id(group) error(err, 0) end \
        end \
        for _, cmd in ipairs(cmds) do \
        local ok, err = pcall(vim.cmd, cmd) \
        if not ok then \
        local line = cmd .. ": " .. (tostring(err):match("E%d+:.*") or tostring(err)) \
        table.insert(lines, line) \
        vim.api.nvim_echo({{line, "ErrorMsg"}}, true, {}) \
        end end \
        vim.api.nvim_del_augroup_by_id(group) \
        return table.concat(lines, "\\n") end)(_A)
        """

    private struct Request {
        var files: [String] = []
        /// `+cmd` arguments with the `+` removed, in the order given.
        var commands: [String] = []
        var readonly = false
        var diff = false

        /// Each element is a Vimscript expression yielding one ex command.
        /// File names pass through the server's own `fnameescape()`.
        func openCommands() -> [String] {
            guard let first = files.first else { return [] }
            guard diff else {
                return ["'drop' .. " + files.map(escapedArgument).joined(separator: " .. ")]
            }
            if files.count == 1 {
                return [Self.diffTab + " .. " + escapedArgument(first), vimLiteral("diffthis")]
            }
            // Splitting to the right of the first file in reverse order, and
            // returning to it after each split, leaves the windows in
            // argument order with the cursor in the first, as `nvim -d` does.
            return [Self.diffTab + " .. " + escapedArgument(first)]
                + files.dropFirst().reversed().flatMap { file in
                    [
                        "'belowright vertical diffsplit' .. " + escapedArgument(file),
                        vimLiteral("wincmd p"),
                    ]
                }
        }

        /// `drop` only places the second and later files in the argument
        /// list, and loading a buffer resets its 'readonly' from the file's
        /// permissions, so each file is loaded before the flag is set.
        func readonlyCommands() -> [String] {
            guard readonly else { return [] }
            return files.map { file in
                let buffer = "bufadd(\(vimLiteral(file)))"
                return vimLiteral(
                    "call bufload(\(buffer)) | call setbufvar(\(buffer), '&readonly', 1)")
            }
        }

        /// The command that opens the first diff file: always a tab of its
        /// own, so the diff never joins windows the user already has, even
        /// when that file is on screen. Only the untouched empty tab of a
        /// fresh server is reused, which a new tab would leave behind.
        private static let diffTab =
            "(tabpagenr('$') == 1 && winnr('$') == 1 && bufname('') == '' && !&modified "
            + "&& line('$') == 1 && getline(1) == '' ? 'edit' : 'tabedit')"

        func userCommands() -> [String] {
            commands.map(vimLiteral)
        }

        private func escapedArgument(_ file: String) -> String {
            "' ' .. fnameescape(\(vimLiteral(file)))"
        }
    }

    private static func parse(
        _ nvimArgs: [String], cwd: String
    ) throws(UnsupportedArgument) -> Request {
        var request = Request()
        var optionsEnded = false
        for arg in nvimArgs {
            if optionsEnded || !(arg.hasPrefix("-") || arg.hasPrefix("+")) {
                request.files.append(arg.hasPrefix("/") ? arg : cwd + "/" + arg)
                continue
            }
            switch arg {
            case "--": optionsEnded = true
            case "-R": request.readonly = true
            case "-d": request.diff = true
            case _ where arg.hasPrefix("+"):
                // A bare `+` means the last line, as it does for nvim.
                let command = String(arg.dropFirst())
                request.commands.append(command.isEmpty ? "$" : command)
            default:
                throw UnsupportedArgument(argument: arg)
            }
        }
        return request
    }

    /// A single-quoted Vimscript string literal: inside one, only `'`
    /// needs escaping, by doubling it.
    private static func vimLiteral(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
    }
}
