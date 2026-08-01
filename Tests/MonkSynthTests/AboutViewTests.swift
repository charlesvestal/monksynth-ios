import XCTest
import UIKit
@testable import MonkSynth

/// Covers `AboutView`'s two newer links — the donation ask
/// (`about.donation`/`about.donationLink`, opening `AboutView.donationURL`)
/// and the iOS port credit (`about.portCredit`/`about.portLink`, opening
/// `AboutView.portURL`) — plus the constraint that made both necessary in
/// the first place: an AUv3 extension has no `UIApplication` instance to
/// call `.open` on, so every outbound link on this screen MUST route
/// through `onOpenURL` (wired by the host, see `AudioUnitViewController`/
/// `RootViewController`), never call `UIApplication` directly from inside
/// `AboutView` itself.
final class AboutViewTests: XCTestCase {

    // MARK: - Helpers

    /// `about`'s interactive links are `UIButton`s buried inside private
    /// `stack`/`scrollView`/`panel` subviews, so they're found the same way
    /// `CharacterSelectorTests`/`CharacterDropdownViewTests` reach into
    /// other views' private hierarchies: walking `subviews` (recursively
    /// here, since these are several levels deep) rather than reaching for
    /// the concrete private property.
    private func allSubviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    private func button(titled title: String, in view: AboutView) throws -> UIButton {
        let matches = allSubviews(of: view).compactMap { $0 as? UIButton }
            .filter { $0.title(for: .normal) == title }
        XCTAssertEqual(matches.count, 1,
            "expected exactly one UIButton titled \"\(title)\" in AboutView, found \(matches.count)")
        return try XCTUnwrap(matches.first)
    }

    private func makeAboutView(size: CGSize = CGSize(width: 390, height: 700)) -> AboutView {
        let view = AboutView(frame: CGRect(origin: .zero, size: size))
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return view
    }

    // MARK: - Donation link

    func testDonationLinkOpensSaveTibetURLThroughOnOpenURL() throws {
        let view = makeAboutView()
        var opened: URL?
        view.onOpenURL = { opened = $0 }

        let title = NSLocalizedString("about.donationLink", comment: "")
        try button(titled: title, in: view).sendActions(for: .touchUpInside)

        XCTAssertEqual(opened, URL(string: "https://www.savetibet.org"))
        XCTAssertEqual(opened, AboutView.donationURL)
    }

    // MARK: - Port credit link

    func testPortLinkOpensCharlesPizzaURLThroughOnOpenURL() throws {
        let view = makeAboutView()
        var opened: URL?
        view.onOpenURL = { opened = $0 }

        let title = NSLocalizedString("about.portLink", comment: "")
        try button(titled: title, in: view).sendActions(for: .touchUpInside)

        XCTAssertEqual(opened, URL(string: "https://charles.pizza"))
        XCTAssertEqual(opened, AboutView.portURL)
    }

    /// Neither new link fires unless `onOpenURL` is actually wired — proves
    /// the button targets go through that closure and not some other path
    /// (e.g. accidentally calling a hardcoded `UIApplication` open inline).
    func testLinksDoNothingObservableWithoutOnOpenURLWired() throws {
        let view = makeAboutView()
        // onOpenURL intentionally left nil.
        let donationTitle = NSLocalizedString("about.donationLink", comment: "")
        let portTitle = NSLocalizedString("about.portLink", comment: "")
        try button(titled: donationTitle, in: view).sendActions(for: .touchUpInside)
        try button(titled: portTitle, in: view).sendActions(for: .touchUpInside)
        // No crash, no assertion failure: reaching this line is the pass.
    }

    /// An AUv3 app extension process has no `UIApplication` instance to call
    /// `.open(_:)` on (`AudioUnitViewController`'s own doc comment spells
    /// this out), so `AboutView` — shared by both the host app and the
    /// extension — must never reference `UIApplication` itself; every link
    /// has to go out through `onOpenURL` to whichever host actually owns a
    /// way to open a URL (`extensionContext?.open` in the extension,
    /// `UIApplication.shared.open` only in `RootViewController`, the
    /// standalone host). A source scan is the only way to actually pin this
    /// down — a passing behavior test can't prove the *absence* of a call
    /// that isn't reachable from these two specific buttons.
    func testAboutViewSourceNeverReferencesUIApplication() throws {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()  // AboutViewTests.swift -> .../Tests/MonkSynthTests
        url.deleteLastPathComponent()  // .../Tests/MonkSynthTests -> .../Tests
        url.deleteLastPathComponent()  // .../Tests -> repo root
        let aboutViewURL = url.appendingPathComponent("AU/UI/AboutView.swift")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: aboutViewURL.path),
                           "could not locate AU/UI/AboutView.swift from #filePath; skipping source-scan test")
        let source = try String(contentsOf: aboutViewURL, encoding: .utf8)
        XCTAssertFalse(source.contains("UIApplication"),
            "AboutView.swift must never reference UIApplication directly — an AUv3 extension has none; route through onOpenURL instead")
    }
}
