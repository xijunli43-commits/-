import Foundation
import Observation

@MainActor @Observable
final class LibraryStore {
    private let defaults: UserDefaults
    private(set) var favorites: Set<String>
    private(set) var comparison: [String]
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = Set(defaults.stringArray(forKey: "favoritePhoneIDs") ?? [])
        comparison = Array((defaults.stringArray(forKey: "comparisonPhoneIDs") ?? []).prefix(3))
    }
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        defaults.set(favorites.sorted(), forKey: "favoritePhoneIDs")
    }
    @discardableResult func toggleComparison(_ id: String) -> Bool {
        if comparison.contains(id) { comparison.removeAll { $0 == id } }
        else {
            guard comparison.count < 3 else { return false }
            comparison.append(id)
        }
        defaults.set(comparison, forKey: "comparisonPhoneIDs")
        return true
    }
    func clearComparison() {
        comparison = []
        defaults.removeObject(forKey: "comparisonPhoneIDs")
    }
    func clearLibrary() {
        favorites = []
        defaults.removeObject(forKey: "favoritePhoneIDs")
        clearComparison()
    }
}
