import SwiftUI
import AppKit

extension Notification.Name {
    static let closeInputWindow = Notification.Name("closeInputWindow")
}

struct InputWindowView: View {
    @EnvironmentObject var appState: AppState
    @State private var text = ""
    @State private var isShowingCategoryBar = false

    // Cache for text when closing without saving
    private static var cachedText: String = ""

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

            // Always show category bar
            categoryBar
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.66))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                .padding(2)
        )
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
    }

    private func restoreFromCache() {
        isShowingCategoryBar = false
        // Use captured text from appState if available, otherwise use cache
        if !appState.inputText.isEmpty {
            text = appState.inputText
            appState.inputText = ""  // Clear after using
        } else {
            text = Self.cachedText
        }
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
