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
                    raw=$(git -C "$work_dir" describe --tags --dirty)
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
                    else
                        branch_tag=""
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
                outputFilesDirectory: outputDirectory
            )
        ]
    }
}
