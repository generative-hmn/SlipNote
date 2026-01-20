import Foundation
import GRDB
import UniformTypeIdentifiers
import CoreTransferable

struct Slip: Identifiable, Codable, Equatable {
    var id: String
    var timestamp: String
    var title: String
    var content: String
    var categoryId: Int
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, timestamp, title, content
        case categoryId = "category_id"
        case isPinned = "is_pinned"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: String = UUID().uuidString,
         content: String,
         categoryId: Int = Category.inboxId,
         isPinned: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.categoryId = categoryId
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.timestamp = Self.generateTimestamp(from: createdAt)
        self.title = Self.extractTitle(from: content)
    }

    // MARK: - Timestamp Generation

    /// Generates timestamp in format "YYMMDD_HHmm"
    static func generateTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd_HHmm"
        return formatter.string(from: date)
    }

    /// Extracts first line as title
    static func extractTitle(from content: String) -> String {
        let firstLine = content.components(separatedBy: .newlines).first ?? content
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        // Limit title length
        if trimmed.count > 50 {
            return String(trimmed.prefix(47)) + "..."
        }
        return trimmed
    }
}

// MARK: - GRDB FetchableRecord & PersistableRecord

extension Slip: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "slips" }

    enum Columns: String, ColumnExpression {
        case id, timestamp, title, content, categoryId = "category_id"
        case isPinned = "is_pinned"
        case createdAt = "created_at", updatedAt = "updated_at"
    }
}

// MARK: - Transferable for Drag & Drop

extension Slip: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .slipNote)
    }
}

// Wrapper for dragging multiple slips
struct SlipSelection: Codable, Transferable {
    var slips: [Slip]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .slipNoteSelection)
    }
}

extension UTType {
    static var slipNote: UTType {
        UTType(exportedAs: "com.slipnote.slip")
    }
    static var slipNoteSelection: UTType {
        UTType(exportedAs: "com.slipnote.slip-selection")
    }
}
