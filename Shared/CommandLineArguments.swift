import Foundation

enum VeilRendererOption: String {
    case metal
    case coretext
}

enum VeilCommandLine {
    struct ParsedArguments {
        var nvimArgs: [String] = []
        var renderer: VeilRendererOption = .metal
    }

    static func parse(_ rawArgs: [String]) -> ParsedArguments {
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
