//
//  PageZoomActionBar.swift
//  Reynard
//
//  Created by Minh Ton on 28/6/26.
//

import UIKit

final class PageZoomActionBar: UIView {
    private enum UX {
        // The percentage follows the text size. The pill grows with it: higher, and wider in the middle.
        static var controlsHeight: CGFloat {
            let growth = BarMetrics.growth(forTextOfSize: percentFontSize)
            if #available(iOS 26.0, *) { return 48 + growth }
            return 38 + growth
        }
        static var controlsWidth: CGFloat {
            let middleGrowth = BarMetrics.scaled(percentWidth) - percentWidth
            if #available(iOS 26.0, *) { return 222 + middleGrowth }
            return 184 + middleGrowth
        }
        static var controlButtonWidth: CGFloat {
            if #available(iOS 26.0, *) { return (222 - separatorWidth * 2) / 3 }
            return 55
        }
        /// The room "100%" takes at the default text size.
        static let percentWidth: CGFloat = 44
        static let separatorWidth: CGFloat = 1
        static var controlsCornerRadius: CGFloat { return controlsHeight / 2 }
        static let percentFontSize: CGFloat = 16
        static let controlSymbolPointSize: CGFloat = 14
        static let animationDuration: TimeInterval = 0.12
        static let bounceScale: CGFloat = 1.3
        static let bounceReturnDuration: TimeInterval = 0.75
        static let bounceDamping: CGFloat = 0.5
        static let backgroundAlpha: CGFloat = 0.34
        static let disabledAlpha: CGFloat = 0.32
        static let shadowOpacity: Float = 0.14
        static let shadowRadius: CGFloat = 8
        static let shadowOffset = CGSize(width: 0, height: 3)
        static let borderWidth: CGFloat = 0.5
    }
    
    static let zoomLevels = PageZoomLevels.all
    
    var onZoomOut: (() -> Void)?
    var onZoomIn: (() -> Void)?
    var onReset: (() -> Void)?
    
    private(set) var zoomLevel = Prefs.BrowsingSettings.defaultPageZoomLevel
    
