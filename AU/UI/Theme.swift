import UIKit

/// Shared colors and metrics for every UI file (Tasks 8, 9, 10, 11). Kept as
/// static constants rather than an asset catalog so the values are visible
/// in one place and trivially referenced from drawing code.
enum Theme {
    static let background   = UIColor(red: 0.082, green: 0.086, blue: 0.102, alpha: 1)
    static let panel        = UIColor(red: 0.118, green: 0.125, blue: 0.157, alpha: 1)
    static let panelBorder  = UIColor(red: 0.180, green: 0.188, blue: 0.220, alpha: 1)
    static let accent       = UIColor(red: 0.788, green: 0.635, blue: 0.153, alpha: 1)
    static let textPrimary  = UIColor(white: 0.92, alpha: 1)
    static let textDim      = UIColor(red: 0.424, green: 0.435, blue: 0.482, alpha: 1)
    static let skin         = UIColor(red: 0.847, green: 0.706, blue: 0.549, alpha: 1)
    static let robe         = UIColor(red: 0.549, green: 0.184, blue: 0.122, alpha: 1)
    static let robeShadow   = UIColor(red: 0.227, green: 0.239, blue: 0.278, alpha: 1)

    static let cornerRadius: CGFloat = 10
    static let gutter: CGFloat = 8
    /// Preferred control-strip heights: taller in portrait (two rows: tabs
    /// over full-size knobs), shorter when wide (tabs become a side column).
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

    /// SF Rounded heavy — names, tabs, scene labels.
    static func display(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: d, size: size)
    }

    static func label(_ size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }
}

extension UIColor {
    /// Returns a copy of this colour with hue shifted and saturation /
    /// brightness scaled in HSB space. Originally `MonkCharacter`-only (to
    /// derive the robe's saffron trim and fold-shadow tones from
    /// `Theme.robe` without hand-picking separate constants that could drift
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
