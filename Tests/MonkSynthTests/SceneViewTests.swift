import UIKit
import XCTest
@testable import MonkSynth

final class SceneViewTests: XCTestCase {
    func testCharacterRectIsBottomCentredSquare() {
        let r = SceneView.characterRect(in: CGRect(x: 0, y: 0, width: 812, height: 226))
        XCTAssertEqual(r.width, r.height)
        XCTAssertEqual(r.width, floor(226 * 0.94))
        XCTAssertEqual(r.maxY, 226)
        XCTAssertEqual(r.midX, 406, accuracy: 0.5)
    }

    func testNarrowSceneIsLimitedByWidth() {
        let r = SceneView.characterRect(in: CGRect(x: 0, y: 0, width: 374, height: 600))
        XCTAssertEqual(r.width, floor(374 * 0.8))
    }

    func testTinySceneHidesTheCharacter() {
        XCTAssertEqual(SceneView.characterRect(in: CGRect(x: 0, y: 0, width: 359, height: 60)), .zero)
    }

    func testPadCoversTheWholeSceneAndStageDetachesWhenHidden() {
        let stage = CharacterView(), pad = XYPadView()
        let scene = SceneView(stage: stage, pad: pad)
        scene.frame = CGRect(x: 0, y: 0, width: 374, height: 400)
        scene.layoutIfNeeded()
        XCTAssertEqual(pad.frame, scene.bounds)
        XCTAssertNotNil(stage.superview)
        scene.frame = CGRect(x: 0, y: 0, width: 359, height: 40)
        scene.layoutIfNeeded()
        XCTAssertNil(stage.superview)
    }
}
