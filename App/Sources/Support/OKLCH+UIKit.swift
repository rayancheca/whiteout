import SwiftUI
import UIKit
import WhiteoutCore

extension OKLCH {
    /// Bridges the computed palette into something the renderer can use.
    ///
    /// Kept in the app layer on purpose: `WhiteoutCore` stays free of UIKit so the whole
    /// weather-to-physics model can be tested from the command line in milliseconds,
    /// without a simulator.
    var uiColor: UIColor {
        let components = rgba
        return UIColor(
            red: CGFloat(components.r),
            green: CGFloat(components.g),
            blue: CGFloat(components.b),
            alpha: CGFloat(components.a)
        )
    }

    /// The same bridge for SwiftUI, so overlay chrome can be tinted by the weather too.
    var color: Color { Color(uiColor: uiColor) }
}

extension UIColor {
    /// Blends toward another colour in sRGB. Only for small nudges between two colours
    /// that were already generated perceptually — anything larger belongs in OKLCH.
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(max(amount, 0), 1)
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: a1 + (a2 - a1) * t
        )
    }
}
