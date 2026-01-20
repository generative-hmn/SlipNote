import SwiftUI
import AppKit

extension Notification.Name {
    static let closeInputWindow = Notification.Name("closeInputWindow")
}

struct InputWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var text = ""
    @State private var isShowingCategoryBar = false
    @State private var selectedSearchIndex = 0

    // Cache for text when closing without saving
    private static var cachedText: String = ""

    private var isSearchMode: Bool {
        text.hasPrefix("/")
    }

    private var searchQuery: String {
        String(text.dropFirst())
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main input area with hint
            ZStack(alignment: .topLeading) {
                inputArea

                // Placeholder hint when empty
                if text.isEmpty {
                    Text("Type and press ⌘+number to save")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(NSColor.placeholderTextColor))
                        .padding(.top, 24)
                        .padding(.leading, 18)
                        .allowsHitTesting(false)
                }
            }

            // Search results (when in search mode)
            if isSearchMode && !searchQuery.isEmpty {
                searchResultsView
            }

            // Always show category bar
            categoryBar
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.66))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .frame(minWidth: 600)
        .onAppear {
            appState.loadCategories()
            restoreFromCache()
        }
        .onChange(of: appState.isInputWindowVisible) { _, isVisible in
            if isVisible {
                appState.loadCategories()
                restoreFromCache()
            }
        }
        .onChange(of: text) { _, newValue in
            if isSearchMode {
                appState.search(query: searchQuery)
                selectedSearchIndex = 0
            }
        }
    }

    private func restoreFromCache() {
        isShowingCategoryBar = false
        text = Self.cachedText
    }

    // MARK: - Input Area

    private var inputArea: some View {
        SlipTextEditor(
            text: $text,
            onEscape: { handleEscape() },
            onCommandEnter: { },  // Not used, ⌘0 handles Inbox
            onNumberKey: { digit in
                // Save to specific category when number key pressed (0-9)
                if appState.categories.contains(where: { $0.id == digit && !$0.name.isEmpty }) {
                    saveSlip(categoryId: digit)
                }
            }
        )
        .frame(height: 120)
        .padding(16)
    }

    // MARK: - Category Bar

    private var categoryBar: some View {
        let activeCategories = appState.categories.filter { !$0.name.isEmpty && $0.id != Category.trashId }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(activeCategories) { category in
                CategoryBubble(category: category) {
                    saveSlip(categoryId: category.id)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Search Results

    private var searchResultsView: some View {
        VStack(spacing: 0) {
            Divider()

            if appState.searchResults.isEmpty {
                Text("No results found", comment: "Search results empty state")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(appState.searchResults.prefix(10).enumerated()), id: \.element.id) { index, slip in
                            SearchResultRow(
                                slip: slip,
                                category: appState.categories.first { $0.id == slip.categoryId },
                                isSelected: index == selectedSearchIndex
                            )
                            .onTapGesture {
                                selectSearchResult(slip)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }

    // MARK: - Actions

    private func handleEscape() {
        // Cache text and close window
        Self.cachedText = text
        closeWindow()
    }

    private func saveSlip(categoryId: Int) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        appState.createSlip(content: content, categoryId: categoryId)
        text = ""
        Self.cachedText = ""  // Clear cache after saving
        isShowingCategoryBar = false
        closeWindow()
    }

    private func selectSearchResult(_ slip: Slip) {
        appState.selectedSlip = slip
        text = ""
        Self.cachedText = ""
        closeWindow()
    }

    private func moveSearchSelection(up: Bool) {
        let maxIndex = min(appState.searchResults.count, 10) - 1
        if up {
            selectedSearchIndex = max(0, selectedSearchIndex - 1)
        } else {
            selectedSearchIndex = min(maxIndex, selectedSearchIndex + 1)
        }
    }

    private func closeWindow() {
        // Post notification to close window - AppDelegate will handle it
        NotificationCenter.default.post(name: .closeInputWindow, object: nil)
    }
}

// MARK: - Category Bubble

struct CategoryBubble: View {
    let category: Category
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var categoryColor: Color {
        category.color ?? Color.accentColor
    }

    private var bgOpacity: Double {
        colorScheme == .light ? 0.8 : 0.2
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(category.name)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Text("⌘\(category.id)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(categoryColor.opacity(bgOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(categoryColor.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let slip: Slip
    let category: Category?
    let isSelected: Bool

    var body: some View {
        HStack {
            if let cat = category, !cat.name.isEmpty {
                Text("\(cat.id)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 14, height: 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(slip.timestamp)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(slip.title)
                        .lineLimit(1)
                }
                Text(slip.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}

// MARK: - Rounded Corner Shape

struct RoundedCorner: Shape {
    var radius: CGFloat = 12
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath()
        let topLeft = corners.contains(.topLeft) ? radius : 0
        let topRight = corners.contains(.topRight) ? radius : 0
        let bottomLeft = corners.contains(.bottomLeft) ? radius : 0
        let bottomRight = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        if topRight > 0 {
            path.appendArc(withCenter: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
                          radius: topRight, startAngle: 270, endAngle: 0, clockwise: false)
        }
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        if bottomRight > 0 {
            path.appendArc(withCenter: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
                          radius: bottomRight, startAngle: 0, endAngle: 90, clockwise: false)
        }
        path.line(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        if bottomLeft > 0 {
            path.appendArc(withCenter: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
                          radius: bottomLeft, startAngle: 90, endAngle: 180, clockwise: false)
        }
        path.line(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        if topLeft > 0 {
            path.appendArc(withCenter: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
                          radius: topLeft, startAngle: 180, endAngle: 270, clockwise: false)
        }
        path.close()

        return Path(path.cgPath)
    }
}

struct UIRectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

#Preview {
    InputWindowView()
        .environmentObject(AppState())
}
