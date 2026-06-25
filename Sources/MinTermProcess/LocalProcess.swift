import Darwin
import Dispatch
import Foundation

/// Receives output and lifecycle events from a ``LocalProcess``. Called on the main actor.
@MainActor
public protocol LocalProcessDelegate: AnyObject {
    /// The child process produced output bytes (e.g. a PTY read).
    func localProcess(_ process: LocalProcess, didReceive data: [UInt8])
    /// The child process exited; `exitCode` is its status, or nil if it was signaled.
    func localProcessDidTerminate(_ process: LocalProcess, exitCode: Int32?)
}

/// Runs a child process (typically a shell) on a pseudo-terminal and bridges
/// its I/O to a delegate.
///
/// `LocalProcess` forks a child connected to a PTY, reads its output on a private
/// queue (with back-pressure), and marshals both output and the exit event to the
/// main actor before calling the ``delegate``. Write the host's input back with
/// ``send(_:)`` and propagate window-size changes with ``resize(cols:rows:)``.
public final class LocalProcess: @unchecked Sendable {
    /// Receives output and termination callbacks on the main actor.
    public weak var delegate: (any LocalProcessDelegate)?

    private let ioQueue = DispatchQueue(label: "com.mintermkit.localprocess.io")
    private var masterFD: Int32 = -1
    private var pid: pid_t = -1
    private var channel: DispatchIO?
    private var processSource: (any DispatchSourceProcess)?

    /// Whether the child process is currently running.
    public private(set) var running = false

    /// Creates a process runner with an optional delegate.
    public init(delegate: (any LocalProcessDelegate)? = nil) {
        self.delegate = delegate
    }

    /// Forks the child on a new PTY and execs `executable` in it.
    ///
    /// Ensures a UTF-8 locale and a sensible `TERM` for the child. Does nothing if
    /// a process is already running.
    ///
    /// - Parameters:
    ///   - executable: The program to run (defaults to `/bin/zsh`).
    ///   - args: Arguments passed after `executable`.
    ///   - environment: Environment variables; defaults to the current process's.
    ///   - currentDirectory: The child's working directory, or nil to inherit.
    ///   - cols: The initial terminal width in columns.
    ///   - rows: The initial terminal height in rows.
    public func start(
        executable: String = "/bin/zsh",
        args: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil,
        cols: Int,
        rows: Int
    ) {
        guard !running else { return }

        var env = environment ?? ProcessInfo.processInfo.environment
        if env["TERM"] == nil {
            env["TERM"] = "xterm-256color"
        }
        Self.ensureUTF8Locale(&env)
        let envArray = env.map { "\($0.key)=\($0.value)" }

        guard let result = PseudoTerminal.fork(
            executable: executable,
            args: args,
            environment: envArray,
            currentDirectory: currentDirectory,
            rows: UInt16(rows),
            cols: UInt16(cols)
        ) else {
            return
        }

        masterFD = result.masterFD
        pid = result.pid
        running = true
        setupChannel()
        setupProcessMonitor()
    }

    /// Writes input bytes to the child's PTY. No-op if the process isn't running.
    ///
    /// - Parameter bytes: The bytes to send to the program's standard input.
    public func send(_ bytes: [UInt8]) {
        guard running, let channel else { return }
        bytes.withUnsafeBytes { raw in
            let data = DispatchData(bytes: raw)
            channel.write(offset: 0, data: data, queue: ioQueue) { _, _, _ in }
        }
    }

    /// Updates the PTY window size, sending `SIGWINCH` to the child.
    ///
    /// - Parameters:
    ///   - cols: The new width in columns.
    ///   - rows: The new height in rows.
    public func resize(cols: Int, rows: Int) {
        guard running else { return }
        PseudoTerminal.setWindowSize(masterFD: masterFD, rows: UInt16(rows), cols: UInt16(cols))
    }

    /// Sends `SIGTERM` to the child process.
    public func terminate() {
        guard running else { return }
        kill(pid, SIGTERM)
    }

    // MARK: - Private

    private func setupChannel() {
        let descriptor = masterFD
        channel = DispatchIO(type: .stream, fileDescriptor: descriptor, queue: ioQueue) { _ in
            close(descriptor)
        }
        // Deliver promptly rather than buffering large amounts in the channel.
        channel?.setLimit(lowWater: 1)
        channel?.read(offset: 0, length: Int.max, queue: ioQueue) { [weak self] _, data, _ in
            guard let self, let data, !data.isEmpty else { return }
            self.deliver([UInt8](data))
        }
    }

    private func setupProcessMonitor() {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: ioQueue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var status = Int32.zero
            waitpid(self.pid, &status, 0)
            self.channel?.close()
            self.running = false
            let code = (status & 0x7F) == 0 ? (status >> 8) & 0xFF : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.delegate?.localProcessDidTerminate(self, exitCode: code)
                }
            }
        }
        source.resume()
        processSource = source
    }

    private func deliver(_ bytes: [UInt8]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.delegate?.localProcess(self, didReceive: bytes)
            }
        }
    }

    /// Ensures the child shell runs under a UTF-8 character locale. A Finder-launched
    /// app inherits a minimal (often US-ASCII) environment, which makes the shell
    /// treat multibyte characters as separate single-width bytes.
    private static func ensureUTF8Locale(_ env: inout [String: String]) {
        func isUTF8(_ value: String?) -> Bool {
            guard let value = value?.lowercased() else { return false }
            return value.contains("utf-8") || value.contains("utf8")
        }
        // Effective ctype locale precedence: LC_ALL > LC_CTYPE > LANG.
        let effective = env["LC_ALL"] ?? env["LC_CTYPE"] ?? env["LANG"]
        guard !isUTF8(effective) else { return }

        env["LC_ALL"] = nil // drop any non-UTF-8 blanket override
        env["LC_CTYPE"] = "en_US.UTF-8"
        if !isUTF8(env["LANG"]) {
            env["LANG"] = "en_US.UTF-8"
        }
    }
}
