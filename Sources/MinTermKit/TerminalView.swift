import AppKit
import SwiftUI
import MinTermCore

/// A SwiftUI terminal view backed by a ``TerminalSession``.
///
/// Rendering, layout, and resize are pure SwiftUI (a `Canvas` driven by a
/// `GeometryReader`); only keyboard, IME, and mouse capture are backed by a thin
/// AppKit view. Hand it a session and it draws the live terminal, forwarding
/// input and size changes back to the session.
public struct TerminalView: View {
    private let session: TerminalSession
    private let metrics: FontMetrics
    private let theme: TerminalTheme
    private let padding: CGFloat

    /// Creates a terminal view for the given session.
    ///
    /// - Parameters:
    ///   - session: The session whose terminal is displayed and driven.
    ///   - font: The monospaced font to render with.
    ///   - theme: The background/foreground/cursor/selection colors.
    ///   - padding: Inset between the window edge and the text grid. The view
    ///     fills this inset (and the whole view) with the theme background, so
    ///     no extra `.background(_:)` is needed around the view.
    public init(
        session: TerminalSession,
        font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular),
        theme: TerminalTheme = .default,
        padding: CGFloat = 0
    ) {
        self.session = session
        self.metrics = FontMetrics(font: font)
        self.theme = theme
        self.padding = padding
    }

    public var body: some View {
        // Read observable state in `body` so @Observable tracks it and re-renders
        // the Canvas (which redraws from the live terminal) on every change.
        let revision = session.revision
        let selection = session.selection
        let composing = session.composingText
        return GeometryReader { proxy in
            Canvas(rendersAsynchronously: false) { context, size in
                _ = revision
                CanvasRenderer(metrics: metrics, theme: theme).draw(
                    context,
                    size: size,
                    terminal: session.terminal,
                    selection: selection,
                    composing: composing
                )
            }
            .overlay(TextInputBridge(session: session, metrics: metrics))
            .padding(padding)
            .onChange(of: proxy.size, initial: true) { _, newSize in
                applyResize(CGSize(
                    width: newSize.width - padding * 2,
                    height: newSize.height - padding * 2
                ))
            }
        }
        .background(theme.background)
    }

    private func applyResize(_ size: CGSize) {
        guard metrics.cellWidth > 0, metrics.cellHeight > 0 else { return }
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        let cols = max(1, Int(size.width / metrics.cellWidth))
        let rows = max(1, Int(size.height / metrics.cellHeight))
        session.resize(cols: cols, rows: rows)
    }
}
