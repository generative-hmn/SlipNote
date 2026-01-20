import Foundation
import AppKit
import HotKey
import Carbon.HIToolbox

enum AppMode: String, Codable, CaseIterable {
    case menuBarOnly = "menuBarOnly"
    case dockOnly = "dockOnly"
    case both = "both"

    var displayName: String {
        switch self {
        case .menuBarOnly: return "Menu Bar Only"
        case .dockOnly: return "Dock Only"
        case .both: return "Both"
        }
    }
}

enum BackupInterval: String, Codable, CaseIterable {
    case off = "off"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .off: return nil
        case .daily: return 24 * 60 * 60
        case .weekly: return 7 * 24 * 60 * 60
        case .monthly: return 30 * 24 * 60 * 60
        }
    }
}

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var displayString: String {
        var parts: [String] = []

        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }

        if let keyString = keyCodeToString(keyCode) {
            parts.append(keyString)
        }

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String? {
        let keyMap: [UInt32: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
            0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
            0x2F: ".", 0x32: "`", 0x24: "↩", 0x30: "⇥", 0x31: "Space",
            0x33: "⌫", 0x35: "⎋", 0x7A: "F1", 0x78: "F2", 0x63: "F3",
            0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        ]
        return keyMap[keyCode]
    }

    func toHotKeyModifiers() -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    func toHotKeyKey() -> Key? {
        return Key(carbonKeyCode: keyCode)
    }

    // Default shortcuts
    static let defaultInputMode = KeyboardShortcut(
        keyCode: 0x2D, // N
        modifiers: UInt32(cmdKey | shiftKey)
    )

    static let defaultBrowseMode = KeyboardShortcut(
        keyCode: 0x0B, // B
        modifiers: UInt32(cmdKey | shiftKey)
    )
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var inputModeShortcut: KeyboardShortcut {
        didSet { saveShortcuts() }
    }

    @Published var browseModeShortcut: KeyboardShortcut {
        didSet { saveShortcuts() }
    }

    @Published var customDatabasePath: String? {
        didSet { saveDatabasePath() }
    }

    @Published var appMode: AppMode {
        didSet { saveAppMode() }
    }

    @Published var backupInterval: BackupInterval {
        didSet { saveBackupInterval() }
    }

    // Track if any shortcut recorder is active
    @Published var isRecordingShortcut = false

    // Track if user has seen the license
    var hasSeenLicense: Bool {
        get { defaults.bool(forKey: hasSeenLicenseKey) }
        set { defaults.set(newValue, forKey: hasSeenLicenseKey) }
    }

    // Last backup date
    var lastBackupDate: Date? {
        get { defaults.object(forKey: lastBackupDateKey) as? Date }
        set { defaults.set(newValue, forKey: lastBackupDateKey) }
    }

    private let defaults = UserDefaults.standard
    private let inputModeKey = "inputModeShortcut"
    private let browseModeKey = "browseModeShortcut"
    private let databasePathKey = "customDatabasePath"
    private let hasSeenLicenseKey = "hasSeenLicense"
    private let appModeKey = "appMode"
    private let backupIntervalKey = "backupInterval"
    private let lastBackupDateKey = "lastBackupDate"

    var onShortcutsChanged: (() -> Void)?
    var onAppModeChanged: (() -> Void)?
    var onBackupIntervalChanged: (() -> Void)?

    private init() {
        // Load saved shortcuts or use defaults
        if let data = defaults.data(forKey: inputModeKey),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            inputModeShortcut = shortcut
        } else {
            inputModeShortcut = .defaultInputMode
        }

        if let data = defaults.data(forKey: browseModeKey),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            browseModeShortcut = shortcut
        } else {
            browseModeShortcut = .defaultBrowseMode
        }

        // Load custom database path
        customDatabasePath = defaults.string(forKey: databasePathKey)

        // Load app mode
        if let modeString = defaults.string(forKey: appModeKey),
           let mode = AppMode(rawValue: modeString) {
            appMode = mode
        } else {
            appMode = .menuBarOnly
        }

        // Load backup interval
        if let intervalString = defaults.string(forKey: backupIntervalKey),
           let interval = BackupInterval(rawValue: intervalString) {
            backupInterval = interval
        } else {
            backupInterval = .off
        }
    }

    private func saveAppMode() {
        defaults.set(appMode.rawValue, forKey: appModeKey)
        onAppModeChanged?()
    }

    private func saveBackupInterval() {
        defaults.set(backupInterval.rawValue, forKey: backupIntervalKey)
        onBackupIntervalChanged?()
    }

    private func saveShortcuts() {
        if let data = try? JSONEncoder().encode(inputModeShortcut) {
            defaults.set(data, forKey: inputModeKey)
        }
        if let data = try? JSONEncoder().encode(browseModeShortcut) {
            defaults.set(data, forKey: browseModeKey)
        }
        onShortcutsChanged?()
    }

    private func saveDatabasePath() {
        if let path = customDatabasePath {
            defaults.set(path, forKey: databasePathKey)
        } else {
            defaults.removeObject(forKey: databasePathKey)
        }
    }

    // Get the current database directory path
    var databaseDirectoryPath: String {
        if let custom = customDatabasePath, !custom.isEmpty {
            return custom
        }
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportURL.appendingPathComponent("SlipNote").path
    }

    // Get the backup directory path
    var backupDirectoryPath: String {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportURL.appendingPathComponent("SlipNote/Backups").path
    }

    // Check if backup is needed
    func isBackupNeeded() -> Bool {
        guard let interval = backupInterval.seconds else { return false }
        guard let lastBackup = lastBackupDate else { return true }
        return Date().timeIntervalSince(lastBackup) >= interval
    }

    // Perform backup
    func performBackup() {
        let fileManager = FileManager.default
        let backupDir = URL(fileURLWithPath: backupDirectoryPath)
        let dbPath = URL(fileURLWithPath: databaseDirectoryPath).appendingPathComponent("slipnote.db")

        do {
            // Create backup directory if needed
            if !fileManager.fileExists(atPath: backupDir.path) {
                try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
            }

            // Create backup filename with timestamp
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timestamp = formatter.string(from: Date())
            let backupPath = backupDir.appendingPathComponent("slipnote_\(timestamp).db")

            // Copy database file
            try fileManager.copyItem(at: dbPath, to: backupPath)

            // Update last backup date
            lastBackupDate = Date()

            // Clean up old backups (keep last 10)
            cleanupOldBackups()

            NSLog("[AppSettings] Backup created: \(backupPath.lastPathComponent)")
        } catch {
            NSLog("[AppSettings] Backup failed: \(error.localizedDescription)")
        }
    }

    private func cleanupOldBackups() {
        let fileManager = FileManager.default
        let backupDir = URL(fileURLWithPath: backupDirectoryPath)

        do {
            let files = try fileManager.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "db" }
                .sorted { (a, b) -> Bool in
                    let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return dateA > dateB
                }

            // Remove backups beyond the 10 most recent
            if files.count > 10 {
                for file in files.dropFirst(10) {
                    try fileManager.removeItem(at: file)
                    NSLog("[AppSettings] Removed old backup: \(file.lastPathComponent)")
                }
            }
        } catch {
            NSLog("[AppSettings] Cleanup failed: \(error.localizedDescription)")
        }
    }
}
