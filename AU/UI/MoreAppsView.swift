import UIKit

/// Live catalog fetch/parse/cache for `MoreAppsView`, pulled from Apple's
/// public iTunes Lookup API. Kept as a plain enum (no UIKit dependency of
/// its own) so the network/parsing logic can be reasoned about — and read —
/// independently of the view that shows it.
///
/// Runs entirely on a background queue via `URLSession`; `load` always calls
/// back on the main queue, never blocking it. The raw response is cached to
/// disk under this process's own Application Support directory (no app
/// group — the host app and the AUv3 extension each keep their own copy, the
/// same way every other per-process default already works in this app), so
/// a second launch — or an offline one — opens instantly from the last known
/// catalog, and a newly-shipped MonkSynth-family app shows up here the next
/// time the network happens to be reachable, no rebuild required.
enum MoreAppsCatalog {
    struct Entry: Equatable {
        let name: String
        let blurb: String
        let url: String
    }

    private static let artistID = "1825037198"

    private static func cacheDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MonkSynth", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var cacheFile: URL { cacheDirectory().appendingPathComponent("moreapps.json") }

    /// Fetches the live catalog (network -> disk cache -> parse), falling
    /// back to whatever was last cached on disk if the network call fails
    /// for any reason — offline, timeout, a non-2xx response, or JSON that
    /// fails to parse. Always calls `done` on the main queue.
    static func load(_ done: @escaping ([Entry]) -> Void) {
        let endpoint = "https://itunes.apple.com/lookup?id=\(artistID)&entity=software&limit=200&country=us"
        func finish(_ entries: [Entry]) { DispatchQueue.main.async { done(entries) } }
        func cached() -> [Entry] { (try? Data(contentsOf: cacheFile)).map(parse) ?? [] }

        guard let url = URL(string: endpoint) else { finish(cached()); return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // Never serve a stale system URL cache — the whole point of hitting
        // this endpoint at all is to notice a catalog that changed since the
        // last launch.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data
            else { finish(cached()); return }

            let entries = parse(data)
            if entries.isEmpty {
                // A response that parsed to nothing — a hiccup, a format
                // change — isn't grounds to blow away a previously-good
                // cache with nothing.
                finish(cached())
            } else {
                try? data.write(to: cacheFile)
                finish(entries)
            }
        }.resume()
    }

    /// Not private: exercised directly from tests (malformed-JSON safety,
    /// filtering, blurb formatting) without needing a real network round
    /// trip. Never throws and never force-unwraps: every cast is optional,
    /// so malformed or unexpected JSON simply yields fewer (or zero)
    /// entries rather than crashing.
    static func parse(_ data: Data) -> [Entry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return [] }

        var out: [Entry] = []
        for item in results {
            guard (item["kind"] as? String) == "software" || (item["wrapperType"] as? String) == "software",
                  let name = item["trackName"] as? String, !name.isEmpty,
                  let url = item["trackViewUrl"] as? String
            else { continue }
            let price = item["formattedPrice"] as? String ?? ""
            let genre = item["primaryGenreName"] as? String ?? ""
            let blurb = [price, genre].filter { !$0.isEmpty }.joined(separator: "  \u{00B7}  ")
            out.append(Entry(name: name, blurb: blurb, url: url))
        }
        return out
    }
}

/// Dismissible overlay listing the developer's other App Store titles,
/// modelled on `AboutView`: scrim, centred panel, tap-outside-to-dismiss,
/// scrolls when the content doesn't fit (an AUv3 host can hand this view an
/// extremely short rect, same as `AboutView`). Populated from
/// `MoreAppsCatalog` rather than static text.
final class MoreAppsView: UIView {

    var onClose: (() -> Void)?
    /// An app extension cannot call `UIApplication.shared.open` — routed the
    /// same way `AboutView.onOpenURL` already is, through
    /// `PluginView.onOpenURL` to whichever host actually owns a way to open
    /// a URL. See that property's doc comment for the full chain.
    var onOpenURL: ((URL) -> Void)?

    static let developerURL = URL(string: "https://apps.apple.com/developer/charles-vestal/id1825037198")!

    /// Never list MonkSynth itself among "other" apps — matches every name
    /// the catalog might return it under.
    static let selfNames: Set<String> = ["MonkSynth"]

