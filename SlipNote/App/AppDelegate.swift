import AppKit
import SwiftUI
import HotKey
import Carbon.HIToolbox
import CoreSpotlight

// Notification for opening slip in edit mode
extension Notification.Name {
    static let openSlipInEditMode = Notification.Name("openSlipInEditMode")
    static let focusSearchField = Notification.Name("focusSearchField")
}

// Custom panel that can become key window even when borderless
final class InputPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var inputPanel: InputPanel?
    private var browseWindow: NSWindow?
    private var popover: NSPopover?
    private var inputHotKey: HotKey?
    private var browseHotKey: HotKey?
    private var previousApp: NSRunningApplication?
    private var backupTimer: Timer?

    // TIS Input Source with proper memory management
    // Using CFTypeRef-based approach for safer Core Foundation memory handling
    private var previousInputSourceRef: Unmanaged<TISInputSource>?

    private func captureInputSource() {
        // Release previous reference if exists
        previousInputSourceRef?.release()
        // Capture new reference (TISCopyCurrentKeyboardInputSource returns retained value)
        previousInputSourceRef = TISCopyCurrentKeyboardInputSource()
    }

    private func restoreInputSource() {
        guard let inputSourceRef = previousInputSourceRef else { return }
        let inputSource = inputSourceRef.takeUnretainedValue()
        TISSelectInputSource(inputSource)
    }

    private func clearInputSource() {
        previousInputSourceRef?.release()
        previousInputSourceRef = nil
    }

    let appState = AppState()
    private let settings = AppSettings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("SlipNote launched")
        setupMainMenu()
        setupMenuBar()
        setupGlobalHotKeys()
        setupDatabase()
        setupLocalKeyMonitor()
        applyAppMode()

        // Listen for shortcut changes
        settings.onShortcutsChanged = { [weak self] in
            Logger.shared.info("Shortcuts changed, re-registering hotkeys")
            self?.setupGlobalHotKeys()
        }

        // Listen for app mode changes
        settings.onAppModeChanged = { [weak self] in
            Logger.shared.info("App mode changed")
            self?.applyAppMode()
        }

        // Listen for backup interval changes
        settings.onBackupIntervalChanged = { [weak self] in
            Logger.shared.info("Backup interval changed")
            self?.setupBackupTimer()
        }

        // Setup auto backup
        setupBackupTimer()
        checkAndPerformBackup()

        // Index all slips for Spotlight
        SpotlightService.shared.indexAllSlips()

        // Hide input window when app loses focus
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        // Listen for close input window notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloseInputWindow),
            name: Notification.Name("closeInputWindow"),
            object: nil
        )
    }

    @objc private func handleCloseInputWindow() {
        hideInputWindow()
    }

    private func setupLocalKeyMonitor() {
        // Reserved for future local keyboard shortcuts
        // Cmd+L is now handled via menu item for better reliability
    }

    private func applyAppMode() {
        switch settings.appMode {
        case .menuBarOnly:
            NSApp.setActivationPolicy(.accessory)
            statusItem.isVisible = true
        case .dockOnly:
            NSApp.setActivationPolicy(.regular)
            statusItem.isVisible = false
        case .both:
            NSApp.setActivationPolicy(.regular)
            statusItem.isVisible = true
        }
    }

    // MARK: - Auto Backup

    private func setupBackupTimer() {
        backupTimer?.invalidate()
        backupTimer = nil

        guard settings.backupInterval != .off else { return }

        // Check every hour if backup is needed
        backupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkAndPerformBackup()
        }
    }

    private func checkAndPerformBackup() {
        if settings.isBackupNeeded() {
            Logger.shared.info("Performing scheduled backup")
            settings.performBackup()
        }
    }

    @objc private func appDidResignActive() {
        // Don't auto-hide on resign - let hideIfNoWindowsVisible handle it
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep app running as menu bar app
    }

    // MARK: - Spotlight Continuation

    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        if userActivity.activityType == CSSearchableItemActionType {
            if let slipId = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                Logger.shared.info("Opening slip from Spotlight: \(slipId)")
                openSlipFromSpotlight(slipId: slipId)
                return true
            }
        }
        return false
    }

    private func openSlipFromSpotlight(slipId: String) {
        // Find the slip and open it in browser
        do {
            let slips = try DatabaseService.shared.fetchAllSlips()
            if let slip = slips.first(where: { $0.id == slipId }) {
                appState.selectedSlip = slip
                showBrowseWindow()
            }
        } catch {
            Logger.shared.error("Failed to open slip from Spotlight: \(error.localizedDescription)")
        }
    }

    // MARK: - URL Scheme Handler

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        Logger.shared.info("Handling URL: \(url.absoluteString)")

        // Validate URL scheme
        guard url.scheme?.lowercased() == "slipnote" else {
            Logger.shared.warning("Invalid URL scheme: \(url.scheme ?? "nil")")
            return
        }

        let host = url.host?.lowercased() ?? ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let params = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        // Validate known hosts
        let validHosts = ["new", "browse", "search", "input"]
        if !host.isEmpty && !validHosts.contains(host) {
            Logger.shared.warning("Unknown URL host: \(host)")
            // Fall through to default behavior
        }

        switch host {
        case "new":
            // slipnote://new?content=text&category=1
            // Sanitize content - limit length to prevent abuse
            let content = String((params["content"] ?? "").prefix(100_000))
            let categoryId = Int(params["category"] ?? "0") ?? Category.inboxId

            // Validate category ID
            let validCategoryId = (0...10).contains(categoryId) ? categoryId : Category.inboxId

            if !content.isEmpty {
                appState.createSlip(content: content, categoryId: validCategoryId)
                Logger.shared.info("Created slip via URL scheme")
            } else {
                // Open input window for new slip
                showInputWindow()
            }

        case "browse":
            // slipnote://browse?category=1
            if let categoryStr = params["category"], let categoryId = Int(categoryStr) {
                // Validate category ID
                if (0...10).contains(categoryId) {
                    appState.selectedCategoryFilter = categoryId
                }
            }
            showBrowseWindow()

        case "search":
            // slipnote://search?query=keyword
            if let query = params["query"] {
                // Sanitize query - limit length
                let sanitizedQuery = String(query.prefix(1000))
                appState.search(query: sanitizedQuery)
                showBrowseWindow()
            }

        case "input":
            // slipnote://input
            showInputWindow()

        default:
            // Default: open browse window
            showBrowseWindow()
        }
    }

    /// Hide the app if no windows are visible
    func hideIfNoWindowsVisible() {
        let inputVisible = appState.isInputWindowVisible
        let browseVisible = browseWindow?.isVisible ?? false

        if !inputVisible && !browseVisible {
            NSApp.hide(nil)

            // Restore input source after a brief delay (after previous app becomes active)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.restoreInputSource()
                self?.clearInputSource()
            }
        }
    }

    // MARK: - Main Menu Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About SlipNote", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit SlipNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenu = NSMenu(title: "File")
        let newSlipItem = NSMenuItem(title: "New Slip", action: #selector(createNewSlipFromMenu), keyEquivalent: "n")
        fileMenu.addItem(newSlipItem)
        fileMenu.addItem(NSMenuItem.separator())
        let searchItem = NSMenuItem(title: "Search", action: #selector(focusSearchFromMenu), keyEquivalent: "f")
        searchItem.target = self
        fileMenu.addItem(searchItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu (for standard text editing)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func focusSearchFromMenu() {
        Logger.shared.info("focusSearchFromMenu called")
        // Open browse window if not visible, then focus search
        if browseWindow == nil || !browseWindow!.isVisible {
            showBrowseWindow()
        }
        Logger.shared.info("Posting focusSearchField notification")
        NotificationCenter.default.post(name: .focusSearchField, object: nil)
    }

    @objc private func createNewSlipFromMenu() {
        // If browser window is visible, create new slip there
        if let window = browseWindow, window.isVisible {
            let categoryId = appState.selectedCategoryFilter ?? Category.inboxId
            let newSlip = Slip(content: "New Slip\n", categoryId: categoryId)

            do {
                try DatabaseService.shared.insertSlip(newSlip)
                appState.loadSlips()

                // Post notification to open in edit mode
                NotificationCenter.default.post(name: .openSlipInEditMode, object: newSlip)
            } catch {
                Logger.shared.error("Failed to create new slip: \(error.localizedDescription)")
            }
        } else {
            // Otherwise show input window
            showInputWindow()
        }
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "SlipNote")
            button.action = #selector(toggleBrowseWindow)
            button.target = self
        }

        // Add right-click menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "New Slip", action: #selector(menuNewSlip), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Browse Slips", action: #selector(toggleBrowseWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit SlipNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = nil  // Left click shows window, right click shows menu

        // Handle right-click for menu
        if let button = statusItem.button {
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func menuNewSlip() {
        showInputWindow()
    }

    @objc private func openSettings() {
        // Find existing settings window (SwiftUI Settings windows have identifier containing "Settings")
        if let settingsWindow = NSApp.windows.first(where: {
            $0.identifier?.rawValue.contains("Settings") == true ||
            $0.title == "Settings" ||
            $0.title == String(localized: "Settings")
        }) {
            if settingsWindow.isVisible {
                settingsWindow.orderOut(nil)
            } else {
                settingsWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            // No settings window exists, create one
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Global HotKeys

    private func setupGlobalHotKeys() {
        // Clear existing hotkeys
        inputHotKey = nil
        browseHotKey = nil

        // Setup input mode hotkey (toggle)
        let inputShortcut = settings.inputModeShortcut
        if let key = inputShortcut.toHotKeyKey() {
            inputHotKey = HotKey(key: key, modifiers: inputShortcut.toHotKeyModifiers())
            inputHotKey?.keyDownHandler = { [weak self] in
                guard let self = self else { return }
                // Ignore hotkey while recording new shortcut in settings
                guard !self.settings.isRecordingShortcut else { return }
                // Capture the frontmost app and focused element BEFORE any window operations
                if self.inputPanel == nil || !self.inputPanel!.isVisible {
                    if let frontApp = NSWorkspace.shared.frontmostApplication,
                       frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                        self.previousApp = frontApp
                        // Capture the current input source (keyboard language)
                        self.captureInputSource()
                    }
                }
                self.toggleInputWindow()
            }
        }

        // Setup browse mode hotkey
        let browseShortcut = settings.browseModeShortcut
        if let key = browseShortcut.toHotKeyKey() {
            browseHotKey = HotKey(key: key, modifiers: browseShortcut.toHotKeyModifiers())
            browseHotKey?.keyDownHandler = { [weak self] in
                guard let self = self else { return }
                // Ignore hotkey while recording new shortcut in settings
                guard !self.settings.isRecordingShortcut else { return }
                // Capture state before opening browse window
                if self.browseWindow == nil || !self.browseWindow!.isVisible {
                    if let frontApp = NSWorkspace.shared.frontmostApplication,
                       frontApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                        self.previousApp = frontApp
                        self.captureInputSource()
                    }
                }
                self.toggleBrowseWindow()
            }
        }
    }

    // MARK: - Database

    private func setupDatabase() {
        do {
            try DatabaseService.shared.setup()
            Logger.shared.info("Database setup succeeded")
            // Load categories immediately after database setup
            appState.loadCategories()
        } catch {
            Logger.shared.error("Database setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Input Window

    private func toggleInputWindow() {
        if let panel = inputPanel, panel.isVisible {
            hideInputWindow()
        } else {
            showInputWindow()
        }
    }

    func showInputWindow() {
        Logger.shared.event("showInputWindow")

        // Restore activation policy if it was set to prohibited
        applyAppMode()

        Logger.shared.info("Current previousApp: \(previousApp?.localizedName ?? "nil")")

        // Fixed width for input window (using grid layout)
        let panelWidth = 600

        if inputPanel == nil {
            let contentView = InputWindowView()
                .environmentObject(appState)

            let panel = InputPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 100),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.contentView = NSHostingView(rootView: contentView)
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.level = .floating
            panel.hasShadow = false  // Use SwiftUI shadow instead
            panel.isMovableByWindowBackground = true  // Enable dragging
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false

            // Center on screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let panelFrame = panel.frame
                let x = screenFrame.midX - panelFrame.width / 2
                let y = screenFrame.midY - panelFrame.height / 2
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }

            inputPanel = panel
            Logger.shared.debug("Input panel created")
        } else {
            // Resize existing panel if category count changed
            if let panel = inputPanel, let screen = NSScreen.main {
                let newWidth = CGFloat(panelWidth)
                let currentFrame = panel.frame
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - newWidth / 2
                panel.setFrame(NSRect(x: x, y: currentFrame.origin.y, width: newWidth, height: currentFrame.height), display: true)
            }
        }

        inputPanel?.makeKeyAndOrderFront(nil)
        inputPanel?.makeFirstResponder(inputPanel?.contentView)
        NSApp.activate(ignoringOtherApps: true)
        appState.isInputWindowVisible = true
    }

    func hideInputWindow(restoreFocus: Bool = true) {
        // Close the panel properly
        inputPanel?.close()
        appState.isInputWindowVisible = false

        if restoreFocus {
            previousApp = nil
            // Note: previousInputSource is cleared in hideIfNoWindowsVisible after restore
            hideIfNoWindowsVisible()
        }
    }

    // MARK: - Browse Window

    @objc private func toggleBrowseWindow() {
        Logger.shared.event("toggleBrowseWindow")
        if let window = browseWindow, window.isVisible {
            hideBrowseWindow()
        } else {
            showBrowseWindow()
        }
    }

    private func hideBrowseWindow() {
        browseWindow?.orderOut(nil)
        Logger.shared.debug("Browse window hidden")

        // Force hide app since browse window is now hidden
        if !appState.isInputWindowVisible {
            NSApp.hide(nil)

            // Restore input source after hide
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.restoreInputSource()
                self?.clearInputSource()
            }
        } else {
            clearInputSource()
        }

        previousApp = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == browseWindow else { return }

        // Force hide app since browse window is closing
        if !appState.isInputWindowVisible {
            NSApp.hide(nil)

            // Restore input source after hide
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.restoreInputSource()
                self?.clearInputSource()
            }
        } else {
            clearInputSource()
        }

        previousApp = nil
    }

    private func showBrowseWindow() {
        Logger.shared.event("showBrowseWindow")

        // Restore activation policy if it was set to prohibited
        applyAppMode()

        // Close input window when opening browser (don't restore focus since we're opening another window)
        hideInputWindow(restoreFocus: false)

        if browseWindow == nil {
            let contentView = ViewModeView()
                .environmentObject(appState)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: contentView)
            window.title = "SlipNote"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 600, height: 400)

            // Center on screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowFrame = window.frame
                let x = screenFrame.midX - windowFrame.width / 2
                let y = screenFrame.midY - windowFrame.height / 2
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }

            browseWindow = window
            window.delegate = self
            Logger.shared.debug("Browse window created")
        }

        // Reload data when showing
        appState.loadSlips()
        appState.loadCategories()

        browseWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
