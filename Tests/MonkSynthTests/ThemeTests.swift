import UIKit
import XCTest
@testable import MonkSynth

final class ThemeTests: XCTestCase {

    func testTokens() {
        XCTAssertEqual(Theme.background, UIColor(hex: 0x1D1719))
        XCTAssertEqual(Theme.panel, UIColor(hex: 0x2A2225))
        XCTAssertEqual(Theme.panelDeep, UIColor(hex: 0x1B1416))
        XCTAssertEqual(Theme.cream, UIColor(hex: 0xFFF1D6))
        XCTAssertEqual(Theme.textPrimary, UIColor(hex: 0xFFF4E6))
        XCTAssertEqual(Theme.textDim, UIColor(hex: 0xC2B1A8))
        XCTAssertEqual(Theme.track, UIColor(hex: 0x4A3D41))
        XCTAssertEqual(Theme.ink, Toon.ink)
        XCTAssertEqual(Theme.defaultAccent, MonkCharacter().palette.accent)
    }

    func testFontsAreRounded() {
        XCTAssertTrue(Theme.display(14).fontName.lowercased().contains("rounded"), Theme.display(14).fontName)
        XCTAssertTrue(Theme.label(10).fontName.lowercased().contains("rounded"), Theme.label(10).fontName)
    }

    private func assertChrome(of view: PluginView, uses accent: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(view.accent, accent, file: file, line: line)
        XCTAssertEqual(view.controls.accent, accent, file: file, line: line)
        XCTAssertEqual(view.controls.selectedTabButton?.backgroundColor, accent, file: file, line: line)
        XCTAssertFalse(view.controls.knobs.isEmpty, file: file, line: line)
        for k in view.controls.knobs { XCTAssertEqual(k.accent, accent, file: file, line: line) }
        XCTAssertEqual(view.pad.accent, accent, file: file, line: line)
        XCTAssertEqual(view.characterSelector.chevronColor, accent, file: file, line: line)
    }

    func testSelectingACharacterRecoloursTheChrome() {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.layoutIfNeeded()
        assertChrome(of: view, uses: view.stage.character.palette.accent)
        view.stage.select(PunkCharacter())
        assertChrome(of: view, uses: PunkCharacter().palette.accent)
        // Knobs made for a newly shown page pick the accent up too.
        view.controls.showPage(2)
        assertChrome(of: view, uses: PunkCharacter().palette.accent)
    }

    /// An AUv3 extension hosts several plugin instances in one process; each
    /// one's chrome must follow its own character, not whichever instance
    /// changed character last.
    func testTwoInstancesKeepTheirOwnAccents() {
        let a = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let b = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        a.layoutIfNeeded(); b.layoutIfNeeded()
        a.stage.select(PunkCharacter())
        b.stage.select(CatCharacter())
        XCTAssertNotEqual(PunkCharacter().palette.accent, CatCharacter().palette.accent)
        assertChrome(of: a, uses: PunkCharacter().palette.accent)
        assertChrome(of: b, uses: CatCharacter().palette.accent)
    }
}
