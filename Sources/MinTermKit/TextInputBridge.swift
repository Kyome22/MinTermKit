import AppKit
import SwiftUI
import MinTermCore

/// The only AppKit-backed piece: a transparent first-responder view that
/// captures keyboard (including IME via NSTextInputClient), mouse, scroll and
/// paste, and forwards the resulting bytes to the session.
struct TextInputBridge: NSViewRepresentable {
    let session: TerminalSession
    let metrics: FontMetrics

    func makeNSView(context: Context) -> TerminalInputView {
        let view = TerminalInputView()
        view.session = session
        view.metrics = metrics
        return view
    }

    func updateNSView(_ nsView: TerminalInputView, context: Context) {
        nsView.session = session
        nsView.metrics = metrics
    }
}

final class TerminalInputView: NSView {
    weak var session: TerminalSession?
    var metrics: FontMetrics?

    private var markedText = ""

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard let session else { return }

        // While composing (IME), let every key go to the input system so it can
        // edit/commit the marked text instead of being sent to the program.
        if hasMarkedText() {
            inputContext?.handleEvent(event)
            return
        }

        session.clearSelection()
        let applicationCursor = session.terminal.applicationCursorKeys

        switch event.keyCode {
        case 51: session.sendUserInput([0x7F]); return // backspace
        case 36, 76: session.sendUserInput([0x0D]); return // return / enter
        case 48: session.sendUserInput([0x09]); return // tab
        case 53: session.sendUserInput([0x1B]); return // escape
        case 117: session.sendUserInput(KeyEncoder.encode(.delete, applicationCursor: applicationCursor)); return
        default:
            break
        }

        if let special = Self.specialKey(for: event) {
            session.sendUserInput(KeyEncoder.encode(special, applicationCursor: applicationCursor))
            return
        }

        if event.modifierFlags.contains(.control),
           let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
           scalar.value < 128 {
            session.sendUserInput(KeyEncoder.control(UInt8(scalar.value)))
            return
        }

        inputContext?.handleEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v":
                pasteFromClipboard()
                return true
            case "c":
                session?.copySelection()
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    private func pasteFromClipboard() {
        guard let session,
              let text = NSPasteboard.general.string(forType: .string) else { return }
        session.sendUserInput(KeyEncoder.paste(text, bracketed: session.terminal.bracketedPasteEnabled))
    }

    private static func specialKey(for event: NSEvent) -> SpecialKey? {
        guard let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else { return nil }
        switch Int(scalar.value) {
        case NSUpArrowFunctionKey: return .up
        case NSDownArrowFunctionKey: return .down
        case NSLeftArrowFunctionKey: return .left
        case NSRightArrowFunctionKey: return .right
        case NSPageUpFunctionKey: return .pageUp
        case NSPageDownFunctionKey: return .pageDown
        case NSHomeFunctionKey: return .home
        case NSEndFunctionKey: return .end
        case NSF1FunctionKey...NSF12FunctionKey: return .function(Int(scalar.value) - NSF1FunctionKey + 1)
        default: return nil
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let session else { return }
        if session.terminal.mouseMode != .off {
            reportMouse(event, action: .press)
        } else if let cell = cell(for: event) {
            session.beginSelection(at: cell)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let session else { return }
        if session.terminal.mouseMode != .off {
            reportMouse(event, action: .release)
        } else {
            session.endSelection()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session else { return }
        if session.terminal.mouseMode != .off {
            reportMouse(event, action: .drag)
        } else if let cell = cell(for: event) {
            session.updateSelection(to: cell)
        }
    }

    private func cell(for event: NSEvent) -> Position? {
        guard let metrics else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let col = max(0, Int(point.x / metrics.cellWidth))
        let row = max(0, Int(point.y / metrics.cellHeight))
        return Position(col: col, row: row)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let session, let metrics else { return }
        let lineDelta = Int((event.scrollingDeltaY / metrics.cellHeight).rounded())
        if lineDelta > 0 {
            session.terminal.scrollViewport(byLines: lineDelta)
        } else if lineDelta < 0 {
            session.terminal.scrollViewport(byLines: lineDelta)
        }
    }

    private func reportMouse(_ event: NSEvent, action: MouseAction) {
        guard let session, let metrics, session.terminal.mouseMode != .off else { return }
        let point = convert(event.locationInWindow, from: nil)
        let col = max(0, Int(point.x / metrics.cellWidth))
        let row = max(0, Int(point.y / metrics.cellHeight))
        session.terminal.sendMouse(col: col, row: row, button: 0, action: action)
    }

    func characterIndex(for point: NSPoint) -> Int {
        NSNotFound
    }
}

// MARK: - NSTextInputClient

extension TerminalInputView: @preconcurrency NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        markedText = ""
        session?.clearComposing()
        session?.sendUserInput(Array(text.utf8))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        session?.setComposing(markedText)
    }

    func unmarkText() {
        markedText = ""
        session?.clearComposing()
    }

    func hasMarkedText() -> Bool {
        !markedText.isEmpty
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func markedRange() -> NSRange {
        markedText.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: markedText.count)
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window, let metrics, let cursor = session?.terminal.displayCursor else { return .zero }
        let rectInView = CGRect(
            x: CGFloat(cursor.col) * metrics.cellWidth,
            y: CGFloat(cursor.row) * metrics.cellHeight,
            width: metrics.cellWidth,
            height: metrics.cellHeight
        )
        return window.convertToScreen(convert(rectInView, to: nil))
    }
}
