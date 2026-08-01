import UIKit

/// Dismissible overlay panel carrying the app's legal/attribution
/// obligations: this is a port of someone else's open-source instrument,
/// shipping under a different developer's App Store account, and the MIT
/// licence Jonathan Taylor released it under requires the notice below to
/// ship with the app. See `AU/Resources/*.lproj/Localizable.strings` for the
/// exact wording in every supported language — every string on this screen
/// is localized, none hard-coded here.
///
/// Three separate facts live here, deliberately kept distinct rather than
/// blurred into one paragraph: Jonathan Taylor wrote the original MonkSynth
/// (`about.credit`), Charles Vestal made this iOS port (`about.portCredit` /
/// `about.portLink`), and the whole thing is an homage to AudioNerdz's
/// Delay Lama (`about.donation`).
///
/// The "Delay Lama" name is AudioNerdz's, not ours, so it gets exactly one
/// literal appearance across the entire English strings table — folded into
/// `about.donation`, which does double duty as the lineage fact AND the
/// donation ask (that ask mirrors the original Delay Lama's own donation
/// request, which is why it lives in the same sentence rather than getting
/// a second, separate mention). There used to be a standalone
/// `about.heritage` key for the lineage sentence alone; it was merged into
/// `about.donation` specifically to keep the count at one instead of two.
/// `LocalizationTests.testDelayLamaAppearsExactlyOnceInEnglish` enforces the
/// count (see that test's comment for the precise rule).
final class AboutView: UIView {

    var onClose: (() -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onBluetoothMIDI: (() -> Void)?
    /// Fired when "More Apps" is tapped. `PluginView` handles it by closing
    /// this screen and presenting `MoreAppsView` in its place.
    var onMoreApps: (() -> Void)?

    /// Hidden by default. Bluetooth MIDI pairing is a host-app concern — an
    /// AUv3 editor embedded in someone else's host (AUM, GarageBand, ...)
    /// has no business popping the system Bluetooth picker on the host's
    /// behalf. `RootViewController` (the standalone app) is the only place
    /// that flips this on.
    var showsBluetoothButton = false {
        didSet { bluetoothButton.isHidden = !showsBluetoothButton }
    }

    private let panel = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let bluetoothButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    static let sourceURL = URL(string: "https://github.com/JonET/monksynth")!
    /// The homage/donation ask (`about.donation`) mirrors the original Delay
    /// Lama's own donation request — see this file's top doc comment.
    static let donationURL = URL(string: "https://www.savetibet.org")!
    /// Where the iOS port credit (`about.portCredit`) links to.
    static let portURL = URL(string: "https://charles.pizza")!

    private static let panelPadding: CGFloat = 16
    private static let closeButtonHeight: CGFloat = 40
    private static let closeButtonGap: CGFloat = 12
    private static let maxPanelWidth: CGFloat = 360

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.6)

        // Tap-outside-to-dismiss: the recognizer lives on `self` (the
        // full-bleed backdrop), but its delegate below refuses any touch
        // that lands on `panel` or one of its children — otherwise UIKit
        // would deliver the same touch to both this recognizer AND a button
        // inside the panel (recognizers observe touches within their own
        // view's bounds regardless of which subview actually got
        // hit-tested), closing the sheet the instant someone taps
        // "Source code".
        let tap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
        tap.delegate = self
        addGestureRecognizer(tap)

        panel.backgroundColor = Theme.panel
        panel.layer.cornerRadius = Theme.cornerRadius
        panel.layer.borderWidth = 1
        panel.layer.borderColor = Theme.panelBorder.cgColor
        panel.clipsToBounds = true
        addSubview(panel)

        // Content lives in a scroll view rather than being clipped straight
        // to the panel: an AUv3 host can hand this view an extremely short
        // rect (see `PluginView`'s own doc comment on host-supplied sizes),
        // and legal text that cannot be read is a real problem, not a
        // cosmetic one.
        scrollView.alwaysBounceVertical = true
        panel.addSubview(scrollView)

        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        scrollView.addSubview(stack)

