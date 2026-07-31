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
    static let stripHeight: CGFloat = 92

    /// Below this, a control strip cannot show a usable knob: the tab bar and
    /// the name+value captions consume the whole height and the dial computes
    /// to nothing, leaving a row of tabs controlling invisible knobs. When the
    /// strip would be shorter than this, the controls collapse to a drawer
    /// instead so the user can pull them up over the pad.
    static let minUsableStripHeight: CGFloat = 78
    static let drawerHandleHeight: CGFloat = 22
    static let minPadHeight: CGFloat = 120
    static let stageCollapseBelowHeight: CGFloat = 260

    static func label(_ size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }
}
