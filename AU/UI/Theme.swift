import UIKit

/// Shared colours, type and metrics for every UI file. Kept as static
/// constants rather than an asset catalog so the values are visible in one
/// place and trivially referenced from drawing code. Panels stay
/// dark-neutral so the scene carries the colour; only `accent` follows the
/// character.
enum Theme {
    static let background  = UIColor(hex: 0x1D1719)
    static let panel       = UIColor(hex: 0x2A2225)
    static let panelDeep   = UIColor(hex: 0x1B1416)
    static let cream       = UIColor(hex: 0xFFF1D6)
    static let track       = UIColor(hex: 0x4A3D41)
    static let ink         = Toon.ink
    static let textPrimary = UIColor(hex: 0xFFF4E6)
    static let textDim     = UIColor(hex: 0xC2B1A8)
    /// The monk's accent: only the starting value of each view's own
    /// `accent`. The live accent is per `PluginView` (set by its
    /// `applyPalette(_:)`), never global — an AUv3 extension hosts several
    /// plugin instances in one process, each with its own character.
    static let defaultAccent = UIColor(hex: 0xF0A020)

    /// Width of every chrome outline (knob rims, tab track, header buttons,
    /// strip panel, drawer handle).
    static let outline: CGFloat = 3
    /// Corner radius of the control strip panel.
    static let stripCornerRadius: CGFloat = 18

    static let gutter: CGFloat = 8
    /// Preferred control-strip heights. `PluginView.sceneLayout` uses
    /// `stripHeightWide` only when the container is wide AND short (inner
    /// width ≥ height and height < 500, e.g. iPhone landscape or the AUM
    /// strip), so the scene keeps its height; otherwise `stripHeight`.
    /// Independently, `ControlPages` puts its tabs in a side column whenever
    /// the strip is at least `ControlPages.sideTabsAspect` (3.5×) wider than
    /// tall, and a top row otherwise.
    static let stripHeight: CGFloat = 132
    static let stripHeightWide: CGFloat = 96

    /// Below this, a control strip cannot show a usable knob: the tab bar and
    /// the name+value captions consume the whole height and the dial computes
    /// to nothing, leaving a row of tabs controlling invisible knobs.
    /// `PluginView.controlStripHeight` treats this as a floor the strip
    /// shouldn't shrink below while there's still room to honour it — see
    /// that function's doc comment.
    static let minUsableStripHeight: CGFloat = 78

    /// Below this the scene is a sliver that reads as a glitch, not a pad:
    /// `PluginView.sceneLayout` drops it to `.zero` (and `PluginView` hides
    /// it) instead. Only the AUM strip with the drawer open gets there;
    /// closing the drawer gives the scene back.
    static let minSceneHeight: CGFloat = 32

    /// SF Rounded heavy — names, tabs, values, scene labels.
    static func display(_ size: CGFloat) -> UIFont { rounded(size, .heavy) }

    /// SF Rounded — captions.
    static func label(_ size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont { rounded(size, weight) }

    /// For a `UIButton` driven by `UIButton.Configuration`: setting
    /// `titleLabel?.font` directly only sticks until the next time the
    /// configuration recomputes the title's attributes (any state change —
    /// a tap, trait change, `updateConfiguration()` — stomps it back to the
    /// system font). This is the configuration-safe way to keep a button's
    /// title in `display` every time that happens.
    static func displayTitleTransformer(_ size: CGFloat) -> UIConfigurationTextAttributesTransformer {
        UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = display(size)
            return outgoing
        }
    }

    private static func rounded(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }
}

extension UIColor {
    /// Returns a copy of this colour with hue shifted and saturation /
    /// brightness scaled in HSB space. Originally `MonkCharacter`-only (to
    /// derive the robe's saffron trim and fold-shadow tones from
    /// a base robe colour without hand-picking separate constants that could drift
    /// out of sync with it); promoted here so every `Character` can derive
    /// its own tonal variants from a single base colour the same way.
    func adjusted(hueShift: CGFloat = 0, saturationScale: CGFloat = 1, brightnessScale: CGFloat = 1) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var shiftedHue = (h + hueShift).truncatingRemainder(dividingBy: 1)
        if shiftedHue < 0 { shiftedHue += 1 }
        return UIColor(hue: shiftedHue,
                        saturation: min(max(s * saturationScale, 0), 1),
                        brightness: min(max(b * brightnessScale, 0), 1),
                        alpha: a)
    }
}
