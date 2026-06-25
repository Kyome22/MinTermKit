import Darwin

/// Thin wrappers around the pseudo-terminal system calls.
enum PseudoTerminal {
    /// Forks a child connected to a new PTY and execs `executable` in it.
    /// Returns the child pid and the master file descriptor in the parent.
    static func fork(
        executable: String,
        args: [String],
        environment: [String],
        currentDirectory: String?,
        rows: UInt16,
        cols: UInt16
    ) -> (pid: pid_t, masterFD: Int32)? {
        var master = Int32.zero
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)

        var argv = makeCStrings([executable] + args)
        var envp = makeCStrings(environment)

        let pid = forkpty(&master, nil, nil, &size)
        if pid < 0 {
            freeCStrings(argv)
            freeCStrings(envp)
            return nil
        }

        if pid == 0 {
            if let currentDirectory {
                _ = currentDirectory.withCString { chdir($0) }
            }
            executable.withCString { path in
                _ = execve(path, &argv, &envp)
            }
            _exit(127)
        }

        freeCStrings(argv)
        freeCStrings(envp)
        return (pid, master)
    }

    static func setWindowSize(masterFD: Int32, rows: UInt16, cols: UInt16) {
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &size)
    }

    private static func makeCStrings(_ strings: [String]) -> [UnsafeMutablePointer<CChar>?] {
        var result = strings.map { strdup($0) }
        result.append(nil)
        return result
    }

    private static func freeCStrings(_ pointers: [UnsafeMutablePointer<CChar>?]) {
        for pointer in pointers {
            if let pointer {
                free(pointer)
            }
        }
    }
}
