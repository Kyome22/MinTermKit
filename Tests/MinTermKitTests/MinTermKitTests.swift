import Testing
import Foundation
import MinTermCore
import MinTermProcess
@testable import MinTermKit

@MainActor
private final class ProcessHarness: LocalProcessDelegate {
    let terminal: Terminal
    var onTerminate: (() -> Void)?

    init(terminal: Terminal) {
        self.terminal = terminal
    }

    func localProcess(_ process: LocalProcess, didReceive data: [UInt8]) {
        terminal.feed(data[...])
    }

    func localProcessDidTerminate(_ process: LocalProcess, exitCode: Int32?) {
        onTerminate?()
    }
}

@MainActor
@Test func echoOutputReachesTerminal() async {
    let terminal = Terminal(cols: 40, rows: 10)
    let harness = ProcessHarness(terminal: terminal)
    let process = LocalProcess(delegate: harness)

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        var resumed = false
        harness.onTerminate = {
            guard !resumed else { return }
            resumed = true
            continuation.resume()
        }
        process.start(executable: "/bin/echo", args: ["hello-mintermkit"], cols: 40, rows: 10)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !resumed else { return }
            resumed = true
            continuation.resume()
        }
    }

    // Allow the final data-delivery hop to drain.
    try? await Task.sleep(nanoseconds: 150_000_000)

    var text = ""
    for column in 0..<40 {
        let cell = terminal.displayLine(0)[column]
        if cell.width == 0 { continue }
        text.unicodeScalars.append(cell.scalar)
    }
    #expect(text.contains("hello-mintermkit"))
}
