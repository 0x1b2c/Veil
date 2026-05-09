import AppKit
import CoreVideo
import MessagePack
import VeilCore

class WindowDocument: NSDocument, NvimViewDelegate {
    var profile = Profile.default
    var nvimArgs: [String] = []
    var nvimEnv: [String: String]?
    var preferredRenderer: NvimView.Renderer = .metal
    /// When true, this document is connected to a remote nvim over TCP.
    /// Closing a remote document disconnects without sending `:qa`.
    var isRemote = false
    /// Address for remote connections (e.g. "192.168.1.100:6666").
    var remoteAddress: String?

    var channel: NvimChannel!
    private let grid = Grid()
    private var eventLoopTask: Task<Void, Never>?
    // Window title strategy:
    //
    // We enable `set title` so nvim sends `set_title` events with its titlestring
    // (e.g. "init.lua (~/.config/nvim/lua/plugins) - Nvim"). However, `set title`
    // fires immediately when enabled, producing an ugly title from whatever buffer
    // is current at startup (e.g. Startify's "filetype-match-scratch...").
    //
    // To avoid this, we register BufEnter/TabEnter autocmds BEFORE enabling
    // `set title`. Since autocmds don't fire retroactively for the initial buffer,
    // the first BufEnter only arrives when the user actually switches buffers.
    // We use `titleReady` as a one-time gate: false at startup to suppress the
    // initial ugly set_title, flipped to true on first BufEnter, then stays true
    // forever, so all subsequent set_title events are displayed normally.
    //
    // Exception: when nvimArgs is non-empty (files passed via CLI or Finder Open
    // With), nvim opens the file directly without Startify, so the initial
    // set_title is already the correct filename. In this case titleReady starts
    // as true to avoid suppressing it.
    private var titleReady = false

    /// Frame coalescing: set true on flush, cleared after render.
    /// CVDisplayLink fires at screen refresh rate and only renders when dirty,
    /// preventing main-thread vsync stalls when nvim flushes faster than 60fps.
    private var needsRender = false
    private var displayLink: CVDisplayLink?
    private var displayLinkContext: Unmanaged<DisplayLinkContext>?

    private var windowController: WindowController? {
        windowControllers.first as? WindowController
    }

    private var nvimView: NvimView? {
        windowController?.nvimView
    }

    override init() {
        super.init()
        self.channel = NvimChannel()
    }

    override var displayName: String! {
        get { "Veil" }
        set {}
    }

    override func makeWindowControllers() {
        let controller = WindowController()
        controller.nvimView.preferredRenderer = preferredRenderer
        controller.nvimView.setupLayers()
        controller.nvimView.delegate = self
        controller.nvimView.channel = channel
        addWindowController(controller)
        if isRemote, let remoteAddress {
            Task { await startRemoteNvim(address: remoteAddress) }
        } else {
            Task { await startNvim() }
        }
    }

    nonisolated override class var autosavesInPlace: Bool { false }
    override func data(ofType typeName: String) throws -> Data { Data() }
    nonisolated override func read(from data: Data, ofType typeName: String) throws {}

    private func startRemoteNvim(address: String) async {
        // Remote nvim has already booted before we attached, so there is no
        // initial set_title to suppress (unlike startNvim, which keeps
        // titleReady false until the BufEnter autocmd fires).
        titleReady = true
        do {
            let (host, port) = try Self.parseAddress(address)
            try await channel.connectRemote(host: host, port: port)
            guard let nvimView else { return }
            let gridSize = nvimView.gridSizeForViewSize(nvimView.bounds.size)
            try await channel.uiAttach(
                width: gridSize.cols, height: gridSize.rows,
                nativeTabs: VeilConfig.current.native_tabs)
            startEventLoop()
            await setupNvimIntegration()
            nvimView.remoteAddress = address
            windowController?.updateTitle("Veil [remote: \(address)]")
            try? await channel.command("set title")
        } catch {
            presentStartupError(error)
        }
    }

    /// Parse "host:port" (or "tcp://host:port") into components.
    /// Uses URL parsing which handles IPv4, IPv6 bracket notation, and scheme URLs.
    private static func parseAddress(_ input: String) throws -> (host: String, port: UInt16) {
        let url = URL(string: input) ?? URL(string: "tcp://\(input)")
        guard let host = url?.host, !host.isEmpty, let port = url?.port,
            let port = UInt16(exactly: port)
        else {
            throw NvimChannelError.rpcError("Invalid address format. Expected host:port")
        }
        return (host, port)
    }

