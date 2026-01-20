import Foundation
import GRDB

struct Version: Identifiable, Codable, Equatable {
    var id: String
    var slipId: String
    var timestamp: String
    var content: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, timestamp, content
        case slipId = "slip_id"
        case createdAt = "created_at"
    }

    init(id: String = UUID().uuidString,
         slipId: String,
         content: String,
         createdAt: Date = Date()) {
        self.id = id
        self.slipId = slipId
        self.content = content
        self.createdAt = createdAt
        self.timestamp = Slip.generateTimestamp(from: createdAt)
    }
}

// MARK: - GRDB Support

extension Version: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "versions" }

    enum Columns: String, ColumnExpression {
        case id, slipId = "slip_id", timestamp, content, createdAt = "created_at"
    }
}
