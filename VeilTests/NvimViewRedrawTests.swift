import AppKit
import Testing
@testable import Veil

@MainActor
struct NvimViewRedrawTests {

    private final class RedrawSpy: NvimViewDelegate {
        var requests = 0
        func nvimViewNeedsDisplay(_ view: NvimView) { requests += 1 }
    }

    @Test(
        "Moving the window to a display with another scale redraws at once, without waiting for Neovim"
    )
    func backingScaleChangeRequestsARedraw() {
        let view = NvimView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let spy = RedrawSpy()
        view.delegate = spy

        view.viewDidChangeBackingProperties()

        #expect(spy.requests == 1)
    }
}
