import Foundation
import GRDB
import SwiftUI

struct Category: Identifiable, Codable, Equatable {
    var id: Int
    var name: String
    var emoji: String?
    var sortOrder: Int
    var colorHex: String?

    enum CodingKeys: String, CodingKey {
        case id, name, emoji
        case sortOrder = "sort_order"
        case colorHex = "color_hex"
    }

    var displayName: String {
        return name
    }

    var shortDisplay: String {
        return "\(id) : \(name)"
    }

    // Convert hex to SwiftUI Color
    var color: Color? {
        guard let hex = colorHex, !hex.isEmpty else { return nil }
        return Color(hex: hex)
    }
}

// MARK: - Color Hex Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

// MARK: - GRDB Support

extension Category: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "categories" }

    enum Columns: String, ColumnExpression {
        case id, name, emoji, sortOrder = "sort_order", colorHex = "color_hex"
    }
}

// MARK: - Default Categories

extension Category {
    static let inboxId = 0  // Default category (⌘0)
    static let trashId = -1  // Trash category (not shown in input window)

    // Preset colors for color picker
    static let presetColors: [String] = [
        "FF6B6B",  // Red
        "FF8E72",  // Orange
        "FFD93D",  // Yellow
        "6BCB77",  // Green
        "4D96FF",  // Blue
        "9B72FF",  // Purple
        "FF72B3",  // Pink
        "72D4FF",  // Cyan
        "A0A0A0",  // Gray
    ]

    static let defaults: [Category] = [
        Category(id: -1, name: "Trash", emoji: "🗑️", sortOrder: -1, colorHex: nil),
        Category(id: 0, name: "Inbox", emoji: nil, sortOrder: 0, colorHex: "FF6B6B"),
        Category(id: 1, name: "Idea", emoji: nil, sortOrder: 1, colorHex: "FF8E72"),
        Category(id: 2, name: "Plan", emoji: nil, sortOrder: 2, colorHex: "FFD93D"),
        Category(id: 3, name: "Task", emoji: nil, sortOrder: 3, colorHex: "6BCB77"),
        Category(id: 4, name: "Event", emoji: nil, sortOrder: 4, colorHex: "72D4FF"),
        Category(id: 5, name: "Journal", emoji: nil, sortOrder: 5, colorHex: "4D96FF"),
        Category(id: 6, name: "Library", emoji: nil, sortOrder: 6, colorHex: "9B72FF"),
        Category(id: 7, name: "Reference", emoji: nil, sortOrder: 7, colorHex: "FF72B3"),
        Category(id: 8, name: "Archive", emoji: nil, sortOrder: 8, colorHex: "71D4FF"),
        Category(id: 9, name: "Temp", emoji: nil, sortOrder: 9, colorHex: nil),
    ]
}
