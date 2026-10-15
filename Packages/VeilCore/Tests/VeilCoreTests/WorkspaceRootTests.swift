import Testing
import VeilCore

struct WorkspaceRootTests {
    private let home = "/Users/x"

    @Test func homeWorkspaceAndARepositoryCalledHomeHaveDistinctNames() {
        #expect(
            WorkspaceRoot.name(of: home, home: home)
                != WorkspaceRoot.name(of: "/Users/x/home", home: home))
    }

    @Test func homeWorkspaceIsCalledTilde() {
        #expect(WorkspaceRoot.name(of: home, home: home) == "~")
    }

    @Test func repositoryIsCalledByItsDirectory() {
        #expect(WorkspaceRoot.name(of: "/Users/x/devel/proj", home: home) == "proj")
    }

    @Test func everyRootWritesItsOwnLog() {
        let roots = [home, "/Users/x/home", "/Users/x/a/proj", "/Users/x/b/proj"]
        let logs = Set(roots.map(WorkspaceRoot.logFileName(of:)))
        #expect(logs.count == roots.count)
    }

    @Test func logIsNamedAfterTheWholePathTheWayVimNamesSwapFiles() {
        #expect(WorkspaceRoot.logFileName(of: "/Users/x/home") == "%Users%x%home.log")
    }
}
