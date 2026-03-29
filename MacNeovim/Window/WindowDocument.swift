import AppKit
import MessagePack

class WindowDocument: NSDocument {
    var profile = Profile.default

    private var channel: NvimChannel!
    private let grid = Grid()
    private var eventLoopTask: Task<Void, Never>?

    private var nvimView: NvimView? {
        (windowControllers.first as? WindowController)?.nvimView
    }

    override init() {
        super.init()
        self.channel = NvimChannel()
    }

    override func makeWindowControllers() {
        let controller = WindowController()
        controller.nvimView.channel = channel
        addWindowController(controller)
        Task { await startNvim() }
    }

    nonisolated override class var autosavesInPlace: Bool { false }
    override func data(ofType typeName: String) throws -> Data { Data() }
    nonisolated override func read(from data: Data, ofType typeName: String) throws {}

    private func startNvim() async {
        do {
            try await channel.start(nvimPath: "", cwd: NSHomeDirectory(), appName: profile.name)
            guard let nvimView else { return }
            let gridSize = nvimView.gridSizeForViewSize(nvimView.bounds.size)
            try await channel.uiAttach(width: gridSize.cols, height: gridSize.rows)
            startEventLoop()
        } catch {
            NSAlert(error: error).runModal()
            close()
        }
    }

    private func startEventLoop() {
        eventLoopTask = Task { @MainActor in
            let events = channel.events
            for await event in events {
                grid.apply(event)
                switch event {
                case .flush:
                    nvimView?.render(grid: grid)
                    grid.clearDirty()
                case .setTitle(let title):
                    windowControllers.first?.window?.title = title
                case .defaultColorsSet(let fg, let bg, _, _, _):
                    nvimView?.setDefaultColors(fg: fg, bg: bg)
                case .modeInfoSet(_, let modes):
                    nvimView?.updateModeInfo(modes)
                case .modeChange(_, let index):
                    nvimView?.updateCursorMode(index)
                case .bell:
                    NSSound.beep()
                default:
                    break
                }
            }
            close()
        }
    }

    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        Task {
            try? await channel.command("qa!")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
        }
    }

    override func close() {
        eventLoopTask?.cancel()
        Task { await channel.stop() }
        super.close()
    }

    func windowDidResize(to size: NSSize) {
        guard let nvimView else { return }
        let gridSize = nvimView.gridSizeForViewSize(size)
        guard gridSize.rows > 0, gridSize.cols > 0 else { return }
        Task { await channel.uiTryResize(width: gridSize.cols, height: gridSize.rows) }
    }
}
