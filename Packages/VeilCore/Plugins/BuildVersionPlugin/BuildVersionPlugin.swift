import Foundation
import PackagePlugin

@main
struct BuildVersionPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        let outputDirectory = context.pluginWorkDirectoryURL
        let outputFile = outputDirectory.appending(path: "BuildVersion.swift")
        let workDir = context.package.directoryURL.path
        // SwiftPM prebuild commands run with an empty environment by default,
        // so VEIL_BUILD_VERSION must be forwarded explicitly for the fallback
        // path to see it.
        var environment: [String: String] = [:]
        if let fallback = ProcessInfo.processInfo.environment["VEIL_BUILD_VERSION"] {
            environment["VEIL_BUILD_VERSION"] = fallback
        }
        // Prebuild ensures the script runs every build. Git state can shift
        // (new commits, dirty worktree, branch switch) without any tracked
        // source file changing, so a dependency-based buildCommand would
        // skip regeneration.
        return [
            .prebuildCommand(
                displayName: "Generate BuildVersion.swift from git describe",
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c",
                    """
                    set -eu
                    work_dir="\(workDir)"
                    output="\(outputFile.path)"
                    branch_tag=""
                    if raw=$(git -C "$work_dir" describe --tags --dirty 2>/dev/null); then
                        raw="${raw#v}"
                        case "$raw" in
                          *-*-g*)
                            tag="${raw%%-*}"
                            hash="${raw#*-*-g}"
                            version="${tag}+${hash}"
                            ;;
                          *)
                            version="$raw"
                            ;;
                        esac
                        branch=$(git -C "$work_dir" branch --show-current)
                        if [ -n "$branch" ] && [ "$branch" != "master" ]; then
                            branch_tag=" [$branch]"
                        fi
                    elif [ -n "${VEIL_BUILD_VERSION:-}" ]; then
                        version="${VEIL_BUILD_VERSION#v}"
                    else
                        echo "BuildVersionPlugin: git describe failed and VEIL_BUILD_VERSION is unset." >&2
                        echo "Set VEIL_BUILD_VERSION (e.g. VEIL_BUILD_VERSION=0.7.0) to build outside a tagged git checkout." >&2
                        exit 1
                    fi
                    cat > "$output" <<SWIFT
                    public enum BuildVersion {
                        /// SemVer 2.0 with build metadata: "<tag>+<hash>[-dirty]".
                        /// Examples: "0.6.3", "0.6.3+21b9326", "0.6.3+21b9326-dirty".
                        /// Strip "+..." for tag comparison.
                        public static let version = "$version"

                        /// "v" + version + optional branch tag (omitted on master).
                        /// Ready to drop into any UI display context. No build timestamp,
                        /// so this string only changes when git state changes, keeping
                        /// incremental builds fast.
                        public static let displayVersion = "v$version$branch_tag"
                    }
                    SWIFT
                    """,
                ],
                environment: environment,
                outputFilesDirectory: outputDirectory
            )
        ]
    }
}
