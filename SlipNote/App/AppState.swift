import Foundation
import Combine

final class AppState: ObservableObject {
    // MARK: - Input Window State
    @Published var isInputWindowVisible = false
    @Published var inputText = ""
    @Published var isShowingCategoryBar = false
    @Published var isSearchMode = false
    @Published var searchQuery = ""
    @Published var searchResults: [Slip] = []

    // MARK: - View Mode State
    @Published var slips: [Slip] = []
    @Published var selectedSlip: Slip?
    @Published var selectedCategoryFilter: Int? = nil

    // MARK: - Categories
    @Published var categories: [Category] = Category.defaults
    @Published var cachedTrashCount: Int = 0

    // MARK: - Methods

    func loadSlips() {
        Logger.shared.debug("loadSlips called, filter: \(String(describing: selectedCategoryFilter))")
        do {
            slips = try DatabaseService.shared.fetchAllSlips(categoryId: selectedCategoryFilter)
            cachedTrashCount = try DatabaseService.shared.trashCount()
            Logger.shared.debug("Loaded \(slips.count) slips")
        } catch {
            Logger.shared.error("Failed to load slips: \(error.localizedDescription)")
        }
    }

    func createSlip(content: String, categoryId: Int) {
        Logger.shared.event("createSlip", details: ["categoryId": categoryId, "contentLength": content.count])
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.shared.warning("createSlip: content is empty, skipping")
            return
        }

        let slip = Slip(content: content, categoryId: categoryId)
        Logger.shared.info("Created slip object: id=\(slip.id), title=\(slip.title)")

        do {
            try DatabaseService.shared.insertSlip(slip)
            Logger.shared.event("slipInserted", details: ["id": slip.id])
            SpotlightService.shared.indexSlip(slip)
            loadSlips()
        } catch {
            Logger.shared.error("Failed to create slip: \(error.localizedDescription)")
        }
    }

    func updateSlip(_ slip: Slip, newContent: String) {
        Logger.shared.event("updateSlip", details: ["id": slip.id, "newContentLength": newContent.count])
        do {
            try DatabaseService.shared.updateSlip(slip, newContent: newContent)
            Logger.shared.info("Slip updated successfully")
            // Update Spotlight index
            var updatedSlip = slip
            updatedSlip.content = newContent
            updatedSlip.title = Slip.extractTitle(from: newContent)
            SpotlightService.shared.indexSlip(updatedSlip)
            loadSlips()
        } catch {
            Logger.shared.error("Failed to update slip: \(error.localizedDescription)")
        }
    }

    func deleteSlip(_ slip: Slip) {
        Logger.shared.event("deleteSlip", details: ["id": slip.id, "title": slip.title])
        do {
            try DatabaseService.shared.deleteSlip(slip)
            Logger.shared.info("Slip deleted successfully")
            SpotlightService.shared.removeSlip(slip)
            loadSlips()
            if selectedSlip?.id == slip.id {
                selectedSlip = nil
            }
        } catch {
            Logger.shared.error("Failed to delete slip: \(error.localizedDescription)")
        }
    }

    func moveSlip(_ slip: Slip, toCategoryId: Int) {
        Logger.shared.event("moveSlip", details: ["id": slip.id, "toCategoryId": toCategoryId])
        do {
            try DatabaseService.shared.moveSlip(slip, toCategoryId: toCategoryId)
            Logger.shared.info("Slip moved successfully")
            loadSlips()
        } catch {
            Logger.shared.error("Failed to move slip: \(error.localizedDescription)")
        }
    }

    func togglePin(_ slip: Slip) {
        Logger.shared.event("togglePin", details: ["id": slip.id, "currentlyPinned": slip.isPinned])
        do {
            try DatabaseService.shared.togglePin(slip)
            Logger.shared.info("Slip pin toggled successfully")
            loadSlips()
        } catch {
            Logger.shared.error("Failed to toggle pin: \(error.localizedDescription)")
        }
    }

    func emptyTrash() {
        Logger.shared.event("emptyTrash")
        do {
            try DatabaseService.shared.emptyTrash()
            Logger.shared.info("Trash emptied successfully")
            loadSlips()
        } catch {
            Logger.shared.error("Failed to empty trash: \(error.localizedDescription)")
        }
    }

    func trashCount() -> Int {
        return cachedTrashCount
    }

    func search(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        Logger.shared.debug("search: query=\(query)")
        do {
            searchResults = try DatabaseService.shared.searchSlips(query: query)
            Logger.shared.debug("search: found \(searchResults.count) results")
        } catch {
            Logger.shared.error("Failed to search: \(error.localizedDescription)")
            searchResults = []
        }
    }

    func loadCategories() {
        do {
            categories = try DatabaseService.shared.fetchCategories()
            Logger.shared.debug("Loaded \(categories.count) categories")
        } catch {
            Logger.shared.error("Failed to load categories: \(error.localizedDescription)")
        }
    }
}
