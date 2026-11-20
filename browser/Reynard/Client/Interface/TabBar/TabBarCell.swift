//
//  TabBarCell.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

final class TabBarCell: UICollectionViewCell {
    private enum UX {
        static let expandedTabMinimumWidth: CGFloat = 220
        static let collapsedTabMinimumWidth: CGFloat = 96
        static let tabTitleSpacing: CGFloat = 6
        static let tabFaviconSideLength: CGFloat = 16
        static let tabFaviconCornerRadius: CGFloat = 3
        static let tabCloseButtonSideLength: CGFloat = 22
        static let tabCloseButtonTrailingInset: CGFloat = 6
        static let tabCloseButtonSymbolPointSize: CGFloat = 14
        static let expandedTabContentLeadingInset: CGFloat = 10
        static let expandedTabContentTrailingInset: CGFloat = 34
        static let collapsedTabContentHorizontalInset: CGFloat = 8
        static let expandedTabTitleWidthInset: CGFloat = 58
        static let contentCornerRadius: CGFloat = 16
        static let contentInsets = UIEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)
        static let borderWidth: CGFloat = 0.5
    }
    
    enum LayoutMode {
        case expanded
        case faviconOnly
    }
    
    static let reuseIdentifier = "TabBarCell"
    private static let minimumVisibleTabTitle = "WWWWW"
    
    static var expandedMinimumWidth: CGFloat {
        return UX.expandedTabMinimumWidth
    }
    
    static var collapsedMinimumWidth: CGFloat {
        return UX.collapsedTabMinimumWidth
    }
    
    static var contentCornerRadius: CGFloat {
        return UX.contentCornerRadius
    }
    
    static var contentInsets: UIEdgeInsets {
        return UX.contentInsets
    }
    
    private static let fallbackFavicon = UIImage(named: "reynard.globe")
    private static let selectedTabBackgroundColor = UIColor { traitCollection in
        let backgroundColor: UIColor = traitCollection.userInterfaceStyle == .dark
        ? .tertiarySystemBackground.withAlphaComponent(0.8)
        : .systemBackground.withAlphaComponent(0.8)
        return backgroundColor.resolvedColor(with: traitCollection)
    }
    var closeHandler: (() -> Void)?
    private(set) var tabID: UUID?
    
    private let tabContentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let faviconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = UX.tabFaviconCornerRadius
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = BarMetrics.font(ofSize: BarMetrics.tabBarTextSize, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.textAlignment = .center
        return label
    }()
    
    // Drawn at 22 points. The cell gives it a touch target 44 points wide and as high as the strip: see
    // `closeButtonHitFrame`.
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        if #available(iOS 13.4, *) {
            button.isPointerInteractionEnabled = true
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "reynard.xmark.circle.fill"), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: UX.tabCloseButtonSymbolPointSize, weight: .regular),
            forImageIn: .normal
        )
        button.tintColor = .secondaryLabel
        button.isHidden = true
        button.accessibilityLabel = NSLocalizedString("Close Tab", comment: "")
        button.accessibilityIdentifier = AccessibilityIdentifier.TabBar.closeTab
        return button
    }()
    
    private let titleStack: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = UX.tabTitleSpacing
        return stackView
    }()
    
    private var expandedTrailingConstraint: NSLayoutConstraint!
    private var collapsedTrailingConstraint: NSLayoutConstraint!
    private var expandedLeadingConstraint: NSLayoutConstraint!
    private var collapsedLeadingConstraint: NSLayoutConstraint!
    private var expandedTitleWidthConstraint: NSLayoutConstraint!
    private var faviconSizeConstraints: [NSLayoutConstraint] = []
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureContentPriorities()
        configureActions()
        configureConstraints()
        updateBorderColor()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        tabID = nil
        closeHandler = nil
        tabContentView.layer.borderWidth = 0
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            faviconSizeConstraints.forEach { $0.constant = BarMetrics.scaled(UX.tabFaviconSideLength) }
        }
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle
                || previousTraitCollection?.accessibilityContrast != traitCollection.accessibilityContrast else {
            return
        }
        
        updateBorderColor()
    }
    
    // MARK: - Accessibility
    
    // A tab is one element: its title, whether it is the one shown, and closing it as an action. The close
    // button is only there on the selected tab, and the action is there on all of them.
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            return [UIAccessibilityCustomAction(
                name: NSLocalizedString("Close Tab", comment: ""),
                target: self,
                selector: #selector(handleAccessibilityClose)
            )]
        }
        set {}
    }
    
    @objc private func handleAccessibilityClose() -> Bool {
        guard let closeHandler else {
            return false
        }
        closeHandler()
        return true
    }
    
    // MARK: - Configuration
    
    func configure(
        tab: Tab,
        isSelected: Bool,
        layoutMode: LayoutMode,
        cellWidth: CGFloat
    ) {
        tabID = tab.id
        let displayTitle = tab.title.isEmpty ? NSLocalizedString("Homepage", comment: "") : tab.title
        titleLabel.text = displayTitle
        faviconView.image = tab.favicon ?? Self.fallbackFavicon
        tabContentView.backgroundColor = isSelected ? Self.selectedTabBackgroundColor : .clear
        tabContentView.layer.borderWidth = isSelected ? UX.borderWidth : 0
        titleLabel.textColor = isSelected ? .label : .secondaryLabel
        faviconView.tintColor = isSelected ? .label : .secondaryLabel
        let minimumVisibleTitle = Self.minimumVisibleTabTitle as NSString
        let minimumTitleWidth = minimumVisibleTitle.size(withAttributes: [.font: titleLabel.font as Any]).width
        let availableTitleWidth = cellWidth - UX.expandedTabTitleWidthInset
        let isTooNarrowForTitle = availableTitleWidth < minimumTitleWidth
        let isCollapsed = layoutMode == .faviconOnly || isTooNarrowForTitle
        
        titleLabel.isHidden = isCollapsed
        titleStack.spacing = isCollapsed ? 0 : UX.tabTitleSpacing
        expandedLeadingConstraint.isActive = !isCollapsed
        collapsedLeadingConstraint.isActive = isCollapsed
        expandedTrailingConstraint.isActive = !isCollapsed
        collapsedTrailingConstraint.isActive = isCollapsed
        expandedTitleWidthConstraint.isActive = !isCollapsed
        closeButton.isHidden = isCollapsed || !isSelected
        
        isAccessibilityElement = true
        accessibilityLabel = displayTitle
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        accessibilityIdentifier = AccessibilityIdentifier.TabBar.tab
    }
    
    func containsCloseButton(at point: CGPoint) -> Bool {
        guard !closeButton.isHidden else {
            return false
        }
        
        return closeButtonHitFrame.contains(point)
    }
    
    /// Where a touch closes the tab, in the cell's coordinates: the cell's end, from 44 points before the
    /// button's far edge, top to bottom.
    private var closeButtonHitFrame: CGRect {
        let buttonFrame = closeButton.convert(closeButton.bounds, to: self)
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let near = isRightToLeft
        ? min(buttonFrame.minX + TouchTarget.minimumSideLength, bounds.maxX)
        : max(buttonFrame.maxX - TouchTarget.minimumSideLength, bounds.minX)
        return isRightToLeft
        ? CGRect(x: bounds.minX, y: bounds.minY, width: near - bounds.minX, height: bounds.height)
        : CGRect(x: near, y: bounds.minY, width: bounds.maxX - near, height: bounds.height)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if containsCloseButton(at: point), self.point(inside: point, with: event) {
            return closeButton
        }
        return super.hitTest(point, with: event)
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        contentView.backgroundColor = .clear
        tabContentView.layer.cornerRadius = UX.contentCornerRadius
        tabContentView.layer.cornerCurve = .continuous
        tabContentView.layer.masksToBounds = true
        tabContentView.layer.borderWidth = 0
    }
    
    private func configureHierarchy() {
        contentView.addSubview(tabContentView)
        tabContentView.addSubview(titleStack)
        titleStack.addArrangedSubview(faviconView)
        titleStack.addArrangedSubview(titleLabel)
        tabContentView.addSubview(closeButton)
    }
    
    private func configureContentPriorities() {
        faviconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        faviconView.setContentCompressionResistancePriority(.required, for: .vertical)
        faviconView.setContentHuggingPriority(.required, for: .horizontal)
    }
    
    private func configureActions() {
        closeButton.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)
    }
    
    private func configureConstraints() {
        expandedTrailingConstraint = titleStack.trailingAnchor.constraint(lessThanOrEqualTo: tabContentView.trailingAnchor, constant: -UX.expandedTabContentTrailingInset)
        collapsedTrailingConstraint = titleStack.trailingAnchor.constraint(lessThanOrEqualTo: tabContentView.trailingAnchor, constant: -UX.collapsedTabContentHorizontalInset)
        expandedLeadingConstraint = titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: tabContentView.leadingAnchor, constant: UX.expandedTabContentLeadingInset)
        collapsedLeadingConstraint = titleStack.leadingAnchor.constraint(greaterThanOrEqualTo: tabContentView.leadingAnchor, constant: UX.collapsedTabContentHorizontalInset)
        expandedTitleWidthConstraint = titleLabel.widthAnchor.constraint(lessThanOrEqualTo: tabContentView.widthAnchor, constant: -UX.expandedTabTitleWidthInset)
        
        faviconSizeConstraints = [
            faviconView.widthAnchor.constraint(equalToConstant: BarMetrics.scaled(UX.tabFaviconSideLength)),
            faviconView.heightAnchor.constraint(equalToConstant: BarMetrics.scaled(UX.tabFaviconSideLength)),
        ]
        NSLayoutConstraint.activate(faviconSizeConstraints)
        
        NSLayoutConstraint.activate([
            tabContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: UX.contentInsets.left),
            tabContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -UX.contentInsets.right),
            tabContentView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.contentInsets.top),
            tabContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.contentInsets.bottom),
            
            titleStack.centerXAnchor.constraint(equalTo: tabContentView.centerXAnchor),
            titleStack.centerYAnchor.constraint(equalTo: tabContentView.centerYAnchor),
            expandedLeadingConstraint,
            expandedTrailingConstraint,
            
            expandedTitleWidthConstraint,
            
            closeButton.trailingAnchor.constraint(equalTo: tabContentView.trailingAnchor, constant: -UX.tabCloseButtonTrailingInset),
            closeButton.centerYAnchor.constraint(equalTo: tabContentView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: UX.tabCloseButtonSideLength),
            closeButton.heightAnchor.constraint(equalToConstant: UX.tabCloseButtonSideLength),
        ])
    }
    
    private func updateBorderColor() {
        tabContentView.layer.borderColor = AccessibilityAppearance.hairlineColor.resolvedColor(with: traitCollection).cgColor
    }
    
    // MARK: - Actions
    
    @objc private func handleCloseTap() {
        closeHandler?()
    }
}
