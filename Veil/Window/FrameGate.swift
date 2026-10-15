import Foundation

/// Decides when the grid may be put on screen.
///
/// Neovim splits one screen update into redraw events that can span several
/// RPC notifications, and only the `flush` event marks the grid as a complete
/// state (`:help ui-events`). Rendering in between shows a half-applied update,
/// such as a region already scrolled but not yet refilled. The gate therefore
/// holds back every render request, including Veil's own redraws, while a
/// batch of grid events has started and its `flush` has not arrived yet.
struct FrameGate {
    /// A render has been requested and not yet presented.
    private(set) var needsRender = false

    /// Grid events have been applied since the last `flush`.
    private(set) var awaitingFlush = false

    var shouldRender: Bool { needsRender && !awaitingFlush }

    mutating func apply(_ event: NvimEvent) {
        switch event {
        case .flush:
            awaitingFlush = false
            needsRender = true
        case .gridResize, .gridLine, .gridClear, .gridCursorGoto, .gridScroll,
            .hlAttrDefine, .defaultColorsSet, .modeChange:
            awaitingFlush = true
        default:
            break
        }
    }

    /// A redraw that Veil initiates itself (window focus, debug overlay).
    mutating func requestRender() {
        needsRender = true
    }

    /// A frame that was not presented stays requested, so the next vsync retries it.
    mutating func frameRendered(presented: Bool) {
        needsRender = !presented
    }
}
