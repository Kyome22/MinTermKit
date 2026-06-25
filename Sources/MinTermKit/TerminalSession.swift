import AppKit
import Observation
import MinTermCore
import MinTermProcess

/// The observable model that drives ``TerminalView``.
///
/// `TerminalSession` ties the UI-agnostic ``Terminal`` engine to an input/output
/// source and publishes redraw signals to SwiftUI via the Observation framework.
/// Create one, attach it to a ``TerminalView``, then either run a local shell
/// with ``startLocalProcess(executable:args:workingDirectory:)`` or wire it to a
/// remote source by calling ``feed(_:)`` with incoming bytes and reading user
/// input through ``sendUserInput(_:)``.
@MainActor
@Observable
public final class TerminalSession: TerminalDelegate, LocalProcessDelegate {
    /// The underlying terminal engine; use it for advanced read access to the grid.
    public let terminal: Terminal
    @ObservationIgnored private let process = LocalProcess()

    /// The current window title set by the host program (OSC 0/2).
    public private(set) var title = ""
    /// Whether a local process is currently running.
    public private(set) var isRunning = false

    /// Bumped (coalesced) whenever the screen content changes, to drive redraws.
    /// Internal: only the in-module view reads it.
    private(set) var revision = 0
    /// Read by the in-module renderer; not part of the public surface.
    private(set) var selection: TerminalSelection?
    private(set) var composingText = ""

    /// Called when the local process exits. Use it to close the window, offer a
    /// restart, etc. If nil, the session just shows "[Process completed]".
    @ObservationIgnored public var onProcessTerminated: ((Int32?) -> Void)?

    @ObservationIgnored private var updateScheduled = false
    @ObservationIgnored private var selecting = false

    /// Creates a session with a terminal of the given size and scrollback capacity.
    public init(cols: Int = 80, rows: Int = 24, scrollbackLimit: Int = 1000) {
        terminal = Terminal(cols: cols, rows: rows, scrollbackLimit: scrollbackLimit)
        terminal.delegate = self
        process.delegate = self
    }

    /// Starts a local shell and connects it to the terminal.
    ///
    /// Does nothing if a process is already running.
    ///
    /// - Parameters:
    ///   - executable: The shell/program to run (defaults to `/bin/zsh`).
    ///   - args: Arguments passed to the program.
    ///   - workingDirectory: The starting directory; defaults to the user's home.
    public func startLocalProcess(
        executable: String = "/bin/zsh",
        args: [String] = [],
        workingDirectory: String? = nil
    ) {
        guard !isRunning else { return }
        isRunning = true
        process.start(
            executable: executable,
            args: args,
            currentDirectory: workingDirectory ?? NSHomeDirectory(),
            cols: terminal.cols,
            rows: terminal.rows
        )
    }

    /// Feeds bytes directly into the engine (for non-local sources such as SSH).
    ///
    /// - Parameter bytes: Output bytes received from the remote/host source.
    public func feed(_ bytes: [UInt8]) {
        terminal.feed(bytes[...])
    }

    /// Observes every batch of user input bytes (diagnostics/tests).
    @ObservationIgnored var userInputObserver: (([UInt8]) -> Void)?

    /// Sends user input bytes to the running program.
    ///
    /// - Parameter bytes: The bytes to deliver to the program's input.
    public func sendUserInput(_ bytes: [UInt8]) {
        userInputObserver?(bytes)
        process.send(bytes)
    }

    /// Resizes both the engine grid and the connected process's PTY.
    ///
    /// - Parameters:
    ///   - cols: The new width in columns.
    ///   - rows: The new height in rows.
    public func resize(cols: Int, rows: Int) {
        terminal.resize(cols: cols, rows: rows)
        process.resize(cols: cols, rows: rows)
    }

    /// Terminates the running local process.
    public func terminate() {
        process.terminate()
    }

    // MARK: IME composition (driven by the in-module input view)

    func setComposing(_ text: String) {
        composingText = text
        revision &+= 1
    }

    func clearComposing() {
        guard !composingText.isEmpty else { return }
        composingText = ""
        revision &+= 1
    }

    // MARK: Selection (driven by the in-module input view)

    func beginSelection(at position: Position) {
        selection = TerminalSelection(anchor: position, head: position)
        selecting = true
        revision &+= 1
    }

    func updateSelection(to position: Position) {
        guard selecting, var current = selection else { return }
        current.head = position
        selection = current
        revision &+= 1
    }

    func endSelection() {
        selecting = false
    }

    func clearSelection() {
        guard selection != nil else { return }
        selection = nil
        revision &+= 1
    }

    /// Copies the current selection to the pasteboard (e.g. for a Copy menu item).
    public func copySelection() {
        guard let text = selectedText(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func selectedText() -> String? {
        guard let selection else { return nil }
        let (start, end) = selection.normalized()
        var rows: [String] = []
        var row = max(0, start.row)
        while row <= min(end.row, terminal.rows - 1) {
            let line = terminal.displayLine(row)
            let from = row == start.row ? start.col : 0
            let to = row == end.row ? end.col : terminal.cols - 1
            var text = ""
            var column = max(0, from)
            while column <= min(to, terminal.cols - 1) {
                let cell = line[column]
                if cell.width != 0 {
                    text.unicodeScalars.append(cell.scalar)
                }
                column += 1
            }
            while text.last == " " {
                text.removeLast()
            }
            rows.append(text)
            row += 1
        }
        return rows.joined(separator: "\n")
    }

    // MARK: TerminalDelegate

    /// Forwards engine output bytes to the running process. (``TerminalDelegate``)
    public func terminalSend(_ terminal: Terminal, data: [UInt8]) {
        process.send(data)
    }

    /// Schedules a coalesced redraw when the screen changes. (``TerminalDelegate``)
    public func terminalDidUpdate(_ terminal: Terminal) {
        scheduleUpdate()
    }

    /// Updates ``title`` when the host sets it. (``TerminalDelegate``)
    public func terminalSetTitle(_ terminal: Terminal, title: String) {
        self.title = title
    }

    /// Plays the system beep on `BEL`. (``TerminalDelegate``)
    public func terminalBell(_ terminal: Terminal) {
        NSSound.beep()
    }

    // MARK: LocalProcessDelegate

    /// Feeds process output into the engine. (``LocalProcessDelegate``)
    public func localProcess(_ process: LocalProcess, didReceive data: [UInt8]) {
        terminal.feed(data[...])
    }

    /// Shows "[Process completed]" and invokes ``onProcessTerminated``. (``LocalProcessDelegate``)
    public func localProcessDidTerminate(_ process: LocalProcess, exitCode: Int32?) {
        isRunning = false
        terminal.feed(Array("\r\n[Process completed]\r\n".utf8))
        onProcessTerminated?(exitCode)
    }

    // MARK: Redraw coalescing

    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.revision &+= 1
        }
    }
}
