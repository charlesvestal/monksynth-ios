import UIKit
import XCTest
@testable import MonkSynth

final class BackdropTests: XCTestCase {
    private func render(_ c: Character, _ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let side = min(size.height * 0.94, size.width * 0.8)
            let stage = CGRect(x: rect.midX - side / 2, y: rect.maxY - side, width: side, height: side)
            c.drawBackdrop(in: rect, stage: stage)
        }
    }

    private func alpha(_ img: UIImage, _ x: Int, _ y: Int) -> UInt8 {
        let cg = img.cgImage!
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return px[3]
    }

    func testEveryBackdropCoversItsRectAtEverySize() {
        for c in CharacterRegistry.all {
            for size in [CGSize(width: 300, height: 300), CGSize(width: 812, height: 226), CGSize(width: 359, height: 104)] {
                let img = render(c, size)
                for (x, y) in [(1, 1), (Int(size.width) - 2, 1), (1, Int(size.height) - 2),
                               (Int(size.width) - 2, Int(size.height) - 2), (Int(size.width) / 2, Int(size.height) / 2)] {
                    XCTAssertEqual(alpha(img, x, y), 255, "\(c.id) leaves a hole at \(x),\(y) in \(size)")
                }
            }
        }
    }

    func testScenesDiffer() {
        let tops = CharacterRegistry.all.map { c -> UIColor in c.palette.skyTop }
        XCTAssertGreaterThan(Set(tops.map { $0.description }).count, 6)
    }
}
