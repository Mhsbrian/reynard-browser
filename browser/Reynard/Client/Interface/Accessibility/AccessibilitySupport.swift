//
//  AccessibilitySupport.swift
//  Reynard
//

import UIKit

/// The smallest area a control answers touches in, whatever size it is drawn at.
enum TouchTarget {
    static let minimumSideLength: CGFloat = 44

    /// `bounds` grown, where it is smaller, to the minimum on each axis, about its centre.
    static func hitFrame(for bounds: CGRect) -> CGRect {
        let dx = min(0, (bounds.width - minimumSideLength) / 2)
        let dy = min(0, (bounds.height - minimumSideLength) / 2)
        return bounds.insetBy(dx: dx, dy: dy)
    }
}

/// A view that passes on touches which land on one of its subviews outside its own bounds.
///
/// A control drawn smaller than 44 points answers touches around itself, but only as far as the views above
/// it let touches through. A bar that is itself lower than 44 points uses this for the views its buttons
/// sit in.
class TouchTargetExtendingView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }
        return subviewAccepts(point, with: event)
    }
}

/// A stack view that does the same for its arranged subviews.
final class TouchTargetExtendingStackView: UIStackView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }
        return subviewAccepts(point, with: event)
    }
}

private extension UIView {
    func subviewAccepts(_ point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else {
            return false
        }
        return subviews.contains { subview in
            !subview.isHidden
            && subview.isUserInteractionEnabled
            && subview.alpha > 0.01
            && subview.point(inside: convert(point, to: subview), with: event)
        }
    }
}

/// A button drawn at any size that answers touches in at least 44 by 44 points.
class MinimumTouchTargetButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else {
            return false
        }
        return TouchTarget.hitFrame(for: bounds).contains(point)
    }
}

extension UIView {
    /// Shows the control's name and symbol in the Large Content Viewer when it is held at an accessibility
    /// text size. For controls in bars, which stay small to leave room for the page.
    func enableLargeContentViewer(title: String?, image: UIImage? = nil) {
        showsLargeContentViewer = true
        largeContentTitle = title
        if let image {
            largeContentImage = image
        }
        if !interactions.contains(where: { $0 is UILargeContentViewerInteraction }) {
            addInteraction(UILargeContentViewerInteraction())
        }
    }
}

/// What the accessibility settings ask of Reynard's own drawing. The system's materials and controls follow
/// these settings by themselves; this is for the surfaces Reynard draws itself.
enum AccessibilityAppearance {
    /// Reduce Transparency: surfaces that blur what is behind them become solid.
    static var prefersSolidBackgrounds: Bool {
        return UIAccessibility.isReduceTransparencyEnabled
    }

    /// The hairline Reynard draws around its floating surfaces. Barely visible by design; with Increase
    /// Contrast it is the system's opaque separator.
    static var hairlineColor: UIColor {
        return UIColor { traitCollection in
            if traitCollection.accessibilityContrast == .high {
                return UIColor.opaqueSeparator.resolvedColor(with: traitCollection)
            }
            return UIColor.separator.resolvedColor(with: traitCollection).withAlphaComponent(0.2)
        }
    }

    /// The colour of a bar when it cannot blur what is behind it.
    static var solidBarColor: UIColor {
        return .secondarySystemBackground
    }
}

extension UITraitCollection {
    /// Whether the system stands this view's bars on their side, as it does on the cover display of an
    /// iPhone Duo. No other device reports an edge.
    var hasVerticalBars: Bool {
        guard #available(iOS 27.1, *) else {
            return false
        }
        
        switch verticalBarEdge {
        case .leading, .trailing:
            return true
        case .unspecified:
            return false
        @unknown default:
            return false
        }
    }
}
