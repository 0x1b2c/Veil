import Foundation

/// Bundle-loaded Lua source executed once per nvim attach to register Veil's
/// augroup, autocmds, user commands, and (in remote mode) clipboard provider.
enum NvimSetupScript {
    static let lua: String = {
        guard let url = Bundle.main.url(forResource: "nvim-setup", withExtension: "lua"),
            let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            fatalError("nvim-setup.lua missing from bundle")
        }
        return content
    }()
}
