import AppKit
import Foundation
import VeilCore

private let veilAppBundleIdentifier = "org.1b2c.Veil"

@main
struct VeilCLI {
    static func main() {
        if CommandLine.arguments.dropFirst().contains("--version") {
            print("Veil \(BuildVersion.displayVersion)")
            exit(0)
        }
        let invocationName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        let appURL = resolveAppURL()
        var launchArguments = Array(CommandLine.arguments.dropFirst())
        var arguments = VeilCommandLine.parse(CommandLine.arguments)
        if invocationName.hasSuffix("vimdiff") {
            launchArguments.insert("-d", at: 0)
            arguments.nvimArgs.insert("-d", at: 0)
        }

        let nvimAppName = ProcessInfo.processInfo.environment["NVIM_APPNAME"]
        let hasOpenRequest = !arguments.nvimArgs.isEmpty || nvimAppName != nil

        if let running = findRunningApp(appURL: appURL) {
            // Hot start: the CLI is the Apple Event client. This avoids
            // starting a second GUI process just to forward argv/env.
            if hasOpenRequest {
                exit(
                    sendOpenRequest(to: running, arguments: arguments, nvimAppName: nvimAppName)
                        ? 0 : 1)
            }
            running.activate(options: [.activateAllWindows])
            exit(0)
        }

        exit(launchApp(at: appURL, launchArguments: launchArguments) ? 0 : 1)
    }

    private static func resolveAppURL() -> URL {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
        let bundledAppURL =
            executable
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

    private static func findRunningApp(appURL: URL) -> NSRunningApplication? {
        let targetPath = appURL.standardizedFileURL.path
        return NSRunningApplication.runningApplications(
            withBundleIdentifier: veilAppBundleIdentifier
        )
        .first { app in
            guard !app.isTerminated else { return false }
            guard let bundleURL = app.bundleURL?.standardizedFileURL else { return false }
            return bundleURL.path == targetPath
        }
    }

    private static func launchApp(at appURL: URL, launchArguments: [String]) -> Bool {
        let binaryURL = appURL.appendingPathComponent("Contents/MacOS/Veil")
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            fputs("veil: cannot find Veil executable\n", stderr)
            return false
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = launchArguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        do {
            try process.run()
            return true
        } catch {
            fputs("veil: failed to launch Veil.app: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    private static func sendOpenRequest(
        to app: NSRunningApplication,
        arguments: VeilCommandLine.ParsedArguments,
        nvimAppName: String?
    ) -> Bool {
        let request = VeilOpenRequest(
            nvimArgs: arguments.nvimArgs,
            env: ProcessInfo.processInfo.environment,
            renderer: arguments.renderer,
            nvimAppName: nvimAppName)
        guard let data = try? JSONEncoder().encode(request),
            let json = String(data: data, encoding: .utf8)
        else {
            fputs("veil: failed to encode CLI request\n", stderr)
            return false
        }

        let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: VeilAppleEventProtocol.eventClass,
            eventID: VeilAppleEventProtocol.openEventID,
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(
            NSAppleEventDescriptor(string: json),
            forKeyword: VeilAppleEventProtocol.jsonParamKey)

        do {
            let reply = try event.sendEvent(
                options: [.waitForReply, .neverInteract],
                timeout: VeilAppleEventProtocol.replyTimeout)
            guard
                let replyJSON = reply.paramDescriptor(
                    forKeyword: VeilAppleEventProtocol.jsonParamKey)?.stringValue,
                let replyData = replyJSON.data(using: .utf8),
                let decoded = try? JSONDecoder().decode(VeilOpenReply.self, from: replyData)
            else {
                fputs("veil: Veil.app returned an invalid Apple Event reply\n", stderr)
                return false
            }
            if decoded.ok { return true }
            fputs("veil: \(decoded.message ?? "Veil.app rejected the CLI request")\n", stderr)
            return false
        } catch {
            fputs(
                "veil: failed to send Apple Event to Veil.app: \(error.localizedDescription)\n",
                stderr)
            return false
        }
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