    private func startNvim() async {
        if !nvimArgs.isEmpty { titleReady = true }
        do {
            let cwd =
                nvimEnv?["PWD"]
                ?? ProcessInfo.processInfo.environment["PWD"]
                ?? NSHomeDirectory()
            try await channel.start(
                nvimPath: VeilConfig.current.nvim_path, cwd: cwd, appName: profile.name,
                extraArgs: nvimArgs, env: nvimEnv)
            guard let nvimView else { return }
            let gridSize = nvimView.gridSizeForViewSize(nvimView.bounds.size)
            try await channel.uiAttach(
                width: gridSize.cols, height: gridSize.rows,
                nativeTabs: VeilConfig.current.native_tabs)
            startEventLoop()

            // Register autocmds AFTER uiAttach. The initial BufEnter fires
            // during nvim startup (before this point), so it's intentionally
            // missed. This keeps titleReady false, suppressing the ugly initial
            // set_title from Startify or similar plugins.
            await setupNvimIntegration()
            nvimView.nvimPath = await channel.nvimPath

            // Enable nvim title. set_title events will be ignored until first BufEnter.
            try? await channel.command("set title")
        } catch {
            presentStartupError(error)
        }
    }

    /// Shared post-uiAttach setup: wire up tab selection, register autocmds
    /// for BufEnter/TabEnter notifications, debug commands, and query nvim version.
    private func setupNvimIntegration() async {
        let channel = self.channel!
        windowController?.tablineView.onSelectTab = { [weak self] handle in
            guard self != nil else { return }
            Task {
                _ = await channel.request(
                    "nvim_set_current_tabpage",
                    params: [.int(Int64(handle))]
                )
            }
        }

        // chan_id MUST be resolved here on the Swift side and passed into the
        // Lua script. Moving this fetch into nvim-setup.lua looks like it
        // would simplify things but breaks silently: `nvim_get_chan_info(0)`
        // only resolves "0 = current channel" for direct RPC calls. Inside a
        // nested nvim_exec_lua call the API treats Lua as an internal caller,
        // 0 yields nil, and every rpcnotify or rpcrequest closure registered
        // by the script then fires with chan_id = nil at autocmd or
        // user-command time, nowhere near setup, hard to trace back.
        let (_, chanInfo) = await channel.request(
            "nvim_get_chan_info", params: [.int(0)])
        if let chanId = chanInfo.dictionaryValue?[.string("id")]?.intValue, chanId > 0 {
            let isRemote = await channel.isRemote
            let (err, _) = await channel.request(
                "nvim_exec_lua",
                params: [
                    .string(NvimSetupScript.lua),
                    .array([.int(Int64(chanId)), .bool(isRemote)]),
                ])
            if err != .nil {
                NSLog("Veil: nvim setup failed: %@", "\(err)")
            }
        } else {
            NSLog("Veil: failed to resolve nvim channel id, skipping setup")
        }

        let (_, versionResult) = await channel.request(
            "nvim_exec2", params: [.string("version"), .map([.string("output"): .bool(true)])])
        if let output = versionResult.dictionaryValue?[.string("output")]?.stringValue,
            let firstLine = output.split(separator: "\n").first
        {
            nvimView?.nvimVersion = String(firstLine)
        }
    }

