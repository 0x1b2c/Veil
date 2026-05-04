import Foundation

private let veilAppBundleIdentifier = "org.1b2c.Veil"

@main
struct VeilCLI {
    static func main() {
        let invocationName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        let appURL = resolveAppURL()
        var arguments = Array(CommandLine.arguments.dropFirst())
        if invocationName.hasSuffix("vimdiff") {
            arguments.insert("-d", at: 0)
        }

        let binaryURL = appURL.appendingPathComponent("Contents/MacOS/Veil")
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            fputs("Cannot find Veil executable.\n", stderr)
            exit(1)
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        do {
            try process.run()
        } catch {
            fputs("Failed to launch Veil: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func resolveAppURL() -> URL {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
        let bundledAppURL = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if isVeilAppBundle(bundledAppURL) {
            return bundledAppURL
        }

        let standardAppURL = URL(fileURLWithPath: "/Applications/Veil.app")
        if isVeilAppBundle(standardAppURL) {
            return standardAppURL
        }

        if let spotlightAppURL = findAppWithSpotlight() {
            return spotlightAppURL
        }

        return bundledAppURL
    }

    private static func isVeilAppBundle(_ url: URL) -> Bool {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let info = plist as? [String: Any],
            let identifier = info["CFBundleIdentifier"] as? String
        else { return false }
        return identifier == veilAppBundleIdentifier
    }

    private static func findAppWithSpotlight() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemCFBundleIdentifier == '\(veilAppBundleIdentifier)'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.split(separator: "\n") {
            let url = URL(fileURLWithPath: String(line))
            if isVeilAppBundle(url) {
                return url
            }
        }
        return nil
    }
}
