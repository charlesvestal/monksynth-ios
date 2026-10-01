import UIKit
import XCTest
@testable import MonkSynth

final class ThemeTests: XCTestCase {
    override func tearDown() {
        Theme.accent = MonkCharacter().palette.accent
        super.tearDown()
    }

    func testTokens() {
        XCTAssertEqual(Theme.background, UIColor(hex: 0x1D1719))
        XCTAssertEqual(Theme.panel, UIColor(hex: 0x2A2225))
        XCTAssertEqual(Theme.panelDeep, UIColor(hex: 0x1B1416))
        XCTAssertEqual(Theme.cream, UIColor(hex: 0xFFF1D6))
        XCTAssertEqual(Theme.textPrimary, UIColor(hex: 0xFFF4E6))
        XCTAssertEqual(Theme.textDim, UIColor(hex: 0xC2B1A8))
        XCTAssertEqual(Theme.track, UIColor(hex: 0x4A3D41))
        XCTAssertEqual(Theme.ink, Toon.ink)
        XCTAssertEqual(Theme.accent, MonkCharacter().palette.accent)
    }

    func testFontsAreRounded() {
        XCTAssertTrue(Theme.display(14).fontName.lowercased().contains("rounded"), Theme.display(14).fontName)
        XCTAssertTrue(Theme.label(10).fontName.lowercased().contains("rounded"), Theme.label(10).fontName)
    }

    func testSelectingACharacterRecoloursTheChrome() {
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.layoutIfNeeded()
        view.stage.select(PunkCharacter())
        XCTAssertEqual(Theme.accent, PunkCharacter().palette.accent)
        XCTAssertEqual(view.controls.selectedTabButton?.backgroundColor, PunkCharacter().palette.accent)
        XCTAssertEqual(view.pad.accent, PunkCharacter().palette.accent)
        XCTAssertEqual(view.characterSelector.chevronColor, PunkCharacter().palette.accent)
    }

    /// A fresh view starts from its own character's accent, whatever an
    /// earlier view left in the shared `Theme.accent`.
    func testANewViewAppliesItsCharactersPalette() {
        Theme.accent = .red
        let view = PluginView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertEqual(Theme.accent, view.stage.character.palette.accent)
        XCTAssertEqual(view.controls.selectedTabButton?.backgroundColor, view.stage.character.palette.accent)
    }
}
