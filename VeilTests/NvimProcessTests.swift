import Foundation
import Testing

@testable import Veil

/// The login shell capture passes `+m` to disable job control, which POSIX
/// shells accept and fish rejects: fish reads `+m` as a script path, exits
/// before printing the marker, and the capture falls back to launchd's
/// minimal PATH. The flag is therefore chosen from the shell's name.
struct NvimProcessTests {
    @Test func posixShellsGetTheJobControlFlag() {
        #expect(NvimProcess.jobControlFlag(forShellPath: "/bin/zsh") == ["+m"])
        #expect(NvimProcess.jobControlFlag(forShellPath: "/bin/bash") == ["+m"])
        #expect(NvimProcess.jobControlFlag(forShellPath: "/bin/ksh") == ["+m"])
        #expect(NvimProcess.jobControlFlag(forShellPath: "/bin/dash") == ["+m"])
    }

    @Test func fishDoesNotGetTheJobControlFlag() {
        #expect(NvimProcess.jobControlFlag(forShellPath: "/opt/homebrew/bin/fish") == [])
        #expect(NvimProcess.jobControlFlag(forShellPath: "/usr/local/bin/fish") == [])
    }

    @Test func theFlagFollowsTheBinaryNameNotTheDirectory() {
        #expect(NvimProcess.jobControlFlag(forShellPath: "/Users/someone/fish/bin/zsh") == ["+m"])
        #expect(NvimProcess.jobControlFlag(forShellPath: "/Users/someone/zsh/bin/fish") == [])
    }
}