    private func startEventLoop() {
        startDisplayLink()
        eventLoopTask = Task { @MainActor in
            let events = channel.events
            for await batch in events {
                for event in batch {
                    grid.apply(event)
                    switch event {
                    case .flush:
                        // Don't render immediately; mark dirty and let the
                        // CVDisplayLink callback render at screen refresh rate.
                        needsRender = true
                    case .setTitle(let title):
                        if titleReady {
                            // Replace nvim's hardcoded "- Nvim" suffix with
                            // "- Veil" or "- Veil [Remote]" depending on mode.
                            let suffix = isRemote ? " - Veil [Remote]" : " - Veil"
                            let displayTitle: String
                            if title.trimmingCharacters(in: .whitespaces).isEmpty {
                                displayTitle = "Veil"
                            } else if title.hasSuffix(" - Nvim") {
                                displayTitle = String(title.dropLast(6)) + suffix
                            } else {
                                displayTitle = title
                            }
                            windowController?.updateTitle(displayTitle)
                        }
                    case .veilBufChanged:
                        titleReady = true
                    case .veilDebugToggle:
                        nvimView?.debugOverlayEnabled.toggle()
                        needsRender = true
                    case .veilDebugCopy:
                        if let text = nvimView?.debugInfoText() {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    case .veilVersion(let detailed):
                        let nvimVer = nvimView?.nvimVersion
                        Task {
                            if detailed {
                                let lines = Self.versionLines(nvimVersion: nvimVer)
                                await Self.showInScratchBuffer(lines, channel: channel)
                            } else {
                                let chunks = Self.versionEchoChunks(nvimVersion: nvimVer)
                                _ = await channel.request(
                                    "nvim_echo",
                                    params: [.array(chunks), .bool(false), .map([:])])
                            }
                        }
                    case .tablineUpdate(let current, let tabs):
                        windowController?.tablineView.update(current: current, tabInfos: tabs)
                    case .defaultColorsSet(let fg, let bg, _, _, _):
                        nvimView?.setDefaultColors(fg: fg, bg: bg)
                        windowController?.updateTitleBarColors(fg: fg, bg: bg)
                    case .modeInfoSet(_, let modes):
                        nvimView?.updateModeInfo(modes)
                    case .modeChange(_, let index):
                        nvimView?.updateCursorMode(index)
                    case .bell:
                        NSSound.beep()
                    case .optionSet(let name, let value):
                        if name == "guifont", let fontStr = value.stringValue, !fontStr.isEmpty {
                            nvimView?.parseAndSetGuifont(fontStr)
                            if let nvimView {
                                let newGridSize = nvimView.gridSizeForViewSize(nvimView.bounds.size)
                                Task {
                                    await channel.uiTryResize(
                                        width: newGridSize.cols, height: newGridSize.rows)
                                }
                            }
                        }
                    default:
                        break
                    }
                }
            }
            close()
        }
    }

    // MARK: - Version

    private static func hasUpdate() -> Bool {
        guard let latest = UpdateChecker.latestVersion else { return false }
        return latest != BuildVersion.version
    }

    private static func versionEchoChunks(nvimVersion: String? = nil) -> [MessagePackValue] {
        var text = ":VeilAppVersion\n"
        text += versionLines(nvimVersion: nvimVersion).joined(separator: "\n")
        if hasUpdate() {
            text += "\n\n:VeilAppVersion! to open in buffer"
        }
        return [.array([.string(text)])]
    }

    private static func versionLines(nvimVersion: String? = nil) -> [String] {
        var lines: [String] = []
        if let nvimVersion { lines.append(nvimVersion) }
        lines.append("Veil \(BuildVersion.displayVersion)")

        if hasUpdate(), let latest = UpdateChecker.latestVersion {
            lines.append("")
            lines.append(
                "Update v\(latest) available: `brew upgrade veil`"
                    + " or visit <https://github.com/0x1b2c/Veil/releases>")
            if let notes = UpdateChecker.releaseNotes, !notes.isEmpty {
                let trimmed = notes.trimmingCharacters(in: .newlines)
                lines.append("")
                lines.append("Release notes:")
                lines.append("")
                lines.append(contentsOf: trimmed.components(separatedBy: "\n"))
            }
        }

        return lines
    }

    private static func showInScratchBuffer(
        _ lines: [String], channel: NvimChannel
    ) async {
        let lineValues = lines.map { MessagePackValue.string($0) }
        let lua = """
            local lines = ...
            vim.cmd('new')
            local buf = vim.api.nvim_get_current_buf()
            vim.bo[buf].buftype = 'nofile'
            vim.bo[buf].bufhidden = 'wipe'
            vim.bo[buf].swapfile = false
            vim.bo[buf].filetype = 'markdown'
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.bo[buf].modifiable = false
            """
        _ = await channel.request(
            "nvim_exec_lua", params: [.string(lua), .array([.array(lineValues)])])
    }

    // MARK: - CVDisplayLink frame pacing

    /// Start a CVDisplayLink that fires at screen refresh rate.
    /// The callback dispatches to main thread where we check needsRender
    /// and render at most once per vsync, coalescing multiple flushes.
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        let context = DisplayLinkContext(document: self)
        let retained = Unmanaged.passRetained(context)
        displayLinkContext = retained

        CVDisplayLinkSetOutputCallback(link, displayLinkCallback, retained.toOpaque())
        CVDisplayLinkStart(link)
        displayLink = link
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
        // Balance the passRetained from startDisplayLink
        displayLinkContext?.release()
        displayLinkContext = nil
    }

