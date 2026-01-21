import SwiftUI

// Shared state for detail view that parent can access
class DetailViewState: ObservableObject {
    @Published var isEditing = false
    @Published var hasVersions = false

    // Action callbacks (set by SlipDetailView)
    var onStartEdit: (() -> Void)?
    var onNavigateVersion: ((Bool) -> Void)?  // true = forward (newer)

    func reset() {
        isEditing = false
        hasVersions = false
        onStartEdit = nil
        onNavigateVersion = nil
    }

    func startEdit() {
        onStartEdit?()
    }

    func navigateVersion(forward: Bool) {
        onNavigateVersion?(forward)
    }
}

struct SlipDetailView: View {
    let slip: Slip
    var startInEditMode: Bool = false
    let onBack: () -> Void
    @ObservedObject var detailState: DetailViewState

    @EnvironmentObject var appState: AppState
    @State private var editedContent: String = ""
    @State private var currentContent: String = ""  // Track current content after saves
    @State private var versions: [Version] = []
    @State private var currentVersionIndex = 0
    @State private var lastClickTime: Date = .distantPast

    private var currentCategory: Category? {
        appState.categories.first { $0.id == slip.categoryId }
    }

    private var displayedContent: String {
        if currentVersionIndex == 0 {
            return currentContent.isEmpty ? slip.content : currentContent
        } else {
            return versions[currentVersionIndex - 1].content
        }
    }

    // Get title from displayed content (first line)
    private var displayedTitle: String {
        displayedContent.components(separatedBy: "\n").first ?? ""
    }

    // Get body from displayed content (everything after first line)
    private var displayedBody: String {
        let lines = displayedContent.components(separatedBy: "\n")
        if lines.count > 1 {
            return lines.dropFirst().joined(separator: "\n")
        }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation header
            headerView

            Divider()

            // Content area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title (first line of content)
                    Text(displayedTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .textSelection(.enabled)

                    // Timestamp
                    Text("[\(slip.timestamp)]")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)

                    Divider()

                    // Content body (everything after first line)
                    if detailState.isEditing {
                        editingView
                    } else if !displayedBody.isEmpty {
                        Text(displayedBody)
                            .font(.system(size: 16))
                            .lineSpacing(8)  // ~1.5 line height
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Double-click detection to enter edit mode
                    let now = Date()
                    if now.timeIntervalSince(lastClickTime) < 0.3 && !detailState.isEditing {
                        startEditing()
                    }
                    lastClickTime = now
                }
            }

            // Version navigation
            if !versions.isEmpty {
                versionNavigator
            }
        }
        .onAppear {
            loadVersions()
            editedContent = slip.content
            // Register callbacks
            detailState.onStartEdit = { [self] in
                startEditing()
            }
            detailState.onNavigateVersion = { [self] forward in
                navigateVersion(forward: forward)
            }
            // Start in edit mode if requested
            if startInEditMode {
                startEditing()
            }
        }
        .onDisappear {
            detailState.reset()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button {
                onBack()
            } label: {
                Text("<- Back")
                    .font(.system(size: 13, design: .monospaced))
            }
            .buttonStyle(.borderless)

            Spacer()

            if let category = currentCategory, !category.name.isEmpty {
                HStack(spacing: 4) {
                    Text("\(category.id)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 16, height: 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(category.name)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            if !detailState.isEditing {
                Text("[⌘↩ to edit]")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    // MARK: - Editing View

    private var editingView: some View {
        VStack(alignment: .trailing, spacing: 8) {
            DetailTextEditor(
                text: $editedContent,
                onEscape: { cancelEditing() },
                onCommandEnter: { saveChanges() }
            )
            .frame(minHeight: 200)

            HStack {
                Button("Cancel") {
                    cancelEditing()
                }

                Button("Save") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Version Navigator

    private var versionNavigator: some View {
        HStack {
            Button {
                navigateVersion(forward: false)
            } label: {
                Text("<")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            .buttonStyle(.borderless)
            .disabled(currentVersionIndex >= versions.count)

            Spacer()

            if currentVersionIndex == 0 {
                Text("v\(versions.count + 1) (current)")
                    .font(.system(size: 12, design: .monospaced))
            } else {
                let version = versions[currentVersionIndex - 1]
                Text("v\(versions.count - currentVersionIndex + 1) (\(version.timestamp))")
                    .font(.system(size: 12, design: .monospaced))
            }

            Spacer()

            Button {
                navigateVersion(forward: true)
            } label: {
                Text(">")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            .buttonStyle(.borderless)
            .disabled(currentVersionIndex <= 0)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Actions

    private func loadVersions() {
        do {
            versions = try DatabaseService.shared.fetchVersions(for: slip)
            detailState.hasVersions = !versions.isEmpty
        } catch {
            print("Failed to load versions: \(error)")
        }
    }

    private func startEditing() {
        editedContent = currentContent.isEmpty ? slip.content : currentContent
        detailState.isEditing = true
    }

    private func cancelEditing() {
        editedContent = currentContent.isEmpty ? slip.content : currentContent
        detailState.isEditing = false
    }

    private func saveChanges() {
        let originalContent = currentContent.isEmpty ? slip.content : currentContent
        guard editedContent != originalContent else {
            detailState.isEditing = false
            return
        }

        appState.updateSlip(slip, newContent: editedContent)
        currentContent = editedContent  // Update displayed content immediately
        detailState.isEditing = false
        loadVersions()
    }

    private func navigateVersion(forward: Bool) {
        if forward {
            currentVersionIndex = max(0, currentVersionIndex - 1)
        } else {
            currentVersionIndex = min(versions.count, currentVersionIndex + 1)
        }
    }
}

#Preview {
    SlipDetailView(slip: Slip(content: "Test content\nSecond line"), onBack: {}, detailState: DetailViewState())
        .environmentObject(AppState())
}
