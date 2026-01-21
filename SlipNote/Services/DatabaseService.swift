import Foundation
import GRDB

final class DatabaseService {
    static let shared = DatabaseService()

    private var dbQueue: DatabaseQueue?

    private init() {}

    // MARK: - Setup

    func setup() throws {
        let fileManager = FileManager.default
        let appDirectory = URL(fileURLWithPath: AppSettings.shared.databaseDirectoryPath)

        Logger.shared.debug("Setting up database at: \(appDirectory.path)")

        // Create directory if needed
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            Logger.shared.debug("Created directory: \(appDirectory.path)")
        }

        let dbPath = appDirectory.appendingPathComponent("slipnote.db").path
        Logger.shared.debug("Database path: \(dbPath)")

        dbQueue = try DatabaseQueue(path: dbPath)
        Logger.shared.debug("Database queue created successfully")

        try createTables()
        try seedDefaultCategories()
        Logger.shared.info("Database setup complete")
    }

    private func createTables() throws {
        Logger.shared.debug("createTables called")
        try dbQueue?.write { db in
            Logger.shared.debug("Creating tables...")
            // Categories table
            try db.create(table: "categories", ifNotExists: true) { t in
                t.column("id", .integer).primaryKey()
                t.column("name", .text).notNull()
                t.column("emoji", .text)
                t.column("sort_order", .integer)
                t.column("color_hex", .text)
            }

            // Migration: Add color_hex column if it doesn't exist
            let columns = try db.columns(in: "categories")
            if !columns.contains(where: { $0.name == "color_hex" }) {
                try db.execute(sql: "ALTER TABLE categories ADD COLUMN color_hex TEXT")
                Logger.shared.debug("[DatabaseService] Added color_hex column to categories")
            }

            // Slips table
            try db.create(table: "slips", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .text).notNull()
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("category_id", .integer).defaults(to: 1)
                    .references("categories", column: "id")
                t.column("is_pinned", .boolean).defaults(to: false)
                t.column("created_at", .datetime)
                t.column("updated_at", .datetime)
            }

            // Migration: Add is_pinned column if it doesn't exist
            let slipColumns = try db.columns(in: "slips")
            if !slipColumns.contains(where: { $0.name == "is_pinned" }) {
                try db.execute(sql: "ALTER TABLE slips ADD COLUMN is_pinned INTEGER DEFAULT 0")
                Logger.shared.debug("[DatabaseService] Added is_pinned column to slips")
            }

            // Versions table
            try db.create(table: "versions", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("slip_id", .text).notNull()
                    .references("slips", column: "id", onDelete: .cascade)
                t.column("timestamp", .text).notNull()
                t.column("content", .text).notNull()
                t.column("created_at", .datetime)
            }

            // Full-text search virtual table
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS slips_fts USING fts5(
                    title,
                    content,
                    content=slips,
                    content_rowid=rowid
                )
            """)

            // Triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS slips_ai AFTER INSERT ON slips BEGIN
                    INSERT INTO slips_fts(rowid, title, content)
                    VALUES (NEW.rowid, NEW.title, NEW.content);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS slips_ad AFTER DELETE ON slips BEGIN
                    INSERT INTO slips_fts(slips_fts, rowid, title, content)
                    VALUES ('delete', OLD.rowid, OLD.title, OLD.content);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS slips_au AFTER UPDATE ON slips BEGIN
                    INSERT INTO slips_fts(slips_fts, rowid, title, content)
                    VALUES ('delete', OLD.rowid, OLD.title, OLD.content);
                    INSERT INTO slips_fts(rowid, title, content)
                    VALUES (NEW.rowid, NEW.title, NEW.content);
                END
            """)
        }
    }

    private func seedDefaultCategories() throws {
        Logger.shared.debug("seedDefaultCategories called")
        try dbQueue?.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories") ?? 0
            Logger.shared.debug("Category count: \(count)")
            if count == 0 {
                Logger.shared.debug("Inserting default categories...")
                for category in Category.defaults {
                    Logger.shared.debug("Inserting category id=\(category.id), name=\(category.name)")
                    try category.insert(db)
                }
                Logger.shared.debug("Default categories inserted")
            } else {
                // Ensure Trash category exists (migration for existing databases)
                let trashExists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories WHERE id = ?", arguments: [Category.trashId]) ?? 0
                if trashExists == 0 {
                    Logger.shared.debug("Adding Trash category to existing database")
                    let trash = Category(id: Category.trashId, name: "Trash", emoji: "🗑️", sortOrder: -1, colorHex: nil)
                    try trash.insert(db)
                }

                // Migration: Set default colors for existing categories without colors
                let categoriesWithoutColor = try Category.filter(Category.Columns.colorHex == nil).fetchAll(db)
                for var category in categoriesWithoutColor {
                    if let defaultCat = Category.defaults.first(where: { $0.id == category.id }) {
                        category.colorHex = defaultCat.colorHex
                        try category.update(db)
                        Logger.shared.debug("Set default color for category id=\(category.id)")
                    }
                }
            }
        }
    }

    // MARK: - Slips CRUD

    func insertSlip(_ slip: Slip) throws {
        Logger.shared.debug("Inserting slip: id=\(slip.id), title=\(slip.title), categoryId=\(slip.categoryId)")
        guard let queue = dbQueue else {
            Logger.shared.error("Database not initialized - dbQueue is nil")
            throw NSError(domain: "DatabaseService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not initialized"])
        }
        try queue.write { db in
            try slip.insert(db)
            Logger.shared.debug("Slip inserted successfully")
        }
    }

    func fetchAllSlips(categoryId: Int? = nil) throws -> [Slip] {
        Logger.shared.debug("Fetching slips with categoryId filter: \(String(describing: categoryId))")
        let result: [Slip] = try dbQueue?.read { db in
            // Sort by: pinned first (desc), then by created_at (desc)
            var query = Slip.order(Slip.Columns.isPinned.desc, Slip.Columns.createdAt.desc)
            if let categoryId = categoryId {
                // Show specific category (including Trash when explicitly selected)
                query = query.filter(Slip.Columns.categoryId == categoryId)
            } else {
                // "All" view: exclude Trash items
                query = query.filter(Slip.Columns.categoryId != Category.trashId)
            }
            return try query.fetchAll(db)
        } ?? []
        Logger.shared.debug("Fetched \(result.count) slips")
        return result
    }

    func updateSlip(_ slip: Slip, newContent: String) throws {
        try dbQueue?.write { db in
            // Save current version to history
            let version = Version(slipId: slip.id, content: slip.content)
            try version.insert(db)

            // Update slip
            var updatedSlip = slip
            updatedSlip.content = newContent
            updatedSlip.title = Slip.extractTitle(from: newContent)
            updatedSlip.updatedAt = Date()
            try updatedSlip.update(db)
        }
    }

    func deleteSlip(_ slip: Slip) throws {
        _ = try dbQueue?.write { db in
            try slip.delete(db)
        }
    }

    func moveSlip(_ slip: Slip, toCategoryId: Int) throws {
        try dbQueue?.write { db in
            var updatedSlip = slip
            updatedSlip.categoryId = toCategoryId
            updatedSlip.updatedAt = Date()
            try updatedSlip.update(db)
        }
    }

    func togglePin(_ slip: Slip) throws {
        try dbQueue?.write { db in
            var updatedSlip = slip
            updatedSlip.isPinned = !slip.isPinned
            updatedSlip.updatedAt = Date()
            try updatedSlip.update(db)
        }
    }

    func emptyTrash() throws {
        Logger.shared.debug("Emptying trash")
        try dbQueue?.write { db in
            // Delete all slips in Trash
            try db.execute(sql: "DELETE FROM slips WHERE category_id = ?", arguments: [Category.trashId])
        }
        Logger.shared.debug("Trash emptied successfully")
    }

    func trashCount() throws -> Int {
        try dbQueue?.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM slips WHERE category_id = ?", arguments: [Category.trashId]) ?? 0
        } ?? 0
    }

    // MARK: - Search

    func searchSlips(query: String) throws -> [Slip] {
        try dbQueue?.read { db in
            let pattern = FTS5Pattern(matchingAllPrefixesIn: query)
            let sql = """
                SELECT slips.*
                FROM slips
                JOIN slips_fts ON slips.rowid = slips_fts.rowid
                WHERE slips_fts MATCH ?
                ORDER BY slips.created_at DESC
            """
            return try Slip.fetchAll(db, sql: sql, arguments: [pattern?.rawPattern ?? query])
        } ?? []
    }

    // MARK: - Categories

    func fetchCategories() throws -> [Category] {
        try dbQueue?.read { db in
            try Category.order(Category.Columns.sortOrder).fetchAll(db)
        } ?? []
    }

    func updateCategory(_ category: Category) throws {
        try dbQueue?.write { db in
            try category.update(db)
        }
    }

    // MARK: - Versions

    func fetchVersions(for slip: Slip) throws -> [Version] {
        try dbQueue?.read { db in
            try Version
                .filter(Version.Columns.slipId == slip.id)
                .order(Version.Columns.createdAt.desc)
                .fetchAll(db)
        } ?? []
    }

    // MARK: - Export

    func exportToMarkdown() throws -> String {
        let slips = try fetchAllSlips()
        let categories = try fetchCategories()

        var markdown = "# SlipNote Export\n\n"
        markdown += "Exported: \(Date())\n\n"

        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        for slip in slips {
            let categoryName = categoryMap[slip.categoryId]?.displayName ?? "Unknown"
            markdown += "## [\(slip.timestamp)] \(slip.title)\n\n"
            markdown += "**Category:** \(categoryName)\n\n"
            markdown += slip.content
            markdown += "\n\n---\n\n"
        }

        return markdown
    }
}
