import Foundation
import Testing
@testable import Veil

@MainActor
final class FrameGateTests {

    var gate = FrameGate()

    private let line = NvimEvent.gridLine(
        grid: 1, row: 0, colStart: 0, cells: [GridCellData(text: "x", hlId: 0, repeats: 1)])
    private let scroll = NvimEvent.gridScroll(
        grid: 1, top: 0, bottom: 3, left: 0, right: 5, rows: 1, cols: 0)

    @Test func aFlushedBatchIsRendered() {
        gate.apply(line)
        gate.apply(.flush)
        #expect(gate.shouldRender)
    }

    @Test func aBatchStillWaitingForItsFlushIsNotRenderedAfterAnEarlierFlush() {
        gate.apply(line)
        gate.apply(.flush)
        // The display link has not fired yet when the next batch starts arriving.
        gate.apply(scroll)
        #expect(!gate.shouldRender)
        gate.apply(line)
        gate.apply(.flush)
        #expect(gate.shouldRender)
    }

    @Test func aVeilRedrawDuringAnUnflushedBatchWaitsForTheFlush() {
        gate.apply(scroll)
        gate.requestRender()
        #expect(!gate.shouldRender)
        gate.apply(line)
        gate.apply(.flush)
        #expect(gate.shouldRender)
    }

    @Test func aVeilRedrawBetweenBatchesRendersImmediately() {
        gate.apply(line)
        gate.apply(.flush)
        gate.frameRendered(presented: true)
        #expect(!gate.shouldRender)
        gate.requestRender()
        #expect(gate.shouldRender)
    }

    @Test func aVeilRedrawBeforeNvimSendsAnythingRendersImmediately() {
        gate.requestRender()
        #expect(gate.shouldRender)
    }

    @Test func eventsOutsideTheRedrawCycleDoNotHoldBackRendering() {
        gate.requestRender()
        gate.apply(.veilBufChanged)
        gate.apply(.setTitle(title: "x"))
        gate.apply(.tablineUpdate(current: 1, tabs: []))
        #expect(gate.shouldRender)
    }

    @Test func aFrameThatWasNotPresentedIsRetried() {
        gate.apply(line)
        gate.apply(.flush)
        gate.frameRendered(presented: false)
        #expect(gate.shouldRender)
        gate.frameRendered(presented: true)
        #expect(!gate.shouldRender)
    }
}
