import XCTest
@testable import PhoneRank

final class CatalogTests: XCTestCase {
    func testMixedIDAndNullDecoding() throws {
        let json = #"{"id":12,"name":"Test","antutu":{"total":null},"battery":{"capacity":5000}}"#
        let record = try JSONDecoder().decode(DeviceRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.id, "12")
        XCTAssertNil(record.number("antutu.total"))
        XCTAssertEqual(record.number("battery.capacity"), 5000)
    }

    func testMissingScoresSortLastAndWeightAscending() throws {
        let json = #"[{"id":1,"name":"Unknown","body":{"weight":null}},{"id":2,"name":"Heavy","body":{"weight":230}},{"id":3,"name":"Light","body":{"weight":170}}]"#
        let devices = try JSONDecoder().decode([DeviceRecord].self, from: Data(json.utf8))
        XCTAssertEqual(CatalogQuery.sorted(devices, by: .weight).map(\.id), ["3", "2", "1"])
    }

    func testSearchUsesChipAlias() throws {
        let json = #"[{"id":"x","name":"测试手机","platform":"android","soc":{"alias":"Snapdragon Elite"}}]"#
        let devices = try JSONDecoder().decode([DeviceRecord].self, from: Data(json.utf8))
        XCTAssertEqual(CatalogQuery.filter(devices, query: " SNAPDRAGON ", platform: "android").count, 1)
        XCTAssertTrue(CatalogQuery.filter(devices, query: "", platform: "ios").isEmpty)
    }

    @MainActor
    func testComparisonLimitAndPersistence() throws {
        let suite = "PhoneRankTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LibraryStore(defaults: defaults)
        XCTAssertTrue(store.toggleComparison("1"))
        XCTAssertTrue(store.toggleComparison("2"))
        XCTAssertTrue(store.toggleComparison("3"))
        XCTAssertFalse(store.toggleComparison("4"))
        store.toggleFavorite("1")
        let restored = LibraryStore(defaults: defaults)
        XCTAssertEqual(restored.comparison, ["1", "2", "3"])
        XCTAssertTrue(restored.favorites.contains("1"))
        XCTAssertTrue(store.toggleComparison("2"))
        XCTAssertEqual(store.comparison, ["1", "3"])
    }

    func testBundledCatalog() throws {
        let catalog = try Catalog.load()
        XCTAssertEqual(catalog.phones.count, 182)
        XCTAssertEqual(catalog.chips.count, 80)
        XCTAssertEqual(Set(catalog.phones.map(\.id)).count, 182)
    }
}
