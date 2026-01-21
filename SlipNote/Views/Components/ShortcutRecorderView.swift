import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorderView: View {
    let id: String
    @Binding var shortcut: KeyboardShortcut
    @ObservedObject private var settings = AppSettings.shared
    @State private var localMonitor: Any?

    private var isRecording: Bool {
        settings.recordingShortcutId == id
    }

    var body: some View {
        Button {
            startRecording()
        } label: {
            HStack {
                if isRecording {
                    Text("Press shortcut...")
                        .foregroundColor(.secondary)
                } else {
                    Text(shortcut.displayString)
                        .fontWeight(.medium)
                }
            }
            .frame(minWidth: 100)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isRecording ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        // Stop any other recorder first
        if settings.recordingShortcutId != nil && settings.recordingShortcutId != id {
            settings.recordingShortcutId = nil
        }

        settings.recordingShortcutId = id

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Only process if this recorder is still active
            guard settings.recordingShortcutId == id else { return event }

            if event.type == .keyDown {
                // Check if it has modifier keys
                let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                if !modifiers.isEmpty {
                    var carbonModifiers: UInt32 = 0
                    if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
                    if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
                    if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
                    if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }

                    shortcut = KeyboardShortcut(
                        keyCode: UInt32(event.keyCode),
                        modifiers: carbonModifiers
                    )
                    stopRecording()
                    return nil
                }
            }

            // Allow Escape to cancel
            if event.keyCode == 53 { // Escape
                stopRecording()
                return nil
            }

            return event
        }
    }

    private func stopRecording() {
        if settings.recordingShortcutId == id {
            settings.recordingShortcutId = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

#Preview {
    ShortcutRecorderView(id: "preview", shortcut: .constant(.defaultInputMode))
        .padding()
}