    private let backgroundView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.backgroundColor = UIColor.systemBackground.withAlphaComponent(UX.backgroundAlpha)
        return view
    }()
    
    private let controlsShadowView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.controlsCornerRadius
        view.layer.shadowOpacity = UX.shadowOpacity
        view.layer.shadowRadius = UX.shadowRadius
        view.layer.shadowOffset = UX.shadowOffset
        view.layer.shadowColor = UIColor.black.cgColor
        return view
    }()
    
    private let controlsBackground: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.backgroundColor = UIColor { traitCollection in
            let backgroundColor: UIColor = traitCollection.userInterfaceStyle == .dark
            ? .tertiarySystemBackground.withAlphaComponent(0.8)
            : .systemBackground.withAlphaComponent(0.8)
            return backgroundColor.resolvedColor(with: traitCollection)
        }
        view.layer.cornerCurve = .continuous
        view.layer.cornerRadius = UX.controlsCornerRadius
        view.layer.borderWidth = UX.borderWidth
        view.layer.borderColor = AccessibilityAppearance.hairlineColor.cgColor
        view.clipsToBounds = true
        return view
    }()
    
    private lazy var zoomOutButton = makeControlButton(
        named: "reynard.minus",
        title: NSLocalizedString("Zoom Out", comment: ""),
        identifier: AccessibilityIdentifier.PageZoom.zoomOut,
        action: #selector(zoomOutTapped)
    )
    private lazy var zoomInButton = makeControlButton(
        named: "reynard.plus",
        title: NSLocalizedString("Zoom In", comment: ""),
        identifier: AccessibilityIdentifier.PageZoom.zoomIn,
        action: #selector(zoomInTapped)
    )
    private var controlsSizeConstraints: [NSLayoutConstraint] = []
    
    private lazy var resetButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = BarMetrics.font(ofSize: UX.percentFontSize)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        // Read as what it is and what it does, with the percentage as its value: see `setZoomLevel(_:)`.
        button.accessibilityLabel = NSLocalizedString("Page Zoom", comment: "")
        button.accessibilityHint = NSLocalizedString("Reset", comment: "")
        button.accessibilityIdentifier = AccessibilityIdentifier.PageZoom.reset
        button.setTitleColor(.secondaryLabel, for: .normal)
        button.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        return button
    }()
    
    private let leadingSeparator = PageZoomActionBar.makeSeparator()
    private let trailingSeparator = PageZoomActionBar.makeSeparator()
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        setZoomLevel(zoomLevel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else {
            return
        }
        
        controlsSizeConstraints[0].constant = UX.controlsWidth
        controlsSizeConstraints[1].constant = UX.controlsHeight
        if #unavailable(iOS 26.0) {
            controlsShadowView.layer.cornerRadius = UX.controlsCornerRadius
            controlsBackground.layer.cornerRadius = UX.controlsCornerRadius
        }
        setNeedsLayout()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        controlsShadowView.layer.shadowPath = UIBezierPath(
            roundedRect: controlsShadowView.bounds,
            cornerRadius: UX.controlsCornerRadius
        ).cgPath
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if #available(iOS 26.0, *), !controlsShadowView.frame.contains(point) { return nil }
        return super.hitTest(point, with: event)
    }
    
    // MARK: - Presentation
    
    @available(iOS 26.0, *)
    func setModernContentHidden(_ hidden: Bool) {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        controlsBackground.effect = hidden ? nil : effect
        controlsBackground.contentView.alpha = hidden ? 0 : 1
    }
    
    // MARK: - Updates
    
    func setZoomLevel(_ level: Int) {
        zoomLevel = PageZoomActionBar.zoomLevels.contains(level) ? level : Prefs.BrowsingSettings.defaultPageZoomLevel
        resetButton.setTitle(PageZoomLevels.displayText(for: zoomLevel), for: .normal)
        resetButton.accessibilityValue = PageZoomLevels.displayText(for: zoomLevel)
        zoomOutButton.isEnabled = zoomLevel > PageZoomActionBar.zoomLevels.first!
        zoomInButton.isEnabled = zoomLevel < PageZoomActionBar.zoomLevels.last!
        zoomOutButton.alpha = zoomOutButton.isEnabled ? 1 : UX.disabledAlpha
        zoomInButton.alpha = zoomInButton.isEnabled ? 1 : UX.disabledAlpha
    }
    
    func nextZoomLevel() -> Int {
        guard let index = PageZoomActionBar.zoomLevels.firstIndex(of: zoomLevel) else {
            return Prefs.BrowsingSettings.defaultPageZoomLevel
        }
        return PageZoomActionBar.zoomLevels[min(index + 1, PageZoomActionBar.zoomLevels.count - 1)]
    }
    
    func previousZoomLevel() -> Int {
        guard let index = PageZoomActionBar.zoomLevels.firstIndex(of: zoomLevel) else {
            return Prefs.BrowsingSettings.defaultPageZoomLevel
        }
        return PageZoomActionBar.zoomLevels[max(index - 1, 0)]
    }
    
    // MARK: - Actions
    
    // Each step of zoom is a value changing, which is what the selection haptic is for.
    @objc private func zoomOutTapped() {
        Haptics.selection()
        animatePillTap()
        onZoomOut?()
    }
    
    @objc private func zoomInTapped() {
        Haptics.selection()
        animatePillTap()
        onZoomIn?()
    }
    
    @objc private func resetTapped() {
        Haptics.selection()
        animatePillTap()
        onReset?()
    }
    
    private func animatePillTap() {
        guard #available(iOS 26.0, *), !UIAccessibility.isReduceMotionEnabled else { return }
        UIView.animate(
            withDuration: UX.animationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.controlsShadowView.transform = CGAffineTransform(scaleX: UX.bounceScale, y: UX.bounceScale)
        } completion: { finished in
            guard finished else { return }
            UIView.animate(
                withDuration: UX.bounceReturnDuration,
                delay: 0,
                usingSpringWithDamping: UX.bounceDamping,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.controlsShadowView.transform = .identity
            }
        }
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        accessibilityIdentifier = AccessibilityIdentifier.PageZoom.bar
        if #available(iOS 26.0, *) {
            backgroundView.isHidden = true
            setModernContentHidden(false)
            controlsBackground.contentView.backgroundColor = .clear
            controlsBackground.layer.borderWidth = 0
            controlsBackground.layer.cornerRadius = 0
            controlsBackground.cornerConfiguration = .capsule()
            controlsBackground.clipsToBounds = false
            controlsShadowView.layer.shadowOpacity = 0
        }
    }
    
    private func configureHierarchy() {
        addSubview(backgroundView)
        addSubview(controlsShadowView)
        controlsShadowView.addSubview(controlsBackground)
        [zoomOutButton, leadingSeparator, resetButton, trailingSeparator, zoomInButton].forEach {
            controlsBackground.contentView.addSubview($0)
        }
    }
    
    private func configureConstraints() {
        controlsSizeConstraints = [
            controlsShadowView.widthAnchor.constraint(equalToConstant: UX.controlsWidth),
            controlsShadowView.heightAnchor.constraint(equalToConstant: UX.controlsHeight),
        ]
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            controlsShadowView.centerXAnchor.constraint(equalTo: centerXAnchor),
            controlsShadowView.centerYAnchor.constraint(equalTo: centerYAnchor),
            controlsSizeConstraints[0],
            controlsSizeConstraints[1],
            
            controlsBackground.topAnchor.constraint(equalTo: controlsShadowView.topAnchor),
            controlsBackground.leadingAnchor.constraint(equalTo: controlsShadowView.leadingAnchor),
            controlsBackground.trailingAnchor.constraint(equalTo: controlsShadowView.trailingAnchor),
            controlsBackground.bottomAnchor.constraint(equalTo: controlsShadowView.bottomAnchor),
            
            zoomOutButton.leadingAnchor.constraint(equalTo: controlsBackground.contentView.leadingAnchor),
            zoomOutButton.topAnchor.constraint(equalTo: controlsBackground.contentView.topAnchor),
            zoomOutButton.bottomAnchor.constraint(equalTo: controlsBackground.contentView.bottomAnchor),
            zoomOutButton.widthAnchor.constraint(equalToConstant: UX.controlButtonWidth),
            
            leadingSeparator.leadingAnchor.constraint(equalTo: zoomOutButton.trailingAnchor),
            leadingSeparator.centerYAnchor.constraint(equalTo: controlsBackground.contentView.centerYAnchor),
            leadingSeparator.widthAnchor.constraint(equalToConstant: UX.separatorWidth),
            leadingSeparator.heightAnchor.constraint(equalTo: controlsBackground.contentView.heightAnchor, multiplier: 0.42),
            
            resetButton.leadingAnchor.constraint(equalTo: leadingSeparator.trailingAnchor),
            resetButton.topAnchor.constraint(equalTo: controlsBackground.contentView.topAnchor),
            resetButton.bottomAnchor.constraint(equalTo: controlsBackground.contentView.bottomAnchor),
            
            trailingSeparator.leadingAnchor.constraint(equalTo: resetButton.trailingAnchor),
            trailingSeparator.centerYAnchor.constraint(equalTo: controlsBackground.contentView.centerYAnchor),
            trailingSeparator.widthAnchor.constraint(equalToConstant: UX.separatorWidth),
            trailingSeparator.heightAnchor.constraint(equalTo: controlsBackground.contentView.heightAnchor, multiplier: 0.42),
            
            zoomInButton.leadingAnchor.constraint(equalTo: trailingSeparator.trailingAnchor),
            zoomInButton.trailingAnchor.constraint(equalTo: controlsBackground.contentView.trailingAnchor),
            zoomInButton.topAnchor.constraint(equalTo: controlsBackground.contentView.topAnchor),
            zoomInButton.bottomAnchor.constraint(equalTo: controlsBackground.contentView.bottomAnchor),
            zoomInButton.widthAnchor.constraint(equalToConstant: UX.controlButtonWidth),
            
        ])
    }
    
    private func makeControlButton(named: String, title: String, identifier: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityLabel = title
        button.accessibilityIdentifier = identifier
        button.enableLargeContentViewer(title: title, image: UIImage(named: named))
        button.translatesAutoresizingMaskIntoConstraints = false
        let configuration = UIImage.SymbolConfiguration(pointSize: UX.controlSymbolPointSize, weight: .regular)
        button.setImage(UIImage(named: named, in: .main, with: configuration), for: .normal)
        button.tintColor = .label
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    
    private static func makeSeparator() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }
}
