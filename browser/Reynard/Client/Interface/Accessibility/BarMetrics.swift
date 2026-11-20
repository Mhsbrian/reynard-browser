//
//  BarMetrics.swift
//  Reynard
//

import UIKit

/// Text and heights for the browser's own bars, which follow the text size people choose.
///
/// The address bar, the tab strip and the bars under the keyboard hold text that has to be read, so they grow
/// with Dynamic Type. They stop at twice the default size: the Human Interface Guidelines ask for text that
/// can be enlarged by at least 200 percent, and a bar that kept growing would leave no room for the page on
/// a phone. Buttons in the bars keep their size and offer the Large Content Viewer above that, as the
/// system's bars do.
enum BarMetrics {
    /// How far a bar's text grows, as a multiple of its size at the default text size.
    static let maximumTextScale: CGFloat = 2

    static let addressBarTextSize: CGFloat = 17
    static let addressBarBaseHeight: CGFloat = 44
    static let tabBarTextSize: CGFloat = 14
    static let tabBarBaseHeight: CGFloat = 36
    static let minimizedTextSize: CGFloat = 13

    /// A system font that follows Dynamic Type as body text does, up to `maximumTextScale`.
    static func font(
        ofSize size: CGFloat,
        weight: UIFont.Weight = .regular,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> UIFont {
        return UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: size, weight: weight),
            maximumPointSize: size * maximumTextScale,
            compatibleWith: traitCollection
        )
    }

    /// How much taller one line of bar text is than at the default text size, in whole points.
    static func growth(
        forTextOfSize size: CGFloat,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> CGFloat {
        let base = UIFont.systemFont(ofSize: size)
        let scaled = font(ofSize: size, compatibleWith: traitCollection)
        // Less a hundredth of a point, so that two fonts of the same size never differ by a rounding error.
        return max(0, (scaled.lineHeight - base.lineHeight - 0.01).rounded(.up))
    }

    /// How much taller the address bar, and every bar that holds it, is than at the default text size.
    static var addressBarGrowth: CGFloat {
        return growth(forTextOfSize: addressBarTextSize)
    }

    static var addressBarHeight: CGFloat {
        return addressBarBaseHeight + addressBarGrowth
    }

    static var tabBarHeight: CGFloat {
        return tabBarBaseHeight + growth(forTextOfSize: tabBarTextSize)
    }

    /// A length that grows with the bar's text: an icon beside it, the space it needs.
    static func scaled(_ value: CGFloat, compatibleWith traitCollection: UITraitCollection? = nil) -> CGFloat {
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: value, compatibleWith: traitCollection)
        return min(max(scaled, value), value * maximumTextScale)
    }
}

extension UIFont {
    /// A system font of a size the design calls for at the default text size, which then follows Dynamic
    /// Type as `textStyle` does, through the accessibility sizes.
    static func scaledSystemFont(
        ofSize size: CGFloat,
        weight: UIFont.Weight = .regular,
        relativeTo textStyle: UIFont.TextStyle = .body,
        maximumPointSize: CGFloat? = nil
    ) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        if let maximumPointSize {
            return metrics.scaledFont(for: font, maximumPointSize: maximumPointSize)
        }
        return metrics.scaledFont(for: font)
    }
}
