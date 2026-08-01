import XCTest
@testable import MonkSynth

/// Localization and about-screen attribution obligations. This app is a
/// port of someone else's MIT-licensed instrument, shipping under a
/// different developer's App Store account — these tests exist to keep the
/// legal/ethical guardrails from silently regressing:
///   - every supported language must define the same keys (no key present
///     in one table and missing from another),
///   - "Delay Lama" (AudioNerdz's product name, not ours) may appear
///     exactly once, as a factual lineage line — never in a title, subtitle,
///     or anywhere else,
///   - the MIT notice and Jonathan Taylor's name must actually be present,
///   - and — the failure mode a passing test suite can otherwise hide —
///     `NSLocalizedString` must actually resolve to real text at runtime,
///     not silently fall back to returning the raw key because a strings
///     file exists on disk in the repo but never made it into the built
///     bundle.
final class LocalizationTests: XCTestCase {

    private let languages = ["en", "ja", "ko"]

    // MARK: - Helpers

    /// `Bundle(for: LocalizationTests.self)` resolves to `MonkSynthTests.xctest`
    /// itself (this class is compiled directly into that bundle — see
    /// `ParityTests.testMatchesGoldenReference`, which locates `golden_44k.f32`
    /// the same way), not the hosting `MonkSynth.app`. `project.yml` copies
    /// `AU/Resources` into the test target for exactly this reason.
    private func testBundle() -> Bundle { Bundle(for: LocalizationTests.self) }

    private func stringsDict(for language: String) throws -> [String: String] {
        let bundle = testBundle()
        let path = try XCTUnwrap(bundle.path(forResource: language, ofType: "lproj"),
                                  "missing \(language).lproj in the built test bundle")
        let lproj = try XCTUnwrap(Bundle(path: path), "\(language).lproj is not a loadable bundle")
        let url = try XCTUnwrap(lproj.url(forResource: "Localizable", withExtension: "strings"),
                                 "\(language).lproj has no Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String],
                              "Localizable.strings in \(language).lproj failed to parse")
    }

    private func keys(for language: String) throws -> Set<String> {
        Set(try stringsDict(for: language).keys)
    }

