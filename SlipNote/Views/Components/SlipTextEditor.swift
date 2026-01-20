import SwiftUI
import AppKit

struct SlipTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onEscape: () -> Void
    var onCommandEnter: () -> Void
    var onNumberKey: ((Int) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = SlipNSTextView()

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.allowsUndo = true

        // Set line spacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]

        // Store coordinator reference in text view
        textView.coordinator = context.coordinator

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SlipNSTextView else { return }

        // Update coordinator callbacks
        context.coordinator.onEscape = onEscape
        context.coordinator.onCommandEnter = onCommandEnter
        context.coordinator.onNumberKey = onNumberKey

        // Update text only if different to avoid cursor jump
        if textView.string != text {
            textView.string = text
        }

        // Make first responder
        DispatchQueue.main.async {
            if let window = textView.window, window.firstResponder != textView {
                window.makeFirstResponder(textView)
                // Select all if there's text
                if !textView.string.isEmpty {
                    textView.selectAll(nil)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SlipTextEditor
        var onEscape: (() -> Void)?
        var onCommandEnter: (() -> Void)?
        var onNumberKey: ((Int) -> Void)?

        init(_ parent: SlipTextEditor) {
            self.parent = parent
            self.onEscape = parent.onEscape
            self.onCommandEnter = parent.onCommandEnter
            self.onNumberKey = parent.onNumberKey
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async {
                self.parent.text = textView.string
            }
        }
    }
}

// Custom NSTextView that handles special key events
class SlipNSTextView: NSTextView {
    weak var coordinator: SlipTextEditor.Coordinator?

    override func keyDown(with event: NSEvent) {
        // ESC key (keyCode 53)
        if event.keyCode == 53 {
            coordinator?.onEscape?()
            return
        }

        super.keyDown(with: event)
    }

    // ESC key typically calls cancelOperation instead of keyDown
    override func cancelOperation(_ sender: Any?) {
        coordinator?.onEscape?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ESC key (keyCode 53)
        if event.keyCode == 53 {
            coordinator?.onEscape?()
            return true
        }

        // Cmd+A - select all text
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "a" {
            selectAll(nil)
            return true
        }

        // Cmd+V - paste
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "v" {
            paste(nil)
            return true
        }

        // Cmd+C - copy
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "c" {
            copy(nil)
            return true
        }

        // Cmd+X - cut
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "x" {
            cut(nil)
            return true
        }

        // Cmd+Z - undo
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "z" {
            undoManager?.undo()
            return true
        }

        // Cmd+Enter (Return keyCode is 36) - save to Inbox
        if event.keyCode == 36 && event.modifierFlags.contains(.command) {
            coordinator?.onCommandEnter?()
            return true
        }

        // Cmd+0-9 - save to specific category
        if let handler = coordinator?.onNumberKey,
           event.modifierFlags.contains(.command) {
            if let char = event.charactersIgnoringModifiers?.first,
               let digit = Int(String(char)),
               digit >= 0 && digit <= 9 {
                handler(digit)
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override var acceptsFirstResponder: Bool { true }
}
