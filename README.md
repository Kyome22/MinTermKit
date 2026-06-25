# MinTermKit

A minimal VT100/xterm terminal emulator for macOS with a **SwiftUI-first** view
layer. The engine is UI-agnostic and the view is a pure SwiftUI `Canvas` — only
keyboard/IME/mouse capture is backed by a thin AppKit shim.

MinTermKit deliberately targets the "**vim / less / tmux works**" feature level
rather than full terminal completeness, making it small enough to read and learn
from while still being usable for a real local shell.

<img width="549" height="434" alt="Image" src="https://github.com/user-attachments/assets/31488841-3076-4cc0-a2d4-edd896665ccd" />

## Features

- **UI-agnostic engine** — a VT500-style escape-sequence parser, a screen +
  scrollback buffer, and a per-cell `CharData`/`Attribute` model.
- **Colors & attributes** — ANSI 16/256 color (+24-bit true color), bold,
  underline, inverse.
- **Cursor / erase / scroll regions** (`DECSTBM`), **alternate buffer**
  (`?1049`), **application cursor keys** (`DECCKM`).
- **Mouse reporting** (`?1000`/`?1002`/`?1006`), **bracketed paste** (`?2004`).
- **Unicode** — full-width (CJK) cells and NFD combining-mark composition
  (e.g. macOS filenames where `ジ` = `シ` + U+3099).
- **Local shell** over a real PTY (`forkpty`) with async I/O and back-pressure.
- **IME** — inline composition via `NSTextInputClient`.
- **Selection & copy**, scrollback wheel-scrolling, configurable theme & padding.

## Requirements

- macOS 26+
- Swift 6.2+ / Xcode 26+

## Installation

Add the package with Swift Package Manager:

```swift
.package(url: "https://github.com/Kyome22/MinTermKit.git", from: "x.y.z")
```

…and depend on the `MinTermKit` product from your app target.

> **Important — App Sandbox must be off for a local shell.** Running a local
> shell means spawning an arbitrary executable via `forkpty`, which the macOS
> App Sandbox forbids. Set `ENABLE_APP_SANDBOX = NO` (the bundled Example does
> this). Like Terminal.app and iTerm2, a local-shell terminal can't be sandboxed
> and therefore can't ship on the Mac App Store; distribute with Developer ID +
> notarization instead. (A *remote-only* terminal can keep the sandbox.)

## Quick start

```swift
import SwiftUI
import MinTermKit

struct ContentView: View {
    @State private var session = TerminalSession(cols: 80, rows: 24)

    var body: some View {
        TerminalView(session: session, padding: 8)
            .onAppear {
                session.startLocalProcess(executable: "/bin/zsh")
            }
    }
}
```

`TerminalView` handles rendering, live resize (rows/cols follow the window),
keyboard/IME/mouse, selection, and scrollback automatically.

### Theming

```swift
let theme = TerminalTheme(
    background: Color(red: 0.11, green: 0.11, blue: 0.14),
    foreground: .green
)

TerminalView(session: session, theme: theme, padding: 12)
```

`TerminalTheme` controls the *default* foreground/background, cursor, and
selection colors. The view fills its own background (including the `padding`
inset) with `theme.background`, so you don't need a separate `.background(_:)`.
The ANSI 16/256 palette for colored program output comes from the engine.

### Working directory & shell

```swift
session.startLocalProcess(
    executable: "/bin/zsh",
    args: ["-l"],
    workingDirectory: "/path/to/dir"   // defaults to the user's home
)
```

## Architecture

Three layers, split into three SPM targets with a one-way dependency:

```
MinTermKit (SwiftUI)  ──▶  MinTermProcess (PTY)  ──▶  MinTermCore (engine)
        └───────────────────────────────────────────────────▲
```

| Target | Role |
|---|---|
| **MinTermCore** | The engine. UI- and process-agnostic. `Terminal` consumes bytes via `feed(_:)`, maintains the grid + scrollback, and exposes it for rendering. All outside communication flows through `TerminalDelegate`. |
| **MinTermProcess** | `LocalProcess` — forks a child shell on a PTY, reads its output with back-pressure on a private queue, and forces a UTF-8 locale. macOS only. |
| **MinTermKit** | `TerminalSession` (an `@Observable` bridge between engine and process), `TerminalView` (the SwiftUI view), and the `NSTextInputClient` input bridge. |

The engine never touches UI or processes, so you can also drive it headlessly
or wire it to a non-local byte source.

### Remote sources (SSH, etc.)

Display works today by feeding incoming bytes into the session:

```swift
let session = TerminalSession(cols: 80, rows: 24)
sshChannel.onData = { bytes in session.feed(bytes) }   // remote → screen
```

Routing *input* to a remote channel is not wired up yet — `sendUserInput` and
the engine's responses currently target the local process. See **Roadmap**.

## Scope & limitations

Intentionally **out of scope** (kept minimal): line **reflow** on resize
(content is preserved but not re-wrapped), images (Sixel/iTerm2/Kitty), the
Kitty keyboard protocol, Metal rendering, OSC palette/cursor overrides
(`OSC 4/10/11/12`), search, and accessibility.

**Roadmap ideas:** an input "send hook" for remote/SSH, OSC color overrides,
24-bit theming of the ANSI palette, and resize reflow.

## Documentation

The public API is documented with Swift-DocC. In Xcode: **Product → Build
Documentation**.

## Acknowledgments

MinTermKit's terminal-emulation design was informed by studying
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT License) by
Miguel de Icaza. Escape-sequence handling follows the ECMA-48 standard and
Paul Williams' [VT500 parser state machine](https://vt100.net/emu/dec_ansi_parser).
No SwiftTerm source code was copied; the implementation was written
independently.

## License

MIT License © 2026 Takuto NAKAMURA (Kyome). See [LICENSE](LICENSE).
