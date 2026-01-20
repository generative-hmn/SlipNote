import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

final class SpotlightService {
    static let shared = SpotlightService()

    private let domainIdentifier = "com.slipnote.slips"

    private init() {}

    // MARK: - Index Single Slip

    func indexSlip(_ slip: Slip) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = slip.title
        attributeSet.contentDescription = slip.content
        attributeSet.displayName = slip.title
        attributeSet.textContent = slip.content
        attributeSet.contentCreationDate = slip.createdAt
        attributeSet.contentModificationDate = slip.updatedAt

        // Add keywords for better search
        let words = slip.content.components(separatedBy: .whitespacesAndNewlines)
        attributeSet.keywords = Array(words.prefix(20))

        let item = CSSearchableItem(
            uniqueIdentifier: slip.id,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )

        // Keep item indexed for 30 days
        item.expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)

        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error = error {
                NSLog("[SpotlightService] Failed to index slip: \(error.localizedDescription)")
            } else {
                NSLog("[SpotlightService] Indexed slip: \(slip.id)")
            }
        }
    }

    // MARK: - Remove Slip from Index

    func removeSlip(_ slip: Slip) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [slip.id]) { error in
            if let error = error {
                NSLog("[SpotlightService] Failed to remove slip from index: \(error.localizedDescription)")
            } else {
                NSLog("[SpotlightService] Removed slip from index: \(slip.id)")
            }
        }
    }

    // MARK: - Index All Slips

    func indexAllSlips() {
        do {
            let slips = try DatabaseService.shared.fetchAllSlips()
            var items: [CSSearchableItem] = []

            for slip in slips {
                let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
                attributeSet.title = slip.title
                attributeSet.contentDescription = slip.content
                attributeSet.displayName = slip.title
                attributeSet.textContent = slip.content
                attributeSet.contentCreationDate = slip.createdAt
                attributeSet.contentModificationDate = slip.updatedAt

                let words = slip.content.components(separatedBy: .whitespacesAndNewlines)
                attributeSet.keywords = Array(words.prefix(20))

                let item = CSSearchableItem(
                    uniqueIdentifier: slip.id,
                    domainIdentifier: domainIdentifier,
                    attributeSet: attributeSet
                )
                item.expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)
                items.append(item)
            }

            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error = error {
                    NSLog("[SpotlightService] Failed to index all slips: \(error.localizedDescription)")
                } else {
                    NSLog("[SpotlightService] Indexed \(items.count) slips")
                }
            }
        } catch {
            NSLog("[SpotlightService] Failed to fetch slips for indexing: \(error.localizedDescription)")
        }
    }

    // MARK: - Clear All Index

    func clearAllIndex() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
            if let error = error {
                NSLog("[SpotlightService] Failed to clear index: \(error.localizedDescription)")
            } else {
                NSLog("[SpotlightService] Cleared all index")
            }
        }
    }
}
