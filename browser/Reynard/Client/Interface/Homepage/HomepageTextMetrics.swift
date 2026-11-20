//
//  HomepageTextMetrics.swift
//  Reynard
//

import UIKit

/// How the homepage's text follows the text size people choose.
///
/// The words of a card and the names in a list grow through the accessibility sizes. Two kinds of text stop
/// earlier, because the room they have does not grow with them: a heading is large to begin with, and past a
/// point a long word in it no longer fits a phone's width; a tile's name sits under an icon at most 74
/// points wide. Tiles show their name in the Large Content Viewer above that, and VoiceOver reads the whole
/// of it.
enum HomepageTextMetrics {
    /// The largest size a section's or a card's heading reaches.
    static let headingMaximumPointSize: CGFloat = 28

    static let tileTitleFontSize: CGFloat = 12
    static let tileTitleMaximumPointSize: CGFloat = 18
    /// A tile's name may be this much wider than its icon on each side, so that a name a point or two wider
    /// than the icon is not broken in the middle of a word.
    static let tileTitleOutset: CGFloat = 6

    /// The heading of a section or a card: 22-point bold at the default text size.
    static func headingFont(ofSize size: CGFloat = 22, weight: UIFont.Weight = .bold) -> UIFont {
        return UIFontMetrics(forTextStyle: .title2).scaledFont(
            for: .systemFont(ofSize: size, weight: weight),
            maximumPointSize: max(size, headingMaximumPointSize)
        )
    }

    static func tileTitleFont(weight: UIFont.Weight) -> UIFont {
        return UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: tileTitleFontSize, weight: weight),
            maximumPointSize: tileTitleMaximumPointSize
        )
    }

    /// The height of the two lines a tile's name may take, never less than it is at the default text size.
    static func tileTitleHeight(weight: UIFont.Weight, minimum: CGFloat) -> CGFloat {
        return max(minimum, (tileTitleFont(weight: weight).lineHeight * 2).rounded(.up) + 4)
    }
}

extension HomepageTextMetrics {
    /// Sets a tile's name. A name of one word that is wider than the tile is made a little smaller to fit
    /// on one line, where two lines would break it in the middle of the word.
    static func setTileTitle(_ title: String, on label: UILabel) {
        let isOneWord = !title.contains(where: { $0.isWhitespace })
        label.numberOfLines = isOneWord ? 1 : 2
        label.adjustsFontSizeToFitWidth = isOneWord
        label.minimumScaleFactor = isOneWord ? 0.7 : 1
        label.lineBreakMode = .byTruncatingTail
        label.text = title
    }
}

extension HomepageTextMetrics {
    /// Sets a heading that may hold a word longer than a phone's width at the larger text sizes. Such a word
    /// is hyphenated where the language allows, in place of being cut wherever the line ends.
    static func setHeading(_ text: String, on label: UILabel) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.hyphenationFactor = 1
        paragraphStyle.alignment = label.textAlignment
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [.paragraphStyle: paragraphStyle, .font: label.font as Any]
        )
    }
}
