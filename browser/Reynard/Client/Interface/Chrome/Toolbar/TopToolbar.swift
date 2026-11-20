//
//  TopToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TopToolbar: UIView {
    private enum UX {
        static let topToolbarContentHeight: CGFloat = 60
        static let topToolbarButtonStackHeight: CGFloat = 30
        static let topToolbarStandardButtonStackWidth: CGFloat = 126
        static let topToolbarHorizontalInset: CGFloat = 12
        static let topToolbarButtonSpacing: CGFloat = 10
        static let topToolbarAddressBarSpacing: CGFloat = 12
        static let topToolbarAddressBarVerticalSpacing: CGFloat = 8
        static let topToolbarAddressBarWidthLimit: CGFloat = 650
        static let backgroundViewHorizontalExtension: CGFloat = 16
        static let borderWidth: CGFloat = 0.5
    }
    
    enum LayoutState {
        case hidden
        case standard
        case compact
    }
    
    /// Where the toolbar's content goes when something lies across its row: the fold of an iPhone Duo that is
    /// partly open, or its inner camera while that is in use. Distances are from the toolbar's leading edge.
    private struct ContentPlacement: Equatable {
        struct Arrangement: Equatable {
            /// How far the leading buttons start after the content guide's leading edge.
            let leadingButtonsInset: CGFloat
            /// How far the trailing buttons end before the content guide's trailing edge.
            let trailingButtonsInset: CGFloat
            let addressBar: ClosedRange<CGFloat>
        }
        
        /// What is in the way. A change in this alone, with the toolbar's width as it was, is animated.
        let obstacles: [ClosedRange<CGFloat>]
        let width: CGFloat
        /// nil where nothing is in the way, and the toolbar lays out as it does on every other device.
        let arrangement: Arrangement?
    }
    
    /// A fold or a camera has moved the toolbar's content, or let it back. Layout has yet to follow.
    var onContentArrangementChange: (() -> Void)?
    var onSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onLibrary: (() -> Void)?
    var onDownloads: (() -> Void)?
    var onShare: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onTabOverview: (() -> Void)?
    
    private let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    private let backgroundView: UIVisualEffectView = {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            effect = UIGlassEffect.nonAdaptive(style: .regular)
        } else {
            effect = UIBlurEffect(style: .systemChromeMaterial)
        }
        let view = UIVisualEffectView(effect: effect)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let backgroundBottomBorderView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.separator.withAlphaComponent(0.2)
        if #available(iOS 26.0, *) {
            view.isHidden = true
        }
        return view
    }()
    
    private lazy var sidebarButton = ToolbarButton(
        buttonType: .sidebar,
        target: self,
        action: #selector(sidebarTapped)
    )
    private lazy var backButton = ToolbarButton(
        buttonType: .back,
        target: self,
        action: #selector(backTapped)
    )
    private lazy var forwardButton = ToolbarButton(
        buttonType: .forward,
        target: self,
        action: #selector(forwardTapped)
    )
    private lazy var libraryButton = ToolbarButton(
        buttonType: .library,
        target: self,
        action: #selector(libraryTapped)
    )
    private lazy var downloadButton = ToolbarButton(
        buttonType: .download,
        target: self,
        action: #selector(downloadsTapped)
    )
    private lazy var shareButton = ToolbarButton(
        buttonType: .share,
        target: self,
        action: #selector(shareTapped)
    )
    private lazy var newTabButton = ToolbarButton(
        buttonType: .newTab,
        target: self,
        action: #selector(newTabTapped)
    )
    private lazy var tabOverviewButton = ToolbarButton(
        buttonType: .tabOverview,
        target: self,
        action: #selector(tabOverviewTapped)
    )
    private let buttonMenus = ToolbarButtonMenus()
    
    private lazy var leadingButtons: UIStackView = {
        downloadButton.isHidden = true
        let stack = UIStackView(arrangedSubviews: [sidebarButton, downloadButton, backButton, forwardButton, libraryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = UX.topToolbarButtonSpacing
        stack.distribution = .fillEqually
        return stack
    }()
    
    private lazy var trailingButtons: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [shareButton, newTabButton, tabOverviewButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = UX.topToolbarButtonSpacing
        stack.distribution = .fillEqually
        return stack
    }()
    
    private lazy var contentLayoutGuide: UILayoutGuide = {
        if #available(iOS 26.0, *) {
            return layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))
        }
        
        return safeAreaLayoutGuide
    }()
    
    /// The width the toolbar's content may use: the safe area, or the system's region for a top bar where the
    /// toolbar shares its row with the status items.
    private let barContentGuide = UILayoutGuide()
    private var barContentSafeAreaConstraints: [NSLayoutConstraint] = []
    private var barContentStatusRowConstraints: [NSLayoutConstraint] = []
    private var backgroundEdgeConstraints: [NSLayoutConstraint] = []
    private var backgroundSafeAreaConstraints: [NSLayoutConstraint] = []
    private var sharesStatusRow = false
    
    private var compactAddressBarHorizontalInset: CGFloat {
        if #available(iOS 26.0, *) {
            return 0
        }
        
        return UX.topToolbarHorizontalInset
    }
    
    private var heightConstraint: NSLayoutConstraint!
    private var contentTopConstraint: NSLayoutConstraint!
    private var backgroundBottomConstraint: NSLayoutConstraint!
    private var leadingWidthConstraint: NSLayoutConstraint!
    private var trailingWidthConstraint: NSLayoutConstraint!
    private var standardAddressBarConstraints: [NSLayoutConstraint] = []
    private var compactAddressBarConstraints: [NSLayoutConstraint] = []
    private var widthLimitedStandardAddressBarConstraints: [NSLayoutConstraint] = []
    private var arrangedAddressBarConstraints: [NSLayoutConstraint] = []
    private var leadingButtonsLeadingConstraint: NSLayoutConstraint!
    private var trailingButtonsTrailingConstraint: NSLayoutConstraint!
    private let contentPlacementTracker = DisplayFoldTracker<ContentPlacement>()
    private var contentArrangement: ContentPlacement.Arrangement?
    
    private var layoutState: LayoutState = .hidden
    private var layoutFamily: BrowserLayout.Family = .compact
    private var layoutSidebarButtonVisible = false
    private var isUsingStandardAddressBarWidthLimit = false
    
    // MARK: - Lifecycle
    
    init() {
        super.init(frame: .zero)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateConstraints() {
        updateContentPlacement(animated: true)
        super.updateConstraints()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateContentPlacement(animated: true)
        updateStandardAddressBarLayout()
    }
    
    // MARK: - Layout
    
    func attachAddressBar(_ addressBar: AddressBar) {
        if addressBar.superview !== contentView {
            addressBar.removeFromSuperview()
            contentView.addSubview(addressBar)
        }
        if standardAddressBarConstraints.isEmpty {
            standardAddressBarConstraints = [
                addressBar.leadingAnchor.constraint(equalTo: leadingButtons.trailingAnchor, constant: UX.topToolbarAddressBarSpacing),
                addressBar.trailingAnchor.constraint(equalTo: trailingButtons.leadingAnchor, constant: -UX.topToolbarAddressBarSpacing),
                addressBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.topToolbarAddressBarVerticalSpacing),
                addressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.topToolbarAddressBarVerticalSpacing),
            ]
            widthLimitedStandardAddressBarConstraints = [
                addressBar.centerXAnchor.constraint(equalTo: barContentGuide.centerXAnchor),
                addressBar.widthAnchor.constraint(equalToConstant: UX.topToolbarAddressBarWidthLimit),
                addressBar.leadingAnchor.constraint(greaterThanOrEqualTo: leadingButtons.trailingAnchor, constant: UX.topToolbarAddressBarSpacing),
                addressBar.trailingAnchor.constraint(lessThanOrEqualTo: trailingButtons.leadingAnchor, constant: -UX.topToolbarAddressBarSpacing),
                addressBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.topToolbarAddressBarVerticalSpacing),
                addressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.topToolbarAddressBarVerticalSpacing),
            ]
            arrangedAddressBarConstraints = [
                addressBar.leadingAnchor.constraint(equalTo: leadingAnchor),
                addressBar.trailingAnchor.constraint(equalTo: leadingAnchor),
                addressBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.topToolbarAddressBarVerticalSpacing),
                addressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.topToolbarAddressBarVerticalSpacing),
            ]
            compactAddressBarConstraints = [
                addressBar.leadingAnchor.constraint(
                    equalTo: barContentGuide.leadingAnchor,
                    constant: compactAddressBarHorizontalInset
                ),
                addressBar.trailingAnchor.constraint(
                    equalTo: barContentGuide.trailingAnchor,
                    constant: -compactAddressBarHorizontalInset
                ),
                addressBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: UX.topToolbarAddressBarVerticalSpacing),
                addressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -UX.topToolbarAddressBarVerticalSpacing),
            ]
        }
    }
    
    func detachAddressBar() {
        NSLayoutConstraint.deactivate(allAddressBarConstraints)
        isUsingStandardAddressBarWidthLimit = false
    }
    
    private var allAddressBarConstraints: [NSLayoutConstraint] {
        return standardAddressBarConstraints
        + widthLimitedStandardAddressBarConstraints
        + arrangedAddressBarConstraints
        + compactAddressBarConstraints
    }
    
    func sharePopoverSourceView() -> UIView {
        return shareButton
    }
    
    func extendBackground(to bottomAnchor: NSLayoutYAxisAnchor) {
        backgroundBottomConstraint.isActive = false
        backgroundBottomConstraint = backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        backgroundBottomConstraint.isActive = true
    }
    
    func setBackgroundCollapseOffset(_ offset: CGFloat) {
        backgroundBottomConstraint.constant = -offset
    }
    
    func apply(
        state: LayoutState,
        topInset: CGFloat,
        family: BrowserLayout.Family,
        sidebarButtonVisible: Bool,
        sharesStatusRow: Bool = false,
        keepsBackgroundInsideSafeArea: Bool = false
    ) {
        layoutState = state
        layoutFamily = family
        layoutSidebarButtonVisible = sidebarButtonVisible
        
        UIView.performWithoutAnimation {
            setSharesStatusRow(sharesStatusRow)
            // Beside a vertical bar the background stops with the content, as the bottom toolbar's does.
            NSLayoutConstraint.deactivate(keepsBackgroundInsideSafeArea ? backgroundEdgeConstraints : backgroundSafeAreaConstraints)
            NSLayoutConstraint.activate(keepsBackgroundInsideSafeArea ? backgroundSafeAreaConstraints : backgroundEdgeConstraints)
            contentTopConstraint.constant = topInset
            heightConstraint.constant = topInset + UX.topToolbarContentHeight
            isHidden = state == .hidden
            guard state != .hidden else { return }
            
            let isCompact = state == .compact
            leadingButtons.isHidden = isCompact
            trailingButtons.isHidden = isCompact
            leadingWidthConstraint.constant = isCompact ? 0 : leadingWidth(
                family: family,
                sidebarButtonVisible: sidebarButtonVisible,
                showsDownloads: downloadButton.isShowingDownloads
            )
            trailingWidthConstraint.constant = isCompact ? 0 : UX.topToolbarStandardButtonStackWidth
            
            sidebarButton.isHidden = family != .regular || !sidebarButtonVisible
            libraryButton.isHidden = family == .regular
            downloadButton.isHidden = isCompact || !downloadButton.isShowingDownloads
            
            NSLayoutConstraint.deactivate(allAddressBarConstraints)
            isUsingStandardAddressBarWidthLimit = false
            if isCompact {
                NSLayoutConstraint.activate(compactAddressBarConstraints)
            }
            // The address bar's constraints were all taken off above, so what was applied no longer holds.
            let placement = resolvedContentPlacement()
            contentPlacementTracker.noteApplied(placement)
            applyContentPlacement(placement)
            layoutIfNeeded()
        }
    }
    
    func setContentAlpha(_ alpha: CGFloat) {
        contentView.alpha = alpha
    }
    
    // MARK: - Updates
    
    func updateNavigation(canGoBack: Bool, canGoForward: Bool, canShare: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        shareButton.isEnabled = canShare
    }
    
    func configureNavigationMenus(
        itemsProvider: @escaping (ToolbarButtonMenus.NavigationDirection) -> [NavigationHistoryStore.HistoryItem],
        onSelect: @escaping (ToolbarButtonMenus.NavigationDirection, Int) -> Void
    ) {
        buttonMenus.installNavigationMenus(
            on: backButton,
            forwardButton: forwardButton,
            itemsProvider: itemsProvider,
            onSelect: onSelect,
            isReversed: false
        )
    }
    
    func configureRecentlyClosedTabsMenu(
        isAvailable: @escaping () -> Bool,
        itemsProvider: @escaping () -> [TabManagementStore.RecentlyClosedTabSnapshot],
        onSelect: @escaping (UUID) -> Void
    ) {
        buttonMenus.installRecentlyClosedTabsMenu(
            on: newTabButton,
            isAvailable: isAvailable,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
    }
    
    func configureLibraryMenus(onSelect: @escaping (LibrarySection) -> Void) {
        buttonMenus.installLibraryMenus(
            on: [sidebarButton, libraryButton],
            onSelect: onSelect
        )
    }
    
    func configureTabOverviewMenus(
        tabCountProvider: @escaping () -> Int,
        onCloseAllTabs: @escaping () -> Void,
        onCloseTab: @escaping () -> Void,
        onNewPrivateTab: @escaping () -> Void,
        onNewTab: @escaping () -> Void
    ) {
        buttonMenus.installTabOverviewMenus(
            on: [tabOverviewButton],
            tabCountProvider: tabCountProvider,
            onCloseAllTabs: onCloseAllTabs,
            onCloseTab: onCloseTab,
            onNewPrivateTab: onNewPrivateTab,
            onNewTab: onNewTab
        )
    }
    
    func updateDownload(_ summary: DownloadStoreSummary) {
        downloadButton.applyDownloadSummary(summary)
        updateDownloadButtonVisibility()
    }
    
    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        libraryButton.setImage(
            hasUpdate ? UIImage(named: "reynard.ellipsis.circle.badge") : UIImage(named: "reynard.ellipsis.circle"),
            for: .normal
        )
    }
    
    func syncSidebarButton(splitViewController: UISplitViewController?) {
        sidebarButton.setImage(splitViewController?.displayModeButtonItem.image ?? UIImage(named: "reynard.sidebar.left"), for: .normal)
        sidebarButton.accessibilityLabel = splitViewController?.displayModeButtonItem.accessibilityLabel
    }
    
    func sidebarButtonFrame(in view: UIView) -> CGRect {
        return sidebarButton.convert(sidebarButton.bounds, to: view)
    }
    
    func setSidebarButtonTransition(alpha: CGFloat, hidden: Bool) {
        sidebarButton.alpha = alpha
        sidebarButton.isHidden = hidden
    }
    
    // MARK: - Action Wiring
    
    @objc private func sidebarTapped() { onSidebar?() }
    @objc private func backTapped() { onBack?() }
    @objc private func forwardTapped() { onForward?() }
    @objc private func libraryTapped() { onLibrary?() }
    @objc private func downloadsTapped() { onDownloads?() }
    @objc private func shareTapped() { onShare?() }
    @objc private func newTabTapped() { onNewTab?() }
    @objc private func tabOverviewTapped() { onTabOverview?() }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
    }
    
    private func configureHierarchy() {
        addLayoutGuide(barContentGuide)
        addSubview(backgroundView)
        addSubview(backgroundBottomBorderView)
        addSubview(contentView)
        contentView.addSubview(leadingButtons)
        contentView.addSubview(trailingButtons)
    }
    
    private func configureConstraints() {
        heightConstraint = heightAnchor.constraint(equalToConstant: UX.topToolbarContentHeight)
        contentTopConstraint = contentView.topAnchor.constraint(equalTo: topAnchor)
        backgroundBottomConstraint = backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor)
        leadingWidthConstraint = leadingButtons.widthAnchor.constraint(equalToConstant: UX.topToolbarStandardButtonStackWidth)
        trailingWidthConstraint = trailingButtons.widthAnchor.constraint(equalToConstant: UX.topToolbarStandardButtonStackWidth)
        leadingButtonsLeadingConstraint = leadingButtons.leadingAnchor.constraint(
            equalTo: barContentGuide.leadingAnchor,
            constant: UX.topToolbarHorizontalInset
        )
        trailingButtonsTrailingConstraint = trailingButtons.trailingAnchor.constraint(
            equalTo: barContentGuide.trailingAnchor,
            constant: -UX.topToolbarHorizontalInset
        )
        
        barContentSafeAreaConstraints = [
            barContentGuide.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            barContentGuide.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
        ]
        NSLayoutConstraint.activate(barContentSafeAreaConstraints)
        
        backgroundEdgeConstraints = [
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -UX.backgroundViewHorizontalExtension),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: UX.backgroundViewHorizontalExtension),
        ]
        backgroundSafeAreaConstraints = [
            backgroundView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
        ]
        NSLayoutConstraint.activate(backgroundEdgeConstraints)
        
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundBottomConstraint,
            
            backgroundBottomBorderView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            backgroundBottomBorderView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            backgroundBottomBorderView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
            backgroundBottomBorderView.heightAnchor.constraint(equalToConstant: UX.borderWidth),
            
            heightConstraint,
            contentTopConstraint,
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.heightAnchor.constraint(equalToConstant: UX.topToolbarContentHeight),
            
            leadingButtonsLeadingConstraint,
            leadingButtons.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            leadingWidthConstraint,
            leadingButtons.heightAnchor.constraint(equalToConstant: UX.topToolbarButtonStackHeight),
            
            trailingButtonsTrailingConstraint,
            trailingButtons.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            trailingWidthConstraint,
            trailingButtons.heightAnchor.constraint(equalToConstant: UX.topToolbarButtonStackHeight),
        ])
    }
    
    private func leadingWidth(
        family: BrowserLayout.Family,
        sidebarButtonVisible: Bool,
        showsDownloads: Bool
    ) -> CGFloat {
        guard family == .regular else { return UX.topToolbarStandardButtonStackWidth }
        let visibleButtonCount = (sidebarButtonVisible ? 3 : 2) + (showsDownloads ? 1 : 0)
        return (CGFloat(visibleButtonCount) * UX.topToolbarButtonStackHeight)
        + (CGFloat(max(visibleButtonCount - 1, 0)) * UX.topToolbarButtonSpacing)
    }
    
    private var shouldLimitStandardAddressBarWidth: Bool {
        let layoutInsets = contentLayoutInsets
        let safeWidth = bounds.width - layoutInsets.left - layoutInsets.right
        guard safeWidth > 0 else { return false }
        
        let leadingBoundary = UX.topToolbarHorizontalInset
        + leadingWidthConstraint.constant
        + UX.topToolbarAddressBarSpacing
        let trailingBoundary = safeWidth
        - UX.topToolbarHorizontalInset
        - trailingWidthConstraint.constant
        - UX.topToolbarAddressBarSpacing
        let centeredWidth = min(
            (safeWidth / 2) - leadingBoundary,
            trailingBoundary - (safeWidth / 2)
        ) * 2
        
        return centeredWidth > UX.topToolbarAddressBarWidthLimit
    }
    
    private var contentLayoutInsets: UIEdgeInsets {
        if #available(iOS 27.1, *), sharesStatusRow {
            let frame = statusRowGuide.layoutFrame
            if frame.width > 0 {
                return UIEdgeInsets(top: 0, left: frame.minX, bottom: 0, right: bounds.width - frame.maxX)
            }
        }
        
        if #available(iOS 26.0, *) {
            return edgeInsets(for: .safeArea(cornerAdaptation: .horizontal))
        }
        
        return safeAreaInsets
    }
    
    // MARK: - Fold And Camera
    
    /// Keeps the toolbar's content out of the fold of an iPhone Duo that is partly open, and out from under
    /// its inner camera while that is in use.
    ///
    /// Only what is in the way moves. Held like a book the fold runs through the address bar, which gives up
    /// the part of it that crosses over and keeps the wider side; the buttons at the ends stay where they are.
    /// The system reports both as reserved regions, and reports none on any other device.
    private func updateContentPlacement(animated: Bool) {
        let placement = resolvedContentPlacement()
        let isObstacleChange = contentPlacementTracker.applied.map {
            $0.width == placement.width && $0.obstacles != placement.obstacles
        } ?? false
        contentPlacementTracker.update(
            in: self,
            value: placement,
            animated: animated && isObstacleChange,
            current: { [weak self] in self?.resolvedContentPlacement() ?? placement },
            apply: { [weak self] in self?.applyContentPlacement($0) }
        )
    }
    
    private func resolvedContentPlacement() -> ContentPlacement {
        let width = bounds.width
        guard layoutState == .standard, width > 0 else {
            return ContentPlacement(obstacles: [], width: width, arrangement: nil)
        }
        
        let row = CGRect(
            x: 0,
            y: contentTopConstraint.constant,
            width: width,
            height: UX.topToolbarContentHeight
        )
        var obstacleFrames: [CGRect] = []
        if let fold = verticalDisplayFold(crossing: row), fold.isActive {
            obstacleFrames.append(fold.frame)
        }
        // Elsewhere the system keeps what it reserves at the edges of the window, inside the safe area.
        if sharesStatusRow {
            obstacleFrames.append(contentsOf: displayOcclusions(crossing: row))
        }
        
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let insets = contentLayoutInsets
        let contentStart = isRightToLeft ? insets.right : insets.left
        let contentEnd = width - (isRightToLeft ? insets.left : insets.right)
        let obstacles = obstacleFrames
            .map { frame -> ClosedRange<CGFloat> in
                isRightToLeft ? (width - frame.maxX)...(width - frame.minX) : frame.minX...frame.maxX
            }
            .filter { $0.upperBound > contentStart && $0.lowerBound < contentEnd }
            .sorted { $0.lowerBound < $1.lowerBound }
        guard !obstacles.isEmpty else {
            return ContentPlacement(obstacles: [], width: width, arrangement: nil)
        }
        
        func crosses(_ obstacle: ClosedRange<CGFloat>, _ start: CGFloat, _ end: CGFloat) -> Bool {
            return obstacle.lowerBound < end && obstacle.upperBound > start
        }
        
        // Buttons that would sit in an obstacle step past it, away from their own end of the toolbar.
        let leadingWidth = leadingWidthConstraint.constant
        var leadingStart = contentStart + UX.topToolbarHorizontalInset
        for obstacle in obstacles where crosses(obstacle, leadingStart, leadingStart + leadingWidth) {
            leadingStart = obstacle.upperBound
        }
        let trailingWidth = trailingWidthConstraint.constant
        var trailingEnd = contentEnd - UX.topToolbarHorizontalInset
        for obstacle in obstacles.reversed() where crosses(obstacle, trailingEnd - trailingWidth, trailingEnd) {
            trailingEnd = obstacle.lowerBound
        }
        
        // The address bar takes the widest clear stretch between them, and the leading one of two alike.
        let end = trailingEnd - trailingWidth - UX.topToolbarAddressBarSpacing
        var cursor = leadingStart + leadingWidth + UX.topToolbarAddressBarSpacing
        var stretches: [ClosedRange<CGFloat>] = []
        for obstacle in obstacles {
            if min(obstacle.lowerBound, end) > cursor {
                stretches.append(cursor...min(obstacle.lowerBound, end))
            }
            cursor = max(cursor, obstacle.upperBound)
        }
        if end > cursor {
            stretches.append(cursor...end)
        }
        var addressBar: ClosedRange<CGFloat>?
        for stretch in stretches {
            let currentWidth = addressBar.map { $0.upperBound - $0.lowerBound } ?? 0
            if stretch.upperBound - stretch.lowerBound > currentWidth + 0.5 {
                addressBar = stretch
            }
        }
        guard let addressBar else {
            return ContentPlacement(obstacles: obstacles, width: width, arrangement: nil)
        }
        
        return ContentPlacement(
            obstacles: obstacles,
            width: width,
            arrangement: ContentPlacement.Arrangement(
                leadingButtonsInset: leadingStart - contentStart,
                trailingButtonsInset: contentEnd - trailingEnd,
                addressBar: addressBar
            )
        )
    }
    
    private func applyContentPlacement(_ placement: ContentPlacement) {
        let arrangement = placement.arrangement
        let isArrangementChange = arrangement != contentArrangement
        defer {
            if isArrangementChange {
                onContentArrangementChange?()
            }
        }
        contentArrangement = arrangement
        leadingButtonsLeadingConstraint.constant = arrangement?.leadingButtonsInset ?? UX.topToolbarHorizontalInset
        trailingButtonsTrailingConstraint.constant = -(arrangement?.trailingButtonsInset ?? UX.topToolbarHorizontalInset)
        guard layoutState == .standard else {
            return
        }
        
        guard let arrangement, arrangedAddressBarConstraints.count == 4 else {
            NSLayoutConstraint.deactivate(arrangedAddressBarConstraints)
            setStandardAddressBarWidthLimitEnabled(shouldLimitStandardAddressBarWidth)
            return
        }
        
        NSLayoutConstraint.deactivate(standardAddressBarConstraints + widthLimitedStandardAddressBarConstraints)
        isUsingStandardAddressBarWidthLimit = false
        arrangedAddressBarConstraints[0].constant = arrangement.addressBar.lowerBound
        arrangedAddressBarConstraints[1].constant = arrangement.addressBar.upperBound
        NSLayoutConstraint.activate(arrangedAddressBarConstraints)
    }
    
    // MARK: - Status Row
    
    /// The system's region for a bar of this toolbar's height on the top edge. On the inner display of an
    /// iPhone Duo it lies in the status items' row and ends where they begin.
    @available(iOS 27.1, *)
    private var statusRowGuide: UILayoutGuide {
        return layoutGuide(for: .bar(onEdge: UIRectEdge.top, extent: UX.topToolbarContentHeight))
    }
    
    /// How far below this view's top edge that region starts.
    func statusRowTopInset() -> CGFloat? {
        guard #available(iOS 27.1, *) else {
            return nil
        }
        return edgeInsets(for: .bar(onEdge: UIRectEdge.top, extent: UX.topToolbarContentHeight)).top
    }
    
    private func setSharesStatusRow(_ sharesStatusRow: Bool) {
        guard #available(iOS 27.1, *) else {
            return
        }
        
        guard self.sharesStatusRow != sharesStatusRow else {
            return
        }
        
        self.sharesStatusRow = sharesStatusRow
        if barContentStatusRowConstraints.isEmpty {
            let guide = statusRowGuide
            barContentStatusRowConstraints = [
                barContentGuide.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                barContentGuide.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            ]
        }
        NSLayoutConstraint.deactivate(sharesStatusRow ? barContentSafeAreaConstraints : barContentStatusRowConstraints)
        NSLayoutConstraint.activate(sharesStatusRow ? barContentStatusRowConstraints : barContentSafeAreaConstraints)
    }
    
    private func updateStandardAddressBarLayout() {
        guard layoutState == .standard else {
            return
        }
        
        setStandardAddressBarWidthLimitEnabled(shouldLimitStandardAddressBarWidth)
    }
    
    private func setStandardAddressBarWidthLimitEnabled(_ isEnabled: Bool) {
        // Around a fold or a camera the address bar has a place of its own: see `ContentPlacement`.
        guard contentArrangement == nil else {
            return
        }
        
        let activeConstraints = isEnabled ? widthLimitedStandardAddressBarConstraints : standardAddressBarConstraints
        guard activeConstraints.contains(where: { !$0.isActive }) || isUsingStandardAddressBarWidthLimit != isEnabled else {
            return
        }
        
        NSLayoutConstraint.deactivate(standardAddressBarConstraints + widthLimitedStandardAddressBarConstraints)
        NSLayoutConstraint.activate(activeConstraints)
        isUsingStandardAddressBarWidthLimit = isEnabled
    }
    
    private func updateDownloadButtonVisibility() {
        let isCompact = layoutState == .compact
        downloadButton.isHidden = layoutState != .standard || !downloadButton.isShowingDownloads
        leadingWidthConstraint.constant = isCompact ? 0 : leadingWidth(
            family: layoutFamily,
            sidebarButtonVisible: layoutSidebarButtonVisible,
            showsDownloads: downloadButton.isShowingDownloads
        )
        updateStandardAddressBarLayout()
        layoutIfNeeded()
    }
}
