import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case shortcuts = 0
    case categories = 1
    case data = 2
    case license = 3

    var title: String {
        switch self {
        case .shortcuts: return String(localized: "Shortcuts")
        case .categories: return String(localized: "Categories")
        case .data: return String(localized: "Data")
        case .license: return String(localized: "License")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedTab: SettingsTab = .shortcuts
    @State private var keyboardMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case .shortcuts:
                    ShortcutsSettingsView()
                case .categories:
                    CategoriesSettingsView()
                        .environmentObject(appState)
                case .data:
                    DataSettingsView()
                case .license:
                    LicenseView()
                        .frame(height: 400)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: selectedTab != .license)
        .focusEffectDisabled()
        .onAppear {
            setupKeyboardNavigation()
        }
        .onDisappear {
            removeKeyboardNavigation()
        }
    }

    private func setupKeyboardNavigation() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only handle events when Settings window is the key window
            // Skip if any other window type is active (InputPanel, browser, etc.)
            guard let keyWindow = NSApp.keyWindow,
                  !(keyWindow is InputPanel),
                  keyWindow.title != "SlipNote" else {
                return event
            }

            // Skip if recording shortcut
            if settings.isRecordingShortcut {
                return event
            }

            // Left arrow = Previous tab
            if event.keyCode == 123 {
                let currentIndex = selectedTab.rawValue
                if currentIndex > 0 {
                    selectedTab = SettingsTab(rawValue: currentIndex - 1) ?? selectedTab
                }
                return nil
            }

            // Right arrow = Next tab
            if event.keyCode == 124 {
                let currentIndex = selectedTab.rawValue
                if currentIndex < SettingsTab.allCases.count - 1 {
                    selectedTab = SettingsTab(rawValue: currentIndex + 1) ?? selectedTab
                }
                return nil
            }

            return event
        }
    }

    private func removeKeyboardNavigation() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Input Mode")
                            .font(.headline)
                        Text("Open quick capture window")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    ShortcutRecorderView(shortcut: $settings.inputModeShortcut)
                }
                .padding(.vertical, 4)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Browse Mode")
                            .font(.headline)
                        Text("Open slip browser window")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    ShortcutRecorderView(shortcut: $settings.browseModeShortcut)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("Click on a shortcut and press your desired key combination. Must include ⌘, ⌃, or ⌥.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Text("Reset to Defaults")
                    Spacer()
                    Button("Reset") {
                        settings.inputModeShortcut = .defaultInputMode
                        settings.browseModeShortcut = .defaultBrowseMode
                    }
                }
            }

            Section {
                Picker("App Mode", selection: $settings.appMode) {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("App Mode")
            } footer: {
                Text("Menu Bar Only: Hidden from Dock. Dock Only: Hidden from menu bar. Both: Shows in both locations.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Categories Settings

struct CategoriesSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var categories: [Category] = []

    // Filter out system categories (Trash)
    private var editableCategories: [Category] {
        categories.filter { $0.id != Category.trashId }
    }

    var body: some View {
        Form {
            Section {
                ForEach(editableCategories) { category in
                    HStack(spacing: 12) {
                        // Color picker
                        CategoryColorPicker(
                            selectedColor: Binding(
                                get: { category.colorHex },
                                set: { newColor in
                                    if let index = categories.firstIndex(where: { $0.id == category.id }) {
                                        categories[index].colorHex = newColor
                                        saveCategory(categories[index])
                                    }
                                }
                            )
                        )

                        // Name
                        TextField("Category name", text: Binding(
                            get: { category.name },
                            set: { newValue in
                                if let index = categories.firstIndex(where: { $0.id == category.id }) {
                                    categories[index].name = newValue
                                    saveCategory(categories[index])
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        // Default indicator
                        if category.id == Category.inboxId {
                            Text("Default")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(4)
                        }

                        Spacer()

                        // Shortcut (right-aligned)
                        Text("⌘\(category.id)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Categories (0-9)")
            } footer: {
                Text("Press ⌘+number to select a category when saving a slip. Empty categories are hidden.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadCategories()
        }
    }

    private func loadCategories() {
        do {
            categories = try DatabaseService.shared.fetchCategories()
        } catch {
            print("Failed to load categories: \(error)")
            categories = Category.defaults
        }
    }

    private func saveCategory(_ category: Category) {
        do {
            try DatabaseService.shared.updateCategory(category)
            appState.loadCategories()
        } catch {
            print("Failed to save category: \(error)")
        }
    }
}

// MARK: - Data Settings

struct DataSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var showExportAlert = false
    @State private var exportedPath: String?
    @State private var showRestartAlert = false

    private var displayPath: String {
        if let custom = settings.customDatabasePath, !custom.isEmpty {
            return custom
        }
        return "~/Library/Application Support/SlipNote/"
    }

    var body: some View {
        Form {
            Section("Export") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Export to Markdown")
                        Text("Export all slips as a Markdown file")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Export...") {
                        exportToMarkdown()
                    }
                }
            }

            Section("Database") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Database Location")
                            Text(displayPath)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Show in Finder") {
                            openDatabaseFolder()
                        }
                    }

                    HStack {
                        Button("Change Location...") {
                            chooseDatabaseLocation()
                        }
                        if settings.customDatabasePath != nil {
                            Button("Reset to Default") {
                                settings.customDatabasePath = nil
                                showRestartAlert = true
                            }
                        }
                    }

                    Text("Changing database location requires app restart. Existing data will not be migrated automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Backup & Restore") {
                HStack {
                    Text("Create Backup")
                    Spacer()
                    Button("Backup...") {
                        createBackup()
                    }
                }

                HStack {
                    Text("Restore from Backup")
                    Spacer()
                    Button("Restore...") {
                        restoreBackup()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Export Complete", isPresented: $showExportAlert) {
            Button("OK") {}
            if exportedPath != nil {
                Button("Show in Finder") {
                    if let path = exportedPath {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    }
                }
            }
        } message: {
            if let path = exportedPath {
                Text("Exported to: \(path)")
            }
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                restartApp()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Please restart SlipNote for the database location change to take effect.")
        }
    }

    private func exportToMarkdown() {
        do {
            let markdown = try DatabaseService.shared.exportToMarkdown()

            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.plainText]
            savePanel.nameFieldStringValue = "SlipNote_Export.md"

            if savePanel.runModal() == .OK, let url = savePanel.url {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                exportedPath = url.path
                showExportAlert = true
            }
        } catch {
            print("Export failed: \(error)")
        }
    }

    private func openDatabaseFolder() {
        let path = settings.databaseDirectoryPath
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    private func chooseDatabaseLocation() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Select"
        openPanel.message = "Choose a folder for the SlipNote database"

        if openPanel.runModal() == .OK, let url = openPanel.url {
            settings.customDatabasePath = url.path
            showRestartAlert = true
        }
    }

    private func createBackup() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.database]
        savePanel.nameFieldStringValue = "SlipNote_Backup_\(Date().formatted(.iso8601)).db"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let dbPath = URL(fileURLWithPath: settings.databaseDirectoryPath).appendingPathComponent("slipnote.db")

            do {
                try FileManager.default.copyItem(at: dbPath, to: url)
            } catch {
                print("Backup failed: \(error)")
            }
        }
    }

    private func restoreBackup() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.database]
        openPanel.allowsMultipleSelection = false

        if openPanel.runModal() == .OK, let url = openPanel.url {
            let dbPath = URL(fileURLWithPath: settings.databaseDirectoryPath).appendingPathComponent("slipnote.db")

            do {
                // Backup current before restore
                let backupPath = dbPath.appendingPathExtension("backup")
                try? FileManager.default.removeItem(at: backupPath)
                if FileManager.default.fileExists(atPath: dbPath.path) {
                    try FileManager.default.moveItem(at: dbPath, to: backupPath)
                }
                try FileManager.default.copyItem(at: url, to: dbPath)
                showRestartAlert = true
            } catch {
                print("Restore failed: \(error)")
            }
        }
    }

    private func restartApp() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        NSApp.terminate(nil)
    }
}