    /// Called from CVDisplayLink callback on main thread.
    /// Renders at most once per vsync, coalescing all flushes since last frame.
    fileprivate func displayLinkFired() {
        guard needsRender else { return }
        needsRender = false
        nvimView?.render(grid: grid)
        grid.clearDirty()
    }

    override func canClose(
        withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        if isRemote {
            // Remote connection: just disconnect. The remote nvim stays alive.
            replyToCanClose(
                true, delegate: delegate, selector: shouldCloseSelector, contextInfo: contextInfo)
        } else {
            Task { @MainActor in
                // Send :confirm qa to let nvim prompt for unsaved buffers
                try? await channel.command("confirm qa")
                // Don't allow NSDocument to close; the window closes when nvim
                // exits (event stream ends -> close() is called from event loop)
            }
            replyToCanClose(
                false, delegate: delegate, selector: shouldCloseSelector, contextInfo: contextInfo)
        }
    }

    /// NSDocument canClose callback pattern: the framework doesn't accept a
    /// direct return value. Instead, you must invoke the delegate's selector
    /// with a Bool indicating whether the document should close.
    private func replyToCanClose(
        _ shouldClose: Bool, delegate: Any, selector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let selector else { return }
        let obj = delegate as AnyObject
        typealias ShouldCloseFunc =
            @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
        let imp = obj.method(for: selector)
        let fn = unsafeBitCast(imp, to: ShouldCloseFunc.self)
        fn(obj, selector, self, shouldClose, contextInfo)
    }

    override func close() {
        stopDisplayLink()
        eventLoopTask?.cancel()
        Task { await channel.stop() }
        super.close()
    }

    /// Render a startup-failure message into the document window itself.
    /// Modal alerts (NSAlert / sheet) are unreliable here: under macOS 14+
    /// cooperative activation, a CLI cold-started app cannot bring any of its
    /// windows to the foreground, leaving modals invisible and blocking the
    /// run loop. Painting the message into the already-visible window
    /// sidesteps the activation rules entirely.
    private func presentStartupError(_ error: Error) {
        let title =
            (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        let body = (error as? LocalizedError)?.recoverySuggestion
        windowController?.showStartupError(title: title, body: body)
    }

    func nvimViewNeedsDisplay(_ view: NvimView) {
        grid.markAllRowsDirty()
        needsRender = true
    }

    func redraw() {
        // Prevent white flash on initial window creation: only allow redraw
        // after the event loop has rendered at least once. windowDidBecomeKey
        // fires before neovim sends grid_resize, and the empty grid defaults
        // to a white background which cause white flash.
        guard grid.size != .zero else { return }
        grid.markAllRowsDirty()
        needsRender = true
    }

    func windowDidResize(to size: NSSize) {
        guard let nvimView else { return }
        let gridSize = nvimView.gridSizeForViewSize(size)
        guard gridSize.rows > 0, gridSize.cols > 0 else { return }
        Task { await channel.uiTryResize(width: gridSize.cols, height: gridSize.rows) }
    }

    /// Pause the display link when the window is fully occluded, minimized,
    /// or on a different Space. Otherwise the callback wakes the main thread
    /// at refresh rate to discover there is nothing to render.
    func windowDidChangeVisibility(isVisible: Bool) {
        if isVisible {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }
}

// MARK: - CVDisplayLink callback plumbing

/// Prevent retain cycle: CVDisplayLink C callback captures a raw pointer
/// to this context, which holds a weak reference back to the document.
private final class DisplayLinkContext {
    weak var document: WindowDocument?
    init(document: WindowDocument) { self.document = document }
}

/// CVDisplayLink C function callback. Runs on a high-priority display thread,
/// so we dispatch to main for the actual render (Metal/AppKit require it).
private func displayLinkCallback(
    _ displayLink: CVDisplayLink,
    _ inNow: UnsafePointer<CVTimeStamp>,
    _ inOutputTime: UnsafePointer<CVTimeStamp>,
    _ flagsIn: CVOptionFlags,
    _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    _ context: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let context else { return kCVReturnSuccess }
    let ctx = Unmanaged<DisplayLinkContext>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        ctx.document?.displayLinkFired()
    }
    return kCVReturnSuccess
}