    private let panel = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let statusLabel = UILabel()
    private let developerButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    private var entries: [MoreAppsCatalog.Entry] = []

    private static let panelPadding: CGFloat = 16
    private static let closeButtonHeight: CGFloat = 40
    private static let closeButtonGap: CGFloat = 12
    private static let maxPanelWidth: CGFloat = 360

    /// The owning `PluginView`'s character accent, for links.
    private let accent: UIColor

    convenience override init(frame: CGRect) {
        self.init(frame: frame, accent: Theme.defaultAccent)
    }

    init(frame: CGRect, accent: UIColor) {
        self.accent = accent
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.6)

        // Tap-outside-to-dismiss, mirroring `AboutView`: the recognizer
        // lives on `self` (the full-bleed backdrop), and its delegate below
        // refuses any touch landing on `panel` or a descendant of it.
        let tap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
        tap.delegate = self
        addGestureRecognizer(tap)

        panel.backgroundColor = Theme.panel
        panel.layer.cornerRadius = Theme.stripCornerRadius
        panel.layer.borderWidth = Theme.outline
        panel.layer.borderColor = Theme.ink.cgColor
        panel.clipsToBounds = true
        addSubview(panel)

        scrollView.alwaysBounceVertical = true
        panel.addSubview(scrollView)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        scrollView.addSubview(stack)

        let title = UILabel()
        title.text = NSLocalizedString("moreapps.title", comment: "More Apps screen title")
        title.font = Theme.display(18)
        title.textColor = Theme.textPrimary
        title.numberOfLines = 0
        stack.addArrangedSubview(title)

        statusLabel.text = NSLocalizedString("moreapps.loading", comment: "Shown while the catalog is loading")
        statusLabel.font = Theme.label(12)
        statusLabel.textColor = Theme.textDim
        statusLabel.numberOfLines = 0
        stack.addArrangedSubview(statusLabel)