    /// Walks up from this very file's own path to the repository root, so
    /// the next helper can scan the real `AU/` and `Host/` source trees
    /// directly instead of restating an "expected keys" list by hand that
    /// could silently drift out of sync with the code. `#filePath` is a
    /// compile-time absolute path baked into the test binary; valid for
    /// tests run from a checkout of this repo, which is how both
    /// `scripts/test.sh` and CI run them.
    private func repoRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()  // LocalizationTests.swift -> .../Tests/MonkSynthTests
        url.deleteLastPathComponent()  // .../Tests/MonkSynthTests -> .../Tests
        url.deleteLastPathComponent()  // .../Tests -> repo root
        let auDir = url.appendingPathComponent("AU", isDirectory: true)
        try XCTSkipUnless(FileManager.default.fileExists(atPath: auDir.path),
                           "could not locate the repo's AU/ directory from #filePath; skipping source-scan test")
        return url
    }

    /// Every `NSLocalizedString("key", ...)` call anywhere under `AU/` or
    /// `Host/`, found by scanning the actual source files. This is what
    /// makes `testEveryReferencedKeyIsDefinedInEveryLanguage` a real check
    /// rather than a test that merely restates the strings tables back at
    /// themselves.
    private func keysReferencedInSource() throws -> Set<String> {
        let root = try repoRoot()
        let pattern = try NSRegularExpression(pattern: #"NSLocalizedString\(\s*"([^"]+)""#)
        var found = Set<String>()

        for dir in ["AU", "Host"] {
            let dirURL = root.appendingPathComponent(dir, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift" else { continue }
                guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let ns = text as NSString
                let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
                for match in matches {
                    found.insert(ns.substring(with: match.range(at: 1)))
                }
            }
        }
        return found
    }

    // MARK: - Tests

    /// All three `.lproj` bundles must carry the same key set — no key
    /// present in one and missing from another.
    func testEveryLanguageHasTheSameKeys() throws {
        let english = try keys(for: "en")
        XCTAssertFalse(english.isEmpty, "en.lproj/Localizable.strings appears to be empty")

        for language in languages.dropFirst() {
            let other = try keys(for: language)
            let missing = english.subtracting(other)
            let extra = other.subtracting(english)
            XCTAssertEqual(other, english,
                "\(language).lproj key set differs from en.lproj — missing: \(missing.sorted()), extra: \(extra.sorted())")
        }
    }

    /// "Delay Lama" is AudioNerdz's product name, not ours. The agreed rule:
    /// the literal substring "Delay Lama" may appear exactly ONCE across the
    /// entire English strings table — not once per key, but one raw
    /// occurrence, full stop — as a single factual "inspired by" mention. It
    /// must never multiply into the app title, subtitle, keywords, or a
    /// second sentence.
    ///
    /// That single mention now lives in `about.donation`, which does double
    /// duty as both the lineage fact ("an homage to the classic Delay Lama
    /// VST plug-in by AudioNerdz (2002)") and the donation ask that mirrors
    /// the original Delay Lama's own donation request. There used to be a
    /// separate `about.heritage` key carrying the lineage sentence alone;
    /// once the donation text (which the app owner also asked to mention
    /// "Delay Lama", to explain why the ask exists) was added, keeping both
    /// would have doubled the count to two. Rather than loosen the rule to
    /// "twice, in these two specific keys", the two sentences were merged
    /// into one — the boundary stays "exactly one mention", not "exactly one
    /// mention per topic".
    ///
    /// This counts total occurrences of the substring across ALL values
    /// concatenated (not `dict.filter { ... }.count`, which would only count
    /// how many *keys* mention it — a single key whose value said "Delay
    /// Lama" twice would still pass that weaker check while violating the
    /// actual rule).
    func testDelayLamaAppearsExactlyOnceInEnglish() throws {
        let dict = try stringsDict(for: "en")
        let needle = "Delay Lama"
        var occurrences: [(key: String, count: Int)] = []
        for (key, value) in dict {
            let count = value.components(separatedBy: needle).count - 1
            if count > 0 { occurrences.append((key, count)) }
        }
        let total = occurrences.reduce(0) { $0 + $1.count }
        XCTAssertEqual(total, 1,
            "\"Delay Lama\" must appear exactly once (one raw occurrence) across the whole English strings table; found: \(occurrences.sorted { $0.key < $1.key })")
    }

    /// The test that actually catches a missing key: scans every
    /// `NSLocalizedString` call under `AU/` and `Host/` in the real source
    /// tree and asserts each key it finds is defined in every language
    /// table, in both directions covered (this test also transitively
    /// confirms `en` itself defines every referenced key).
    func testEveryReferencedKeyIsDefinedInEveryLanguage() throws {
        let referenced = try keysReferencedInSource()
        XCTAssertFalse(referenced.isEmpty,
            "source scan under AU/ and Host/ found no NSLocalizedString calls — check repoRoot()/the regex")

        for language in languages {
            let defined = try keys(for: language)
            let missing = referenced.subtracting(defined)
            XCTAssertTrue(missing.isEmpty,
                "\(language).lproj is missing keys referenced in source: \(missing.sorted())")
        }
    }

    /// MIT attribution is a legal requirement, not decoration: the notice
    /// must name both the licence and the original author.
    func testLicenseMentionsMITAndJonathanTaylor() throws {
        let dict = try stringsDict(for: "en")
        let license = try XCTUnwrap(dict["about.license"], "about.license key is missing from en.lproj")
        XCTAssertTrue(license.contains("MIT"), "about.license must mention MIT: \"\(license)\"")
        XCTAssertTrue(license.contains("Jonathan Taylor"),
            "about.license must credit Jonathan Taylor by name: \"\(license)\"")
    }

    /// The visible credit line (separate from the MIT notice above) must
    /// also still name Jonathan Taylor as the original author of MonkSynth
    /// — this is the fact "about.portCredit" below must stay clearly
    /// distinct from, not blur into.
    func testCreditMentionsJonathanTaylor() throws {
        let dict = try stringsDict(for: "en")
        let credit = try XCTUnwrap(dict["about.credit"], "about.credit key is missing from en.lproj")
        XCTAssertTrue(credit.contains("Jonathan Taylor"),
            "about.credit must credit Jonathan Taylor by name: \"\(credit)\"")
    }

    /// The iOS port credit is a separate fact from `about.credit` above
    /// (Jonathan Taylor wrote MonkSynth; Charles Vestal ported it to iOS) —
    /// must actually name Charles Vestal, not just gesture at "the port".
    func testPortCreditMentionsCharlesVestal() throws {
        let dict = try stringsDict(for: "en")
        let credit = try XCTUnwrap(dict["about.portCredit"], "about.portCredit key is missing from en.lproj")
        XCTAssertTrue(credit.contains("Charles Vestal"),
            "about.portCredit must credit Charles Vestal by name: \"\(credit)\"")
    }

    /// The donation ask must actually name the destination site — the part
    /// of `about.donation` that `AboutView.donationURL` / the
    /// `about.donationLink` button make tappable (see `AboutViewTests`).
    func testDonationMentionsSaveTibet() throws {
        let dict = try stringsDict(for: "en")
        let donation = try XCTUnwrap(dict["about.donation"], "about.donation key is missing from en.lproj")
        XCTAssertTrue(donation.contains("savetibet.org"),
            "about.donation must mention savetibet.org: \"\(donation)\"")
    }

    /// The failure mode every test above can miss: a `Localizable.strings`
    /// file that exists on disk in the repo but never actually lands in the
    /// built bundle (wrong `buildPhase` in `project.yml`, wrong target
    /// membership, a stripped/renamed `.lproj` folder, ...).
    /// `NSLocalizedString` never throws in that case — it silently returns
    /// the raw key — so this is the one check standing between "the
    /// strings compile" and "the strings actually work in the shipped app."
    func testNSLocalizedStringActuallyResolvesAtRuntimeNotJustTheRawKey() {
        let resolved = NSLocalizedString("about.title", bundle: testBundle(), comment: "")
        XCTAssertEqual(resolved, "MonkSynth",
            "NSLocalizedString(\"about.title\") returned \"\(resolved)\" — Localizable.strings is not actually present in the built test bundle")
    }
}
