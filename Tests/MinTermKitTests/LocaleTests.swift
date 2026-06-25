import Testing
import Foundation
import MinTermProcess

@MainActor
private final class OutputCollector: LocalProcessDelegate {
    var data: [UInt8] = []
    func localProcess(_ process: LocalProcess, didReceive data: [UInt8]) { self.data.append(contentsOf: data) }
    func localProcessDidTerminate(_ process: LocalProcess, exitCode: Int32?) {}
}

@MainActor
@Test func childShellGetsUTF8LocaleFromMinimalEnvironment() async {
    let collector = OutputCollector()
    let process = LocalProcess(delegate: collector)
    // Simulate a Finder/launchd launch: no LANG/LC_* present.
    let minimal = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "USER": NSUserName()]
    process.start(executable: "/bin/zsh", environment: minimal, cols: 80, rows: 24)
    try? await Task.sleep(nanoseconds: 700_000_000)
    process.send(Array("locale charmap\r".utf8))
    try? await Task.sleep(nanoseconds: 700_000_000)
    process.terminate()
    let text = String(decoding: collector.data, as: UTF8.self)
    #expect(text.contains("UTF-8"))
}
