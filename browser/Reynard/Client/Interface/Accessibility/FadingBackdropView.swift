//
//  FadingBackdropView.swift
//  Reynard
//

import UIKit

/// A blur that fades out toward one edge, behind controls that float over the page.
///
/// The system's materials turn solid by themselves when Reduce Transparency is on. This blur is drawn by
/// Reynard, so it follows the setting here: with Reduce Transparency it is a solid colour, and what scrolls
/// under it is covered and no longer shows through.
final class FadingBackdropView: UIView {
    private let blurView = VariableBlurView()
    private let solidColor: UIColor

    /// - Parameters:
    ///   - direction: The edge the blur is strongest at.
    ///   - dimmingTintColor: The tint the blur fades into, or `nil` for none.
    ///   - solidColor: What stands in for the blur with Reduce Transparency.
    init(
        direction: VariableBlurView.Direction,
        dimmingTintColor: UIColor? = .systemBackground,
        solidColor: UIColor
    ) {
        self.solidColor = solidColor
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        blurView.direction = direction
        blurView.dimmingTintColor = dimmingTintColor
        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blurView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(update),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
        update()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func update() {
        let isSolid = AccessibilityAppearance.prefersSolidBackgrounds
        blurView.isHidden = isSolid
        backgroundColor = isSolid ? solidColor : .clear
    }
}