// MARK: - Category Color Picker

struct CategoryColorPicker: View {
    @Binding var selectedColor: String?
    @State private var showingPopover = false
    @State private var customColor: Color = .blue

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            Circle()
                .fill(selectedColor.flatMap { Color(hex: $0) } ?? Color.gray.opacity(0.3))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            VStack(spacing: 12) {
                Text("Choose Color")
                    .font(.headline)

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 5), spacing: 8) {
                    // Clear color option
                    Button {
                        selectedColor = nil
                        showingPopover = false
                    } label: {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                            )
                            .overlay(
                                Circle()
                                    .stroke(selectedColor == nil ? Color.primary : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)

                    // Preset colors
                    ForEach(Category.presetColors, id: \.self) { colorHex in
                        Button {
                            selectedColor = colorHex
                            showingPopover = false
                        } label: {
                            Circle()
                                .fill(Color(hex: colorHex) ?? Color.gray)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColor == colorHex ? Color.primary : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // Custom color picker
                HStack {
                    Text("Custom:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ColorPicker("", selection: $customColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: customColor) { _, newColor in
                            if let hex = newColor.toHex() {
                                selectedColor = hex
                            }
                        }

                    Button("Apply") {
                        if let hex = customColor.toHex() {
                            selectedColor = hex
                            showingPopover = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding()
            .frame(width: 200)
            .onAppear {
                // Initialize custom color from current selection
                if let hex = selectedColor, let color = Color(hex: hex) {
                    customColor = color
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
