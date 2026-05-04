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
        var iterator = rawArgs.dropFirst().makeIterator()
        while let arg = iterator.next() {
            if arg.hasPrefix("-NS") || arg.hasPrefix("-Apple") {
                _ = iterator.next()
                continue
            }
            if arg.hasPrefix("--veil-") {
                let parts = splitFlag(arg)
                switch parts.name {
                case "--veil-renderer":
                    let value = (parts.value ?? iterator.next())?.lowercased()
                    if let value, let renderer = VeilRendererOption(rawValue: value) {
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
