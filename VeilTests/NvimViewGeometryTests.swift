import AppKit
import Testing
@testable import Veil

@MainActor
struct NvimViewGeometryTests {

    let view = NvimView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

    /// The view-space y of the bottom edge of `row`, as the renderers place
    /// it: rows start below the top padding and stack downward.
    private func bottomEdge(ofRow row: Int) -> CGFloat {
        view.bounds.height - NvimView.gridTopPadding - CGFloat(row + 1) * view.cellSize.height
    }

    @Test func aPointNearTheBottomOfARowMapsToThatRow() {
        for row in [0, 1, 5] {
            let point = NSPoint(x: 1, y: bottomEdge(ofRow: row) + 1)
            #expect(view.gridPosition(for: point).row == row)
        }
    }

    @Test func aPointNearTheTopOfARowMapsToThatRow() {
        for row in [0, 1, 5] {
            let point = NSPoint(x: 1, y: bottomEdge(ofRow: row) + view.cellSize.height - 1)
            #expect(view.gridPosition(for: point).row == row)
        }
    }

    @Test func aPointInTheTopPaddingMapsToTheFirstRow() {
        let point = NSPoint(x: 1, y: view.bounds.height - 1)
        #expect(view.gridPosition(for: point).row == 0)
    }

    @Test func aPointBeyondTheGridMapsToTheLastRowAndColumn() {
        let size = view.gridSizeForViewSize(view.bounds.size)
        let point = NSPoint(x: view.bounds.width + 50, y: -50)
        #expect(view.gridPosition(for: point) == Position(row: size.rows - 1, col: size.cols - 1))
    }

    @Test func columnsFollowTheCellWidth() {
        let point = NSPoint(x: view.cellSize.width * 3 + 1, y: bottomEdge(ofRow: 0) + 1)
        #expect(view.gridPosition(for: point).col == 3)
    }
}
