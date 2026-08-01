import XCTest
@testable import MonkSynth

/// Covers `MoreAppsCatalog.parse`, the pure JSON-to-`Entry` logic behind
/// `MoreAppsView` — deliberately exercised without any network round trip,
/// same spirit as `KnobView.value(from:dragDelta:fine:)` in
/// `ControlPagesTests`. `MoreAppsCatalog.load` itself (the network/disk
/// half) is intentionally left untested here: it always resolves on the
/// main queue and there is no seam to fake `URLSession` without adding
/// production code whose only job would be enabling that fake.
final class MoreAppsCatalogTests: XCTestCase {

    private func json(_ string: String) -> Data { Data(string.utf8) }

    // MARK: - Happy path

    func testParsesNameBlurbAndURLFromAWellFormedResponse() throws {
        let data = json("""
        {"resultCount": 1, "results": [
            {"kind": "software", "trackName": "Qwertet",
             "trackViewUrl": "https://apps.apple.com/app/id123",
             "formattedPrice": "Free", "primaryGenreName": "Music"}
        ]}
        """)
        let entries = MoreAppsCatalog.parse(data)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "Qwertet")
        XCTAssertEqual(entries[0].url, "https://apps.apple.com/app/id123")
        XCTAssertTrue(entries[0].blurb.contains("Free"))
        XCTAssertTrue(entries[0].blurb.contains("Music"))
    }

    /// The lookup endpoint can return `wrapperType: "software"` instead of
    /// (or alongside) `kind: "software"` depending on the item; either
    /// should be accepted.
    func testAcceptsWrapperTypeSoftwareAsAnAlternativeToKind() throws {
        let data = json("""
        {"results": [
            {"wrapperType": "software", "trackName": "Qwerty Keys",
             "trackViewUrl": "https://apps.apple.com/app/id456"}
        ]}
        """)
        let entries = MoreAppsCatalog.parse(data)
        XCTAssertEqual(entries.map(\.name), ["Qwerty Keys"])
    }

    /// A missing price or genre must not crash the join, and must not leave
    /// a stray separator around the missing half.
    func testMissingPriceOrGenreOmitsItFromTheBlurbWithoutAStraySeparator() throws {
        let data = json("""
        {"results": [
            {"kind": "software", "trackName": "NoPrice",
             "trackViewUrl": "https://apps.apple.com/app/id1",
             "primaryGenreName": "Utilities"},
            {"kind": "software", "trackName": "NoGenre",
             "trackViewUrl": "https://apps.apple.com/app/id2",
             "formattedPrice": "$4.99"}
        ]}
        """)
        let entries = MoreAppsCatalog.parse(data)
        XCTAssertEqual(entries.first { $0.name == "NoPrice" }?.blurb, "Utilities")
        XCTAssertEqual(entries.first { $0.name == "NoGenre" }?.blurb, "$4.99")
    }

    // MARK: - Filtering out non-software / incomplete entries

    func testSkipsNonSoftwareResultsAndEntriesMissingRequiredFields() throws {
        let data = json("""
        {"results": [
            {"kind": "artist", "trackName": "Not An App",
             "trackViewUrl": "https://apps.apple.com/app/idX"},
            {"kind": "software", "trackViewUrl": "https://apps.apple.com/app/idY"},
            {"kind": "software", "trackName": "NoURL"},
            {"kind": "software", "trackName": "", "trackViewUrl": "https://apps.apple.com/app/idZ"},
            {"kind": "software", "trackName": "GoodOne", "trackViewUrl": "https://apps.apple.com/app/idW"}
        ]}
        """)
        let entries = MoreAppsCatalog.parse(data)
        XCTAssertEqual(entries.map(\.name), ["GoodOne"],
            "only the one fully-formed software entry should survive")
    }

    // MARK: - Never crashes on malformed input

    func testMalformedJSONYieldsAnEmptyArrayRatherThanCrashing() {
        XCTAssertEqual(MoreAppsCatalog.parse(json("not json at all")), [])
        XCTAssertEqual(MoreAppsCatalog.parse(json("{\"unexpected\": \"shape\"}")), [])
        XCTAssertEqual(MoreAppsCatalog.parse(json("{\"results\": \"not an array\"}")), [])
        XCTAssertEqual(MoreAppsCatalog.parse(json("{\"results\": [\"not\", \"objects\"]}")), [])
        XCTAssertEqual(MoreAppsCatalog.parse(Data()), [])
    }

    // MARK: - Self-filtering

    /// `MoreAppsView` filters the parsed catalog against `selfNames` before
    /// display; this is the exact filtering call it makes, proven in
    /// isolation from the view/network plumbing.
    func testSelfNamesCoversMonkSynthSoItNeverListsItself() throws {
        let data = json("""
        {"results": [
            {"kind": "software", "trackName": "MonkSynth",
             "trackViewUrl": "https://apps.apple.com/app/idSelf"},
            {"kind": "software", "trackName": "Qwertet",
             "trackViewUrl": "https://apps.apple.com/app/idOther"}
        ]}
        """)
        let entries = MoreAppsCatalog.parse(data)
            .filter { !MoreAppsView.selfNames.contains($0.name) }
        XCTAssertEqual(entries.map(\.name), ["Qwertet"])
    }
}
