import SwiftUI
import UniformTypeIdentifiers

struct ViewModeView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedSlipForDetail: Slip?
    @State private var selectedSlipIndex: Int = 0
    @State private var selectedVersionIndex: Int = 0  // 0 = current, 1+ = older versions
    @State private var selectedSlipVersions: [Version] = []
    @State private var showingSettings = false
    @State private var showingAbout = false
    @State private var openInEditMode = false
    @State private var selectedSlipIds: Set<String> = []  // Multi-selection for drag
    @State private var dropTargetCategoryId: Int? = nil  // Track drop target for highlighting
    @State private var showEmptyTrashAlert = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    // Double-click tracking
    @State private var lastClickedSlipId: String? = nil
    @State private var lastClickTime: Date = .distantPast

    // Keyboard navigation flag (for auto-scroll)
    @State private var isKeyboardNavigation = false

    // Detail view state (shared with SlipDetailView)
    @StateObject private var detailState = DetailViewState()

    // NotificationCenter observer tokens for proper cleanup
    @State private var windowObserver: NSObjectProtocol?
    @State private var slipEditObserver: NSObjectProtocol?
    @State private var searchFocusObserver: NSObjectProtocol?

    // Opacity values based on color scheme (higher for light mode)
    private var categoryBgOpacity: Double { colorScheme == .light ? 0.8 : 0.2 }
    private var categorySelectedBgOpacity: Double { colorScheme == .light ? 0.9 : 0.3 }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar - Categories (fixed width, non-collapsible)
            sidebarView
                .frame(width: 180)

            Divider()

            // Main content
            if let slip = selectedSlipForDetail {
                SlipDetailView(slip: slip, startInEditMode: openInEditMode, onBack: {
                    selectedSlipForDetail = nil
                    openInEditMode = false
                }, detailState: detailState)
            } else {
                slipListView
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            appState.loadSlips()
            appState.loadCategories()
            setupKeyboardShortcuts()
            focusSearchField()

            // Listen for window becoming key to refocus search (token-based for proper cleanup)
            windowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak appState] _ in
                // Only focus if not in detail view
                guard appState != nil else { return }
                if selectedSlipForDetail == nil {
                    focusSearchField()
                }
            }

            // Listen for new slip creation from menu
            slipEditObserver = NotificationCenter.default.addObserver(
                forName: .openSlipInEditMode,
                object: nil,
                queue: .main
            ) { notification in
                if let slip = notification.object as? Slip {
                    openInEditMode = true
                    selectedSlipForDetail = slip
                }
            }

            // Listen for focus search field notification
            searchFocusObserver = NotificationCenter.default.addObserver(
                forName: .focusSearchField,
                object: nil,
                queue: .main
            ) { _ in
                Logger.shared.info("focusSearchField notification received")
                // Close detail view first if open
                selectedSlipForDetail = nil
                openInEditMode = false
                // Delay focus to allow view hierarchy to update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Logger.shared.info("Setting isSearchFocused = true")
                    isSearchFocused = true
                }
            }
        }
        .onDisappear {
            removeKeyboardShortcuts()
            // Remove observers using tokens for proper cleanup
            if let observer = windowObserver {
                NotificationCenter.default.removeObserver(observer)
                windowObserver = nil
            }
            if let observer = slipEditObserver {
                NotificationCenter.default.removeObserver(observer)
                slipEditObserver = nil
            }
            if let observer = searchFocusObserver {
                NotificationCenter.default.removeObserver(observer)
                searchFocusObserver = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("⌘F to search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .frame(minWidth: 200, maxWidth: 300)
                        .onChange(of: searchText) { _, newValue in
                            if newValue.isEmpty {
                                appState.loadSlips()
                            } else {
                                appState.search(query: newValue)
                            }
                        }
                        .onSubmit {
                            if let first = filteredSlips.first {
                                selectedSlipForDetail = first
                            }
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            appState.loadSlips()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(String(localized: "About SlipNote")) {
                        showingAbout = true
                    }
                    Divider()
                    Button(String(localized: "Settings...")) {
                        showingSettings = true
                    }
                    .keyboardShortcut(",", modifiers: .command)
                    Divider()
                    Button(String(localized: "Quit SlipNote")) {
                        NSApp.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: .command)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showingAbout) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(String(localized: "Done")) {
                        showingAbout = false
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding()

                LicenseView()
            }
            .frame(width: 500, height: 550)
        }
        .alert(String(localized: "Empty Trash?"), isPresented: $showEmptyTrashAlert) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Empty Trash"), role: .destructive) {
                appState.emptyTrash()
            }
        } message: {
            Text("This will permanently delete all items in Trash. This action cannot be undone.", comment: "Empty trash confirmation")
        }
        .onChange(of: selectedSlipIndex) { _, newIndex in
            // Load versions for newly selected slip
            selectedVersionIndex = 0
            if newIndex < filteredSlips.count {
                loadVersionsForSlip(filteredSlips[newIndex])
            } else {
                selectedSlipVersions = []
            }
        }
    }

    private func loadVersionsForSlip(_ slip: Slip) {
        // Load versions asynchronously to avoid blocking UI
        let slipId = slip.id
        let currentIndex = selectedSlipIndex  // Capture current index on main thread

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let versions = try DatabaseService.shared.fetchVersions(for: slip)
                DispatchQueue.main.async { [weak appState] in
                    // Only update if still viewing the same slip (compare IDs, not indices)
                    guard appState != nil else { return }
                    let currentSlips = self.filteredSlips
                    if currentIndex < currentSlips.count && currentSlips[currentIndex].id == slipId {
                        self.selectedSlipVersions = versions
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.selectedSlipVersions = []
                    Logger.shared.error("Failed to load versions: \(error.localizedDescription)")
                }
            }
        }
    }

    private func focusSearchField() {
        isSearchFocused = true
    }

    private func focusSearchFieldInWindow(_ window: NSWindow) {
        // Recursively find NSTextField in view hierarchy
        func findTextField(in view: NSView) -> NSTextField? {
            // Check if this is an editable text field
            if let textField = view as? NSTextField, textField.isEditable {
                return textField
            }
            // Also check for NSSearchField
            if let searchField = view as? NSSearchField {
                return searchField
            }
            for subview in view.subviews {
                if let found = findTextField(in: subview) {
                    return found
                }
            }
            return nil
        }

        // Search in content view
        if let contentView = window.contentView,
           let textField = findTextField(in: contentView) {
            Logger.shared.info("Found TextField in contentView, making first responder")
            window.makeFirstResponder(textField)
            return
        }

        // Search in toolbar views
        if let toolbar = window.toolbar {
            for item in toolbar.items {
                if let view = item.view, let textField = findTextField(in: view) {
                    Logger.shared.info("Found TextField in toolbar, making first responder")
                    window.makeFirstResponder(textField)
                    return
                }
            }
        }

        // Try to find any NSTextField in the entire window
        if let contentView = window.contentView {
            // Use a broader search - find all subviews recursively
            var allViews: [NSView] = [contentView]
            var index = 0
            while index < allViews.count {
                let view = allViews[index]
                allViews.append(contentsOf: view.subviews)
                index += 1
            }

            Logger.shared.info("Total views found: \(allViews.count)")
            for view in allViews {
                let typeName = String(describing: type(of: view))
                if typeName.contains("TextField") || typeName.contains("SearchField") {
                    Logger.shared.info("Found view of type: \(typeName)")
                    if let textField = view as? NSTextField {
                        window.makeFirstResponder(textField)
                        return
                    }
                }
            }
        }

        Logger.shared.warning("TextField not found in window")
    }

    private func navigateCategory(up: Bool) {
        let activeCategories = appState.categories.filter { !$0.name.isEmpty }
        guard !activeCategories.isEmpty else { return }

        // Build list: nil (All) + category IDs
        var categoryList: [Int?] = [nil]
        categoryList.append(contentsOf: activeCategories.map { $0.id })

        // Find current index
        let currentIndex = categoryList.firstIndex(where: { $0 == appState.selectedCategoryFilter }) ?? 0

        // Navigate
        let newIndex: Int
        if up {
            newIndex = currentIndex > 0 ? currentIndex - 1 : categoryList.count - 1
        } else {
            newIndex = currentIndex < categoryList.count - 1 ? currentIndex + 1 : 0
        }

        appState.selectedCategoryFilter = categoryList[newIndex]
        appState.loadSlips()
        selectedSlipIndex = 0
    }

    private func createNewSlip() {
        // Create a new empty slip in the current category (or Inbox)
        let categoryId = appState.selectedCategoryFilter ?? Category.inboxId
        let newSlip = Slip(content: "", categoryId: categoryId)

        do {
            try DatabaseService.shared.insertSlip(newSlip)
            appState.loadSlips()

            // Open the new slip in edit mode
            openInEditMode = true
            selectedSlipForDetail = newSlip
        } catch {
            Logger.shared.error("Failed to create new slip: \(error.localizedDescription)")
        }
    }

    private func moveToTrash(_ slip: Slip) {
        appState.moveSlip(slip, toCategoryId: Category.trashId)
        // Adjust selection index if needed
        if selectedSlipIndex >= filteredSlips.count {
            selectedSlipIndex = max(0, filteredSlips.count - 1)
        }
    }

    private func slipSelectionForDrag(_ slip: Slip) -> SlipSelection {
        // If the slip is in the selection, drag all selected slips
        if selectedSlipIds.contains(slip.id) {
            let slips = filteredSlips.filter { selectedSlipIds.contains($0.id) }
            return SlipSelection(slips: slips)
        }
        // Otherwise just drag the single slip
        return SlipSelection(slips: [slip])
    }

    private func handleSlipSelectionDrop(_ selection: SlipSelection, categoryId: Int) {
        for slip in selection.slips {
            appState.moveSlip(slip, toCategoryId: categoryId)
        }
        selectedSlipIds.removeAll()
    }

    // MARK: - Export

    private func exportCategoryToMarkdown(_ category: Category) {
        // Fetch slips for this category
        do {
            let slips = try DatabaseService.shared.fetchAllSlips(categoryId: category.id)
            guard !slips.isEmpty else {
                // No slips to export
                return
            }

            // Generate markdown content
            let markdown = generateMarkdown(for: slips, category: category)

            // Show save panel
            let savePanel = NSSavePanel()
            savePanel.title = String(localized: "Export to Markdown")
            savePanel.nameFieldStringValue = "\(category.name).md"
            savePanel.allowedContentTypes = [.plainText]
            savePanel.canCreateDirectories = true

            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    do {
                        try markdown.write(to: url, atomically: true, encoding: .utf8)
                        Logger.shared.info("Exported \(slips.count) slips to \(url.path)")
                    } catch {
                        Logger.shared.error("Failed to export: \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            Logger.shared.error("Failed to fetch slips for export: \(error.localizedDescription)")
        }
    }

    private func generateMarkdown(for slips: [Slip], category: Category? = nil) -> String {
        var markdown = "\n"  // Start with empty line

        if let category = category {
            markdown = "\n# \(category.name)\n\n"
        }

        for (index, slip) in slips.enumerated() {
            // Add separator between slips (not before first one)
            if index > 0 {
                markdown += "---\n\n"
            }

            markdown += "## \(slip.title)\n\n"
            markdown += "**\(slip.timestamp)**\n\n"

            // Get content body (excluding first line which is the title)
            let lines = slip.content.components(separatedBy: "\n")
            if lines.count > 1 {
                let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    markdown += "\(body)\n\n"
                }
            }
        }

        return markdown
    }

    private func copySelectedSlipsToClipboard() {
        var slipsToCopy: [Slip] = []

        // If multiple slips are selected, copy all of them
        if !selectedSlipIds.isEmpty {
            slipsToCopy = filteredSlips.filter { selectedSlipIds.contains($0.id) }
        } else if selectedSlipIndex < filteredSlips.count {
            // Otherwise copy the currently highlighted slip
            slipsToCopy = [filteredSlips[selectedSlipIndex]]
        }

        guard !slipsToCopy.isEmpty else { return }

        let markdown = generateMarkdown(for: slipsToCopy)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)

        Logger.shared.info("Copied \(slipsToCopy.count) slip(s) to clipboard")
    }

    private func exportSlipsToMarkdown(_ slip: Slip) {
        var slipsToExport: [Slip] = []

        // If multiple slips are selected and clicked slip is in selection, export all selected
        if !selectedSlipIds.isEmpty && selectedSlipIds.contains(slip.id) {
            slipsToExport = filteredSlips.filter { selectedSlipIds.contains($0.id) }
        } else {
            // Otherwise export only the clicked slip
            slipsToExport = [slip]
        }

        guard !slipsToExport.isEmpty else { return }

        let markdown = generateMarkdown(for: slipsToExport)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]

        // Generate filename based on content
        if slipsToExport.count == 1 {
            let title = slipsToExport[0].title.replacingOccurrences(of: "/", with: "-")
            savePanel.nameFieldStringValue = "\(title).md"
        } else {
            savePanel.nameFieldStringValue = "SlipNote_Export_\(slipsToExport.count)_slips.md"
        }

        if savePanel.runModal() == .OK, let url = savePanel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                Logger.shared.info("Exported \(slipsToExport.count) slip(s) to \(url.path)")
            } catch {
                Logger.shared.error("Failed to export: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Keyboard & Mouse Shortcuts

    @State private var keyboardMonitor: Any?
    @State private var mouseMonitor: Any?

    private func setupKeyboardShortcuts() {
        // Keyboard monitor
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only handle events when not in input panel
            guard let keyWindow = NSApp.keyWindow,
                  !(keyWindow is InputPanel) else {
                return event
            }

            // Skip if settings sheet is showing
            if showingSettings {
                return event
            }

            // Cmd+F = Focus search field (skip when editing)
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers?.lowercased(),
               chars == "f" {
                // Don't handle Cmd+F when editing - let text editor handle it
                if detailState.isEditing {
                    return event
                }
                selectedSlipForDetail = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = NSApp.keyWindow {
                        self.focusSearchFieldInWindow(window)
                    }
                }
                return nil
            }

            // Detail view mode shortcuts
            if selectedSlipForDetail != nil {
                // ESC = Go back (when not editing)
                if event.keyCode == 53 && !detailState.isEditing {
                    selectedSlipForDetail = nil
                    openInEditMode = false
                    return nil
                }

                // Cmd+Enter = Enter edit mode (when not editing)
                if event.keyCode == 36 && event.modifierFlags.contains(.command) && !detailState.isEditing {
                    detailState.startEdit()
                    return nil
                }

                // Left arrow = Next version (newer)
                if event.keyCode == 123 && !detailState.isEditing && detailState.hasVersions {
                    detailState.navigateVersion(forward: true)
                    return nil
                }

                // Right arrow = Previous version (older)
                if event.keyCode == 124 && !detailState.isEditing && detailState.hasVersions {
                    detailState.navigateVersion(forward: false)
                    return nil
                }

                // Let other events pass through (for text editing etc)
                return event
            }

            // Option+0-9 = Move selected slip(s) to category
            if event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.command) {
                if let char = event.charactersIgnoringModifiers?.first,
                   let digit = Int(String(char)),
                   digit >= 0 && digit <= 9 {
                    if appState.categories.contains(where: { $0.id == digit && !$0.name.isEmpty }) {
                        // Move multi-selected slips or single selected slip
                        if !selectedSlipIds.isEmpty {
                            let slipsToMove = filteredSlips.filter { selectedSlipIds.contains($0.id) }
                            for slip in slipsToMove {
                                appState.moveSlip(slip, toCategoryId: digit)
                            }
                            selectedSlipIds.removeAll()
                        } else if selectedSlipIndex < filteredSlips.count {
                            let slip = filteredSlips[selectedSlipIndex]
                            appState.moveSlip(slip, toCategoryId: digit)
                        }
                        return nil
                    }
                }
            }

            // Cmd+0-9 = Toggle category filter
            if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.option) {
                if let char = event.charactersIgnoringModifiers?.first,
                   let digit = Int(String(char)),
                   digit >= 0 && digit <= 9 {
                    if appState.categories.contains(where: { $0.id == digit && !$0.name.isEmpty }) {
                        // Toggle filter: if already selected, deselect (show all)
                        if appState.selectedCategoryFilter == digit {
                            appState.selectedCategoryFilter = nil
                        } else {
                            appState.selectedCategoryFilter = digit
                        }
                        appState.loadSlips()
                        selectedSlipIndex = 0
                        return nil
                    }
                }
            }

            // Cmd+Up = Previous category
            if event.keyCode == 126 && event.modifierFlags.contains(.command) {
                navigateCategory(up: true)
                return nil
            }

            // Cmd+Down = Next category
            if event.keyCode == 125 && event.modifierFlags.contains(.command) {
                navigateCategory(up: false)
                return nil
            }

            // Up arrow = Previous slip
            if event.keyCode == 126 {
                if !filteredSlips.isEmpty {
                    // Clear multi-selection and navigate from last selected
                    selectedSlipIds.removeAll()
                    isKeyboardNavigation = true
                    selectedSlipIndex = max(0, selectedSlipIndex - 1)
                }
                return nil
            }

            // Down arrow = Next slip
            if event.keyCode == 125 {
                if !filteredSlips.isEmpty {
                    // Clear multi-selection and navigate from last selected
                    selectedSlipIds.removeAll()
                    isKeyboardNavigation = true
                    selectedSlipIndex = min(filteredSlips.count - 1, selectedSlipIndex + 1)
                }
                return nil
            }

            // Enter = Open selected slip (ignore if multi-selection)
            if event.keyCode == 36 && !event.modifierFlags.contains(.command) {
                if selectedSlipIds.isEmpty && !filteredSlips.isEmpty && selectedSlipIndex < filteredSlips.count {
                    selectedSlipForDetail = filteredSlips[selectedSlipIndex]
                }
                return nil
            }

            // Cmd+Enter = Open selected slip in edit mode (ignore if multi-selection)
            if event.keyCode == 36 && event.modifierFlags.contains(.command) {
                if selectedSlipIds.isEmpty && !filteredSlips.isEmpty && selectedSlipIndex < filteredSlips.count {
                    openInEditMode = true
                    selectedSlipForDetail = filteredSlips[selectedSlipIndex]
                }
                return nil
            }

            // Cmd+N = Create new slip in edit mode
            if let chars = event.charactersIgnoringModifiers?.lowercased(),
               chars == "n" {
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if modifiers.contains(.command) && !modifiers.contains(.shift) {
                    createNewSlip()
                    return nil
                }
            }

            // Cmd+T = Toggle Trash filter
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers?.lowercased(),
               chars == "t" {
                if appState.selectedCategoryFilter == Category.trashId {
                    appState.selectedCategoryFilter = nil
                } else {
                    appState.selectedCategoryFilter = Category.trashId
                }
                appState.loadSlips()
                selectedSlipIndex = 0
                return nil
            }

            // Cmd+, = Open Settings
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers,
               chars == "," {
                showingSettings = true
                return nil
            }

            // Cmd+Delete = Move selected slip(s) to Trash (Delete = keyCode 51)
            if event.keyCode == 51 && event.modifierFlags.contains(.command) {
                if !selectedSlipIds.isEmpty {
                    // Delete all multi-selected slips
                    let slipsToDelete = filteredSlips.filter { selectedSlipIds.contains($0.id) }
                    for slip in slipsToDelete {
                        appState.moveSlip(slip, toCategoryId: Category.trashId)
                    }
                    selectedSlipIds.removeAll()
                    // Adjust selection index if needed
                    if selectedSlipIndex >= filteredSlips.count {
                        selectedSlipIndex = max(0, filteredSlips.count - 1)
                    }
                } else if !filteredSlips.isEmpty && selectedSlipIndex < filteredSlips.count {
                    let slip = filteredSlips[selectedSlipIndex]
                    moveToTrash(slip)
                }
                return nil
            }

            // Cmd+C = Copy selected slips as markdown
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers?.lowercased(),
               chars == "c" {
                copySelectedSlipsToClipboard()
                return nil
            }

            // Cmd+P = Toggle pin for selected slip
            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers?.lowercased(),
               chars == "p" {
                if !filteredSlips.isEmpty && selectedSlipIndex < filteredSlips.count {
                    let slip = filteredSlips[selectedSlipIndex]
                    appState.togglePin(slip)
                }
                return nil
            }

            // ESC = Clear multi-selection, or clear search and reset category filter
            if event.keyCode == 53 {
                if !selectedSlipIds.isEmpty {
                    // First ESC: clear multi-selection
                    selectedSlipIds.removeAll()
                } else {
                    // Second ESC: clear search and reset category filter
                    searchText = ""
                    appState.selectedCategoryFilter = nil
                    appState.loadSlips()
                    selectedSlipIndex = 0
                }
                return nil
            }

            return event
        }
    }

    private func removeKeyboardShortcuts() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
    }

    // MARK: - Sidebar

    private var sidebarView: some View {
        List(selection: Binding(
            get: { appState.selectedCategoryFilter },
            set: { newValue in
                appState.selectedCategoryFilter = newValue
                appState.loadSlips()
                selectedSlipIndex = 0
            }
        )) {
            // All category (ESC to reset, Cmd+Arrow to navigate)
            HStack {
                Text("All", comment: "All categories filter")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                Spacer()
                Text("⌘↑↓")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(appState.selectedCategoryFilter == nil ? categorySelectedBgOpacity : categoryBgOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(appState.selectedCategoryFilter == nil ? Color.accentColor : Color.accentColor.opacity(0.3), lineWidth: appState.selectedCategoryFilter == nil ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture {
                appState.selectedCategoryFilter = nil
                appState.loadSlips()
                selectedSlipIndex = 0
            }
            .tag(nil as Int?)

            Section(String(localized: "Categories")) {
                ForEach(appState.categories.filter { !$0.name.isEmpty && $0.id != Category.trashId }) { category in
                    let catColor = category.color ?? Color.accentColor
                    HStack {
                        Text(category.name)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("⌘\(category.id)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(catColor.opacity(dropTargetCategoryId == category.id ? 0.5 : (appState.selectedCategoryFilter == category.id ? categorySelectedBgOpacity : categoryBgOpacity)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(dropTargetCategoryId == category.id ? catColor : (appState.selectedCategoryFilter == category.id ? catColor : catColor.opacity(0.3)), lineWidth: dropTargetCategoryId == category.id || appState.selectedCategoryFilter == category.id ? 2 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .tag(category.id as Int?)
                    .dropDestination(for: SlipSelection.self) { selections, _ in
                        for selection in selections {
                            handleSlipSelectionDrop(selection, categoryId: category.id)
                        }
                        dropTargetCategoryId = nil
                        return true
                    } isTargeted: { isTargeted in
                        dropTargetCategoryId = isTargeted ? category.id : (dropTargetCategoryId == category.id ? nil : dropTargetCategoryId)
                    }
                    .contextMenu {
                        Button {
                            exportCategoryToMarkdown(category)
                        } label: {
                            Label(String(localized: "Export to Markdown"), systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }

            // Trash section (at bottom with ⌘T shortcut)
            if appState.categories.contains(where: { $0.id == Category.trashId }) {
                Section {
                    let trashColor = Color.gray
                    HStack {
                        HStack(spacing: 4) {
                            Text("🗑️")
                                .font(.system(size: 12))
                            Text("Trash")
                                .font(.system(size: 13))
                        }
                        Spacer()
                        // Show trash count
                        if appState.trashCount() > 0 {
                            Text("\(appState.trashCount())")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Text("⌘T")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(trashColor.opacity(dropTargetCategoryId == Category.trashId ? 0.5 : (appState.selectedCategoryFilter == Category.trashId ? categorySelectedBgOpacity : categoryBgOpacity)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(dropTargetCategoryId == Category.trashId ? Color.red : (appState.selectedCategoryFilter == Category.trashId ? Color.red : trashColor.opacity(0.3)), lineWidth: dropTargetCategoryId == Category.trashId || appState.selectedCategoryFilter == Category.trashId ? 2 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.selectedCategoryFilter = Category.trashId
                        appState.loadSlips()
                        selectedSlipIndex = 0
                    }
                    .tag(Category.trashId as Int?)
                    .dropDestination(for: SlipSelection.self) { selections, _ in
                        for selection in selections {
                            handleSlipSelectionDrop(selection, categoryId: Category.trashId)
                        }
                        dropTargetCategoryId = nil
                        return true
                    } isTargeted: { isTargeted in
                        dropTargetCategoryId = isTargeted ? Category.trashId : (dropTargetCategoryId == Category.trashId ? nil : dropTargetCategoryId)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            showEmptyTrashAlert = true
                        } label: {
                            Text("Empty Trash", comment: "Empty trash context menu")
                        }
                        .disabled(appState.trashCount() == 0)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Slip List

    private var slipListView: some View {
        VStack(spacing: 0) {
            // Slips list
            if filteredSlips.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(filteredSlips.enumerated()), id: \.element.id) { index, slip in
                            SlipCardView(
                                slip: slip,
                                category: appState.categories.first { $0.id == slip.categoryId },
                                isSelected: index == selectedSlipIndex || selectedSlipIds.contains(slip.id),
                                versionContent: index == selectedSlipIndex && selectedVersionIndex > 0 && selectedVersionIndex <= selectedSlipVersions.count
                                    ? selectedSlipVersions[selectedVersionIndex - 1].content
                                    : nil,
                                versionIndex: index == selectedSlipIndex ? selectedVersionIndex : 0,
                                totalVersions: index == selectedSlipIndex ? selectedSlipVersions.count : 0
                            )
                            .id(slip.id)
                            .draggable(slipSelectionForDrag(slip)) {
                                // Drag preview
                                let count = selectedSlipIds.contains(slip.id) ? max(selectedSlipIds.count, 1) : 1
                                HStack(spacing: 4) {
                                    Image(systemName: count > 1 ? "doc.on.doc" : "doc.text")
                                    Text(count > 1 ? "\(count) slips" : slip.title)
                                        .lineLimit(1)
                                }
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                // Require more movement before drag starts (increased for better click detection)
                                DragGesture(minimumDistance: 25)
                            )
                            .onTapGesture {
                                let now = Date()
                                let flags = NSEvent.modifierFlags

                                // Double-click detection (same slip within 0.3s)
                                if lastClickedSlipId == slip.id && now.timeIntervalSince(lastClickTime) < 0.3 {
                                    selectedSlipForDetail = slip
                                    lastClickedSlipId = nil
                                    return
                                }

                                // Update last click tracking
                                lastClickedSlipId = slip.id
                                lastClickTime = now

                                if flags.contains(.command) {
                                    // Cmd+Click = toggle selection
                                    // If starting multi-selection by clicking a different slip,
                                    // add the currently selected slip first
                                    if selectedSlipIds.isEmpty && selectedSlipIndex < filteredSlips.count && index != selectedSlipIndex {
                                        selectedSlipIds.insert(filteredSlips[selectedSlipIndex].id)
                                    }
                                    // Toggle the clicked slip
                                    if selectedSlipIds.contains(slip.id) {
                                        selectedSlipIds.remove(slip.id)
                                    } else {
                                        selectedSlipIds.insert(slip.id)
                                    }
                                    selectedSlipIndex = index
                                } else if flags.contains(.shift) {
                                    // Shift+Click = range selection
                                    let start = min(selectedSlipIndex, index)
                                    let end = max(selectedSlipIndex, index)
                                    for i in start...end {
                                        if i < filteredSlips.count {
                                            selectedSlipIds.insert(filteredSlips[i].id)
                                        }
                                    }
                                } else {
                                    // Single click = select only
                                    selectedSlipIds.removeAll()
                                    selectedSlipIndex = index
                                }
                            }
                            .contextMenu {
                                slipContextMenu(for: slip)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: selectedSlipIndex) { _, newIndex in
                    if isKeyboardNavigation && newIndex < filteredSlips.count {
                        withAnimation {
                            proxy.scrollTo(filteredSlips[newIndex].id)
                        }
                        isKeyboardNavigation = false
                    }
                }
                }
            }
        }
    }

    private var filteredSlips: [Slip] {
        if searchText.isEmpty {
            return appState.slips
        } else {
            return appState.searchResults
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Text("---")
                .font(.system(size: 32, weight: .light, design: .monospaced))
                .foregroundColor(.secondary)

            if searchText.isEmpty {
                Text("No slips yet", comment: "Empty state title")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Press Cmd+Shift+N to create your first slip", comment: "Empty state subtitle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No results found", comment: "Search empty state")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Try a different search term", comment: "Search empty state subtitle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func slipContextMenu(for slip: Slip) -> some View {
        Button {
            selectedSlipForDetail = slip
        } label: {
            Text("View", comment: "Context menu view action")
        }

        Button {
            appState.togglePin(slip)
        } label: {
            if slip.isPinned {
                Label(String(localized: "Unpin"), systemImage: "pin.slash")
            } else {
                Label(String(localized: "Pin to Top"), systemImage: "pin")
            }
        }

        Divider()

        Button {
            exportSlipsToMarkdown(slip)
        } label: {
            Label(String(localized: "Export to Markdown"), systemImage: "square.and.arrow.up")
        }

        Divider()

        Menu(String(localized: "Move to...")) {
            ForEach(appState.categories.filter { !$0.name.isEmpty && $0.id != slip.categoryId && $0.id != Category.trashId }) { category in
                Button {
                    appState.moveSlip(slip, toCategoryId: category.id)
                } label: {
                    Text("(\(category.id)) \(category.name)")
                }
            }
        }

        Divider()

        // Show "Move to Trash" for non-trash items, "Delete Permanently" for trash items
        if slip.categoryId != Category.trashId {
            Button {
                moveToTrash(slip)
            } label: {
                Text("Move to Trash", comment: "Context menu move to trash")
            }
        } else {
            // Restore from Trash
            Button {
                appState.moveSlip(slip, toCategoryId: Category.inboxId)
            } label: {
                Text("Restore", comment: "Context menu restore from trash")
            }
        }

        Button(role: .destructive) {
            appState.deleteSlip(slip)
        } label: {
            Text("Delete Permanently", comment: "Context menu delete permanently")
        }
    }
}

// MARK: - Slip Card View

struct SlipCardView: View, Equatable {
    let slip: Slip
    let category: Category?
    let isSelected: Bool
    let versionContent: String?
    let versionIndex: Int
    let totalVersions: Int
    let categoryColor: Color

    init(slip: Slip, category: Category?, isSelected: Bool, versionContent: String? = nil, versionIndex: Int = 0, totalVersions: Int = 0) {
        self.slip = slip
        self.category = category
        self.isSelected = isSelected
        self.versionContent = versionContent
        self.versionIndex = versionIndex
        self.totalVersions = totalVersions
        self.categoryColor = category?.color ?? Color.accentColor
    }

    static func == (lhs: SlipCardView, rhs: SlipCardView) -> Bool {
        lhs.slip.id == rhs.slip.id &&
        lhs.slip.content == rhs.slip.content &&
        lhs.slip.isPinned == rhs.slip.isPinned &&
        lhs.isSelected == rhs.isSelected &&
        lhs.versionIndex == rhs.versionIndex &&
        lhs.category?.id == rhs.category?.id
    }

    // Get content body (everything after the first line)
    private var contentBody: String {
        let content = versionContent ?? slip.content
        let lines = content.components(separatedBy: "\n")
        if lines.count > 1 {
            return lines.dropFirst().joined(separator: "\n")
        }
        return ""
    }

    // Get title from current content
    private var displayTitle: String {
        let content = versionContent ?? slip.content
        return content.components(separatedBy: "\n").first ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                // Pin indicator
                if slip.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }

                if let cat = category, !cat.name.isEmpty {
                    Text("\(cat.id)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 14, height: 14)
                        .background(categoryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                // Version indicator (right after title)
                if versionIndex > 0 {
                    Text("v\(totalVersions - versionIndex + 1)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                // Version count indicator (only shown for selected slip with versions)
                if isSelected && totalVersions > 0 {
                    Text("v\(totalVersions + 1)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text(slip.timestamp)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Content preview (body only, excluding title)
            if !contentBody.isEmpty {
                Text(contentBody)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(category?.color != nil
                    ? categoryColor.opacity(isSelected ? 0.25 : 0.1)
                    : (isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? categoryColor : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    ViewModeView()
        .environmentObject(AppState())
}