        developerButton.setTitle(
            NSLocalizedString("moreapps.viewAll", comment: "Link to the full developer App Store page"),
            for: .normal)
        developerButton.titleLabel?.font = Theme.label(12)
        developerButton.titleLabel?.numberOfLines = 0
        developerButton.setTitleColor(accent, for: .normal)
        developerButton.contentHorizontalAlignment = .leading
        developerButton.addTarget(self, action: #selector(openDeveloperPage), for: .touchUpInside)
        stack.addArrangedSubview(developerButton)

        var closeConfig = UIButton.Configuration.filled()
        closeConfig.title = NSLocalizedString("about.close", comment: "Dismiss the about screen")
        closeConfig.baseBackgroundColor = Theme.cream
        closeConfig.baseForegroundColor = Theme.ink
        closeConfig.cornerStyle = .medium
        closeConfig.background.strokeColor = Theme.ink
        closeConfig.background.strokeWidth = Theme.outline
        closeButton.configuration = closeConfig
        closeButton.titleLabel?.font = Theme.display(13)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        panel.addSubview(closeButton)

        load()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func load() {
        MoreAppsCatalog.load { [weak self] entries in
            guard let self else { return }
            self.entries = entries.filter { !Self.selfNames.contains($0.name) }
            self.populateRows()
        }
    }

    /// Test-only seam: lets `RenderUISnapshot` render the populated and
    /// empty/failed states directly, without a real network round trip.
    /// Mirrors the "not private, exercised directly from tests" seams used
    /// elsewhere in this app's UI code (e.g. `ControlPages.visibleKnobViews`).
    func debugSetEntries(_ entries: [MoreAppsCatalog.Entry]) {
        self.entries = entries
        populateRows()
    }

    /// Builds one row per entry and inserts them just above `developerButton`
    /// (repeatedly re-resolving its index, since each insert shifts it) —
    /// or, if the catalog came back empty (no network AND no cache, the
    /// honest failure case), swaps the loading message for a clear one
    /// instead of leaving a silent, empty-looking panel.
    private func populateRows() {
        if entries.isEmpty {
            statusLabel.text = NSLocalizedString(
                "moreapps.empty",
                comment: "Shown when the catalog can't be loaded and there is no cached copy")
            statusLabel.isHidden = false
        } else {
            statusLabel.isHidden = true
            for entry in entries {
                let row = MoreAppsRow(entry: entry)
                row.onTap = { [weak self] in
                    guard let self, let url = URL(string: entry.url) else { return }
                    self.onOpenURL?(url)
                }
                let insertIndex = stack.arrangedSubviews.firstIndex(of: developerButton)
                    ?? stack.arrangedSubviews.count
                stack.insertArrangedSubview(row, at: insertIndex)
            }
        }
        setNeedsLayout()
    }

    @objc private func backdropTapped() { onClose?() }
    @objc private func closeTapped() { onClose?() }
    @objc private func openDeveloperPage() { onOpenURL?(Self.developerURL) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let margin: CGFloat = 20
        let w = min(Self.maxPanelWidth, bounds.width - margin * 2)
        let maxPanelH = bounds.height - margin * 2
        guard w > 0, maxPanelH > 0 else { return }

        let padding = Self.panelPadding
        let innerW = w - padding * 2

        // How tall the stack WANTS to be at this width — may exceed what's
        // actually available; the scroll view absorbs the difference.
        let fitting = stack.systemLayoutSizeFitting(
            CGSize(width: innerW, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        let contentH = max(0, fitting.height)

        let desiredPanelH = padding * 2 + contentH + Self.closeButtonGap + Self.closeButtonHeight
        let panelH = min(desiredPanelH, maxPanelH)

        panel.frame = CGRect(x: bounds.midX - w / 2, y: bounds.midY - panelH / 2,
                              width: w, height: panelH)

        closeButton.frame = CGRect(x: padding, y: panelH - padding - Self.closeButtonHeight,
                                    width: innerW, height: Self.closeButtonHeight)

        let scrollH = max(0, panelH - padding * 2 - Self.closeButtonGap - Self.closeButtonHeight)
        scrollView.frame = CGRect(x: padding, y: padding, width: innerW, height: scrollH)
        stack.frame = CGRect(x: 0, y: 0, width: innerW, height: contentH)
        scrollView.contentSize = CGSize(width: innerW, height: contentH)
    }
}

extension MoreAppsView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                            shouldReceive touch: UITouch) -> Bool {
        guard let touchView = touch.view else { return true }
        return !touchView.isDescendant(of: panel)
    }
}

/// A single tappable row: app name, a "price · genre" blurb, and a chevron.
/// Manual frame layout (`layoutSubviews`), matching the rest of this app's
/// UI code rather than Auto Layout constraints; `intrinsicContentSize` is
/// all `MoreAppsView`'s `systemLayoutSizeFitting` call needs to size it
/// correctly inside the stack.
private final class MoreAppsRow: UIControl {
    private let nameLabel = UILabel()
    private let blurbLabel = UILabel()
    private let chevron = UILabel()

    var onTap: (() -> Void)?

    private static let height: CGFloat = 52

    init(entry: MoreAppsCatalog.Entry) {
        super.init(frame: .zero)
        backgroundColor = Theme.panel
        layer.cornerRadius = 8
        layer.borderWidth = Theme.outline
        layer.borderColor = Theme.ink.cgColor

        nameLabel.text = entry.name
        nameLabel.font = Theme.label(13, weight: .semibold)
        nameLabel.textColor = Theme.textPrimary
        nameLabel.isUserInteractionEnabled = false
        addSubview(nameLabel)

        blurbLabel.text = entry.blurb
        blurbLabel.font = Theme.label(11, weight: .regular)
        blurbLabel.textColor = Theme.textDim
        blurbLabel.isUserInteractionEnabled = false
        addSubview(blurbLabel)

        chevron.text = "\u{203A}"
        chevron.font = Theme.label(18, weight: .semibold)
        chevron.textColor = Theme.textDim
        chevron.textAlignment = .center
        chevron.isUserInteractionEnabled = false
        addSubview(chevron)

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let chevronW: CGFloat = 20
        let pad: CGFloat = 10
        chevron.frame = CGRect(x: bounds.maxX - chevronW - pad, y: 0, width: chevronW, height: bounds.height)
        let textW = max(0, bounds.width - chevronW - pad * 2 - 4)
        nameLabel.frame = CGRect(x: pad, y: 8, width: textW, height: 18)
        blurbLabel.frame = CGRect(x: pad, y: 27, width: textW, height: 16)
    }

    @objc private func tapped() { onTap?() }
}