        addLabel(NSLocalizedString("about.title", comment: "About screen title"),
                 font: Theme.label(18, weight: .bold), color: Theme.textPrimary)
        addLabel(NSLocalizedString("about.tagline", comment: "About screen one-line description"),
                 font: Theme.label(12), color: Theme.textPrimary)
        addLabel(NSLocalizedString("about.credit", comment: "Credit to Jonathan Taylor"),
                 font: Theme.label(11), color: Theme.textDim)
        addLabel(NSLocalizedString("about.portCredit", comment: "Credit for the iOS port, distinct from the original author credit"),
                 font: Theme.label(11), color: Theme.textDim)
        addLinkButton(NSLocalizedString("about.portLink", comment: "Link to the iOS port author's site"),
                      action: #selector(openPortLink))
        addLabel(NSLocalizedString("about.license", comment: "Required MIT licence notice"),
                 font: Theme.label(10), color: Theme.textDim)
        addLabel(NSLocalizedString("about.donation", comment: "Delay Lama homage + donation request; the one permitted Delay Lama mention"),
                 font: Theme.label(11), color: Theme.textDim)
        addLinkButton(NSLocalizedString("about.donationLink", comment: "Tappable donation URL"),
                      action: #selector(openDonation))

        let source = UIButton(type: .system)
        source.setTitle(NSLocalizedString("about.source", comment: "Link to upstream source repository"),
                         for: .normal)
        source.titleLabel?.font = Theme.label(12)
        source.setTitleColor(Theme.accent, for: .normal)
        source.contentHorizontalAlignment = .leading
        source.addTarget(self, action: #selector(openSource), for: .touchUpInside)
        stack.addArrangedSubview(source)

        bluetoothButton.setTitle(NSLocalizedString("about.bluetooth", comment: "Open Bluetooth MIDI pairing"),
                                  for: .normal)
        bluetoothButton.titleLabel?.font = Theme.label(12)
        bluetoothButton.setTitleColor(Theme.accent, for: .normal)
        bluetoothButton.contentHorizontalAlignment = .leading
        bluetoothButton.isHidden = true
        bluetoothButton.addTarget(self, action: #selector(openBluetooth), for: .touchUpInside)
        stack.addArrangedSubview(bluetoothButton)

        let moreApps = UIButton(type: .system)
        moreApps.setTitle(NSLocalizedString("about.moreApps", comment: "Link to the More Apps screen"),
                           for: .normal)
        moreApps.titleLabel?.font = Theme.label(12)
        moreApps.setTitleColor(Theme.accent, for: .normal)
        moreApps.contentHorizontalAlignment = .leading
        moreApps.addTarget(self, action: #selector(openMoreApps), for: .touchUpInside)
        stack.addArrangedSubview(moreApps)

        var closeConfig = UIButton.Configuration.filled()
        closeConfig.title = NSLocalizedString("about.close", comment: "Dismiss the about screen")
        closeConfig.baseBackgroundColor = Theme.panelBorder
        closeConfig.baseForegroundColor = Theme.textPrimary
        closeConfig.cornerStyle = .medium
        closeButton.configuration = closeConfig
        closeButton.titleLabel?.font = Theme.label(13, weight: .semibold)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        panel.addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func addLabel(_ text: String, font: UIFont, color: UIColor) {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = color
        l.numberOfLines = 0
        stack.addArrangedSubview(l)
    }

    /// Small accent-colored tappable link, styled like the existing
    /// "Source code" / "More Apps" buttons — used for the donation and port
    /// links, which (unlike `sourceURL`) route to third-party sites.
    private func addLinkButton(_ title: String, action: Selector) {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = Theme.label(12)
        b.setTitleColor(Theme.accent, for: .normal)
        b.contentHorizontalAlignment = .leading
        b.addTarget(self, action: action, for: .touchUpInside)
        stack.addArrangedSubview(b)
    }

    @objc private func backdropTapped() { onClose?() }
    @objc private func closeTapped() { onClose?() }
    @objc private func openSource() { onOpenURL?(Self.sourceURL) }
    @objc private func openDonation() { onOpenURL?(Self.donationURL) }
    @objc private func openPortLink() { onOpenURL?(Self.portURL) }
    @objc private func openBluetooth() { onBluetoothMIDI?() }
    @objc private func openMoreApps() { onMoreApps?() }

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

extension AboutView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                            shouldReceive touch: UITouch) -> Bool {
        // Only the dimmed backdrop dismisses. A touch that lands anywhere
        // inside `panel` (the card itself, its labels, the source/bluetooth
        // links, the close button) must NOT be treated as "outside".
        guard let touchView = touch.view else { return true }
        return !touchView.isDescendant(of: panel)
    }
}
