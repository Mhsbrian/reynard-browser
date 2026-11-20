//
//  BrowserChrome.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class BrowserChrome: UIView, UIGestureRecognizerDelegate {
    private enum UX {
        static let overlayTopSpacing: CGFloat = 12
        static let actionBarSpacing: CGFloat = 0
        static let actionBarFlyOutDuration: TimeInterval = 0.18
        static var actionBarFadeDuration: TimeInterval {
            if #available(iOS 26.0, *) { return 0.05 }
            return 0.12
        }
        static let minimizedToolbarBaseContentHeight: CGFloat = 24
        static let textShrinkTravelFraction: CGFloat = 0.75
        static let toolbarContentFadeDuration: TimeInterval = 0.12
    }
    
    enum PresentationState {
        case browsing
        case tabOverview
        case fullscreenMedia
    }
    
    enum SearchState {
        case inactive
        case focused
        case scrollingEmbeddedSuggestions
        case scrollingDetachedSuggestions
        
        var showsAddressBarDismissButton: Bool {
            switch self {
            case .inactive:
                return false
            case .focused, .scrollingEmbeddedSuggestions, .scrollingDetachedSuggestions:
                return true
            }
        }
    }
    
    /// What the fold of an iPhone Duo that is partly open does to what floats over the page: the action bar
    /// and the overlay under the address bar each keep to one side of it. Distances are from the left edge.
    private struct FoldPlacement: Equatable {
        /// The band to keep clear, where the fold runs from top to bottom through this view.
        let fold: ClosedRange<CGFloat>?
        let width: CGFloat
        /// The side the overlay stays on: the one its address bar is on.
        let overlaySide: ClosedRange<CGFloat>?
    }
    
    struct State {
        let position: BrowserChromePosition
        let mode: BrowserChromeMode
        let presentation: PresentationState
        let search: SearchState
        let topInset: CGFloat
        let family: BrowserLayout.Family
        let toolbarPlacement: BrowserLayout.ToolbarPlacement
        /// Whether the top toolbar shares its row with the status items, and so follows the system's region
        /// for a bar on that edge. The inner display of an iPhone Duo.
        let topToolbarSharesStatusRow: Bool
        let orientation: BrowserLayout.ViewportOrientation
        let isTwoThirdSplitScreenOrSmaller: Bool
        let sidebarButtonVisible: Bool
        let animatesChromeStateChanges: Bool
    }
    
    var onSidebar: (() -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onShare: (() -> Void)?
    var onLibrary: (() -> Void)?
    var onDownloads: (() -> Void)?
    var onNewTab: (() -> Void)?
    /// Links dropped on the tab strip or on the new tab button.
    var onDropLinks: (([URL]) -> Void)?
    var onTabOverview: (() -> Void)?
    var onOverlayDismiss: (() -> Void)?
    var onPageZoomOut: (() -> Void)?
    var onPageZoomIn: (() -> Void)?
    var onPageZoomReset: (() -> Void)?
    var onFindInPage: ((_ query: String?, _ backwards: Bool) async -> (current: Int, total: Int)?)?
    var onClearFindInPage: (() -> Void)?
    var onFindInPageVisibilityChanged: ((Bool) -> Void)?
    var onKeyboardDismissal: (() -> Void)?
    var onToolbarExpansionRequested: (() -> Void)?
    /// The overlay under the address bar began or stopped keeping to one side of a fold.
    var onOverlayFoldSideChanged: (() -> Void)?
    
    let addressBar: AddressBar = {
        let view = AddressBar()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    let tabBar = TabBar()
    private let topToolbar: TopToolbar
    private let bottomToolbar: BottomToolbar
    
    private let toolbarTextLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .label
        label.lineBreakMode = .byTruncatingTail
        label.isHidden = true
        label.isAccessibilityElement = false
        return label
    }()
    
    private let overlayDismissView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isHidden = true
        return view
    }()
    
    private let overlayContentView = ChromeOverlayContentView()
    private let actionBar = ActionBar()
    private lazy var pageZoomDismissView: UIControl = {
        let view = UIControl()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        view.addTarget(self, action: #selector(pageZoomOutsideTapped), for: .touchUpInside)
        return view
    }()
    
    private var overlayWidthConstraint: NSLayoutConstraint!
    private var overlayHeightConstraint: NSLayoutConstraint!
    private var overlayTopConstraint: NSLayoutConstraint?
    private var overlayCenterXConstraint: NSLayoutConstraint?
    private var actionBarTopConstraint: NSLayoutConstraint?
    private var actionBarBottomConstraint: NSLayoutConstraint?
    private var actionBarKeyboardBottomConstraint: NSLayoutConstraint?
    private var actionBarDockOffset: CGFloat = 0
    private var actionBarEdgeConstraints: [NSLayoutConstraint] = []
    private var actionBarSafeAreaConstraints: [NSLayoutConstraint] = []
    private var actionBarSideConstraints: [NSLayoutConstraint] = []
    private var overlaySideConstraints: [NSLayoutConstraint] = []
    private let foldPlacementTracker = DisplayFoldTracker<FoldPlacement>()
    private var foldPlacement: FoldPlacement?
    /// The top toolbar has moved its address bar for a fold or a camera, and has yet to be laid out.
    private var needsOverlayWidthForArrangedAddressBar = false
    private var modernActionBarDismissalID: UUID?
    
    private var state: State?
    private var verticalBarItemsStorage: AnyObject?
    private var toolbarCollapseProgress: CGFloat = 0
    private var toolbarTextCenterProgress: CGFloat = 0
    private var isToolbarContentHidden = false
    private var toolbarContentAlphas: (top: CGFloat, bottom: CGFloat) = (1, 1)
    
    // MARK: - Lifecycle
    
    init() {
        topToolbar = TopToolbar()
        bottomToolbar = BottomToolbar()
        super.init(frame: .zero)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureToolbarActions()
        configureOverlayDismissGesture()
        topToolbar.onContentArrangementChange = { [weak self] in
            // The fold of an iPhone Duo changes the address bar's width under a window that stays the size it
            // was. Nothing else lays this view out again, and the overlay would keep the width it had.
            self?.needsOverlayWidthForArrangedAddressBar = true
            self?.setNeedsLayout()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !pageZoomDismissView.isHidden {
            return super.hitTest(point, with: event)
        }
        if let hitView = bottomToolbar.hitTestAddressBar(
            at: bottomToolbar.convert(point, from: self),
            with: event
        ) {
            return hitView
        }
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
    
    override func updateConstraints() {
        updateFoldPlacement(animated: true)
        super.updateConstraints()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateFoldPlacement(animated: true)
        if needsOverlayWidthForArrangedAddressBar {
            // The overlay follows the address bar's width, which the toolbar's own layout gives it.
            needsOverlayWidthForArrangedAddressBar = false
            topToolbar.layoutIfNeeded()
        }
        updateOverlayWidth()
    }
    
    // MARK: - Anchors And Frames
    
    var topToolbarBottomAnchor: NSLayoutYAxisAnchor {
        return topToolbar.bottomAnchor
    }
    
    var tabBarBottomAnchor: NSLayoutYAxisAnchor {
        return tabBar.bottomAnchor
    }
    
    var bottomToolbarTopAnchor: NSLayoutYAxisAnchor {
        return bottomToolbar.topAnchor
    }
    
    var addressBarBottomAnchor: NSLayoutYAxisAnchor {
        return addressBar.bottomAnchor
    }
    
    /// The strip a hidden toolbar leaves behind, with the page's address in small text. It grows with that text.
    private static var minimizedToolbarContentHeight: CGFloat {
        return UX.minimizedToolbarBaseContentHeight + BarMetrics.growth(forTextOfSize: BarMetrics.minimizedTextSize)
    }
    
    func minimizedToolbarHeight(for mode: BrowserChromeMode) -> CGFloat {
        let inset = mode == .phone ? safeAreaInsets.bottom : (state?.topInset ?? safeAreaInsets.top)
        let minimizedHeight = inset + Self.minimizedToolbarContentHeight
        // A top toolbar in the status items' row has no height to give back: the row stays as tall as the
        // status items whatever the toolbar does. It keeps its place and only the tab strip under it goes.
        if mode != .phone, state?.topToolbarSharesStatusRow == true {
            return max(minimizedHeight, topToolbar.bounds.height)
        }
        return minimizedHeight
    }
    
    /// How much of the bottom toolbar slides away with the page.
    func bottomToolbarScrollHeight(in view: UIView) -> CGFloat {
        return bottomToolbar.layoutState == .empty ? 0 : bottomToolbarTransitionFrame(in: view).height
    }
    
    /// Where the system puts the top of a bar that shares the status items' row, in this view.
    func statusRowTopInset() -> CGFloat? {
        return topToolbar.statusRowTopInset()
    }
    
    /// The toolbar's buttons for the system's vertical bar: see `VerticalBarItems`.
    @available(iOS 27.1, *)
    var verticalBarItems: VerticalBarItems {
        if let items = verticalBarItemsStorage as? VerticalBarItems {
            return items
        }
        
        let items = VerticalBarItems()
        items.onBack = { [weak self] in self?.onBack?() }
        items.onForward = { [weak self] in self?.onForward?() }
        items.onShare = { [weak self] in self?.onShare?() }
        items.onLibrary = { [weak self] in self?.onLibrary?() }
        items.onDownloads = { [weak self] in self?.onDownloads?() }
        items.onNewTab = { [weak self] in self?.onNewTab?() }
        items.onTabOverview = { [weak self] in self?.onTabOverview?() }
        verticalBarItemsStorage = items
        return items
    }
    
    func addressBarFrame(in view: UIView) -> CGRect {
        return addressBar.convert(addressBar.bounds, to: view)
    }
    
    func sharePopoverSourceView() -> UIView {
        guard let state else { return bottomToolbar.sharePopoverSourceView() }
        return state.mode == .phone
        ? bottomToolbar.sharePopoverSourceView()
        : topToolbar.sharePopoverSourceView()
    }
    
    var addressBarButton: AddressBarButton {
        return addressBar.addressBarButton
    }
    
    // MARK: - Layout
    
    func apply(state: State) {
        if self.state?.mode != state.mode {
            toolbarCollapseProgress = 0
            toolbarTextCenterProgress = 0
        }
        
        self.state = state
        addressBar.updateLayout(position: state.position, chromeMode: state.mode)
        attachAddressBar(for: state.mode)
        attachActionBar(for: state.mode)
        applyActionBarHorizontalConstraints()
        configureOverlayPositioningIfNeeded()
        overlayContentView.setLayoutMode(overlayLayoutMode(for: state))
        updateOverlayWidth()
        updateOverlayHeight()
        let canUseActionBar = state.presentation == .browsing && state.search == .inactive
        actionBar.isUserInteractionEnabled = canUseActionBar
        
        if !canUseActionBar {
            dismissActionBar(animated: false)
        }
        
        let topState: TopToolbar.LayoutState
        let bottomState: BottomToolbar.LayoutState
        if state.presentation != .browsing {
            topState = .hidden
            if state.mode == .compact {
                bottomState = state.toolbarPlacement == .verticalBar ? .empty : .collapsed
            } else {
                bottomState = .hidden
            }
        } else {
            topState = resolvedTopState(for: state)
            bottomState = resolvedBottomState(for: state)
        }
        
        topToolbar.apply(
            state: topState,
            topInset: state.topInset,
            family: state.family,
            sidebarButtonVisible: state.sidebarButtonVisible,
            sharesStatusRow: state.topToolbarSharesStatusRow,
            keepsBackgroundInsideSafeArea: state.toolbarPlacement == .verticalBar
        )
        bottomToolbar.apply(
            state: bottomState,
            hidesButtons: state.search == .scrollingEmbeddedSuggestions
        )
        addressBar.setDismissButtonVisible(
            state.search.showsAddressBarDismissButton && state.presentation == .browsing,
            animated: state.animatesChromeStateChanges
        )
    }
    
    func dockAddressBar(offset: CGFloat) {
        bottomToolbar.setAddressBarDockOffset(offset)
    }
    
    func dockActionBar(offset: CGFloat) {
        actionBarDockOffset = offset
        actionBar.isKeyboardDocked = offset != 0
        if offset == 0 {
            actionBarKeyboardBottomConstraint?.isActive = false
            actionBarKeyboardBottomConstraint = nil
            actionBarBottomConstraint?.constant = -UX.actionBarSpacing
            actionBarBottomConstraint?.isActive = true
            actionBar.transform = CGAffineTransform(translationX: 0, y: bottomToolbar.transform.ty)
            return
        }
        
        actionBarBottomConstraint?.isActive = false
        if actionBarKeyboardBottomConstraint == nil {
            actionBarKeyboardBottomConstraint = actionBar.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: offset
            )
        }
        actionBarKeyboardBottomConstraint?.constant = offset
        actionBarKeyboardBottomConstraint?.isActive = true
        actionBar.transform = .identity
    }
    
    var isShowingFindInPage: Bool {
        return actionBar.isShowingFindInPage
    }
    
    // MARK: - Action Bar
    
    var isShowingKeyboardDismissal: Bool {
        return actionBar.isShowingKeyboardDismissal
    }
    
    func showActionBar(_ item: ActionBar.Item, animated: Bool) {
        guard state?.presentation == .browsing,
              state?.search == .inactive else {
            return
        }
        
        modernActionBarDismissalID = nil
        let wasShowingFindInPage = actionBar.isShowingFindInPage
        actionBar.setItem(item)
        if #available(iOS 26.0, *) {
            pageZoomDismissView.isHidden = item != .pageZoom
        }
        if wasShowingFindInPage != actionBar.isShowingFindInPage {
            onFindInPageVisibilityChanged?(actionBar.isShowingFindInPage)
        }
        showActionBar(animated: animated)
    }
    
    func dismissActionBar(animated: Bool) {
        pageZoomDismissView.isHidden = true
        guard !actionBar.isHidden else { return }
        if #available(iOS 26.0, *), animated,
           actionBar.item == .pageZoom || actionBar.isShowingFindInPage {
            guard modernActionBarDismissalID == nil else { return }
            
            let dismissalID = UUID()
            modernActionBarDismissalID = dismissalID
            let wasShowingFindInPage = actionBar.isShowingFindInPage
            let shouldRestoreToolbarAtStart = wasShowingFindInPage && !actionBar.isKeyboardDocked
            let shouldSlide = (actionBar.item == .pageZoom || actionBarDockOffset == 0)
            && !UIAccessibility.isReduceMotionEnabled
            
            if shouldRestoreToolbarAtStart {
                onFindInPageVisibilityChanged?(false)
            }
            
            let screenBottom = window.map { convert($0.bounds, from: $0).maxY } ?? bounds.maxY
            let translationY = shouldSlide
            ? max(0, screenBottom - actionBar.frame.minY)
            : 0
            let animationOptions: UIView.AnimationOptions = shouldRestoreToolbarAtStart
            ? [.beginFromCurrentState, .curveEaseOut]
            : [.beginFromCurrentState, .curveEaseIn]
            
            UIView.animate(
                withDuration: shouldSlide ? UX.actionBarFlyOutDuration : UX.actionBarFadeDuration,
                delay: 0,
                options: animationOptions
            ) {
                self.actionBar.dismissModernContent(
                    translationY: translationY,
                    fadeDuration: shouldSlide ? nil : UX.actionBarFadeDuration
                )
            } completion: { _ in
                guard self.modernActionBarDismissalID == dismissalID else { return }
                self.modernActionBarDismissalID = nil
                self.actionBar.alpha = 0
                self.actionBar.setItem(nil)
                self.dockActionBar(offset: 0)
                
                if wasShowingFindInPage && !shouldRestoreToolbarAtStart {
                    self.onFindInPageVisibilityChanged?(false)
                }
            }
            return
        }
        modernActionBarDismissalID = nil
        
        dockActionBar(offset: 0)
        actionBar.prepareForDismissal()
        let wasShowingFindInPage = actionBar.isShowingFindInPage
        
        let finish = {
            guard self.actionBar.alpha == 0 else { return }
            self.actionBar.setItem(nil)
            if wasShowingFindInPage {
                self.onFindInPageVisibilityChanged?(false)
            }
        }
        
        guard animated else {
            actionBar.alpha = 0
            finish()
            return
        }
        
        UIView.animate(withDuration: UX.actionBarFadeDuration, animations: {
            self.actionBar.alpha = 0
        }) { _ in
            finish()
        }
    }
    
    func setPageZoomLevel(_ level: Int) {
        actionBar.setPageZoomLevel(level)
    }
    
    func updatePageZoomLevel(_ level: Int) {
        guard !actionBar.isHidden,
              actionBar.item == .pageZoom else {
            return
        }
        
        actionBar.setPageZoomLevel(level)
    }
    
    func nextPageZoomLevel() -> Int {
        return actionBar.nextPageZoomLevel()
    }
    
    func previousPageZoomLevel() -> Int {
        return actionBar.previousPageZoomLevel()
    }
    
    // MARK: - Overlay Content
    
    func setOverlayPresentation(
        _ presentation: ChromeOverlayContentView.PresentationState,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        setOverlayDismissViewVisible(presentation != .hidden)
        overlayContentView.setPresentation(presentation, animated: animated) { [weak self] in
            self?.setOverlayDismissViewVisible(presentation != .hidden)
            completion?()
        }
    }
    
    func setOverlayHeightMode(_ heightMode: ChromeOverlayContentView.HeightMode) {
        overlayContentView.setHeightMode(heightMode)
        updateOverlayHeight()
    }
    
    func setOverlayContentHeight(_ contentHeight: CGFloat) {
        overlayContentView.setContentHeight(contentHeight)
        updateOverlayHeight()
    }
    
    func setOverlayAvailableContentHeight(_ availableContentHeight: CGFloat) {
        overlayContentView.setAvailableContentHeight(availableContentHeight)
        updateOverlayHeight()
    }
    
    func setOverlayController(
        _ viewController: UIViewController,
        for page: ChromeOverlayContentView.Page,
        in parentViewController: UIViewController
    ) {
        overlayContentView.setController(viewController, for: page, in: parentViewController)
    }
    
    func removeOverlayController(for page: ChromeOverlayContentView.Page) {
        overlayContentView.removeController(for: page)
    }
    
    private func updateOverlayHeight() {
        overlayHeightConstraint.constant = overlayContentView.resolvedHeight
    }
    
    private func updateOverlayWidth() {
        var width = overlayContentView.layoutMode.resolvedWidth(addressBarWidth: addressBar.bounds.width)
        if let side = foldPlacement?.overlaySide {
            width = min(width, side.upperBound - side.lowerBound)
        }
        if abs(overlayWidthConstraint.constant - width) > 0.5 {
            overlayWidthConstraint.constant = width
        }
    }
    
    // MARK: - Fold
    
    /// Keeps the action bar and the overlay under the address bar on one side of the fold of an iPhone Duo
    /// that is partly open. Nothing else in this view spans the window: the toolbars and the tab strip look
    /// after themselves. No other device reports a fold, and there this changes nothing.
    private func updateFoldPlacement(animated: Bool) {
        let placement = resolvedFoldPlacement()
        let isFoldChange = foldPlacementTracker.applied.map {
            $0.width == placement.width && $0.fold != placement.fold
        } ?? false
        foldPlacementTracker.update(
            in: self,
            value: placement,
            animated: animated && isFoldChange,
            current: { [weak self] in self?.resolvedFoldPlacement() ?? placement },
            apply: { [weak self] in self?.applyFoldPlacement($0) }
        )
    }
    
    private func resolvedFoldPlacement() -> FoldPlacement {
        let width = bounds.width
        guard let band = activeFoldBand(crossing: bounds) else {
            return FoldPlacement(fold: nil, width: width, overlaySide: nil)
        }
        
        let addressBarCenter = addressBar.convert(
            CGPoint(x: addressBar.bounds.midX, y: addressBar.bounds.midY),
            to: self
        ).x
        let overlaySide = addressBarCenter < (band.lowerBound + band.upperBound) / 2
        ? 0...band.lowerBound
        : band.upperBound...width
        return FoldPlacement(fold: band, width: width, overlaySide: overlaySide)
    }
    
    /// Whether the overlay under the address bar is held to one side of the fold of an iPhone Duo that is
    /// partly open, which leaves it about half the room it has otherwise.
    var keepsOverlayBesideFold: Bool {
        return foldPlacement?.overlaySide != nil
    }
    
    private func applyFoldPlacement(_ placement: FoldPlacement) {
        let wasBesideFold = keepsOverlayBesideFold
        foldPlacement = placement
        if wasBesideFold != keepsOverlayBesideFold {
            onOverlayFoldSideChanged?()
        }
        applyActionBarHorizontalConstraints()
        
        if let side = placement.overlaySide, overlaySideConstraints.count == 2 {
            overlaySideConstraints[0].constant = side.lowerBound
            overlaySideConstraints[1].constant = side.upperBound
            NSLayoutConstraint.activate(overlaySideConstraints)
        } else {
            NSLayoutConstraint.deactivate(overlaySideConstraints)
        }
        updateOverlayWidth()
    }
    
    /// The action bar runs from edge to edge, stops at a vertical bar's column, or keeps to the wider side of
    /// the fold, which is the leading one where both are alike.
    private func applyActionBarHorizontalConstraints() {
        NSLayoutConstraint.deactivate(actionBarEdgeConstraints + actionBarSafeAreaConstraints + actionBarSideConstraints)
        if let fold = foldPlacement?.fold, let width = foldPlacement?.width {
            let leftWidth = fold.lowerBound
            let rightWidth = width - fold.upperBound
            let prefersLeft = effectiveUserInterfaceLayoutDirection == .leftToRight
            let usesLeft = abs(leftWidth - rightWidth) <= 1 ? prefersLeft : leftWidth > rightWidth
            actionBarSideConstraints[0].constant = usesLeft ? 0 : fold.upperBound
            actionBarSideConstraints[1].constant = usesLeft ? fold.lowerBound : width
            NSLayoutConstraint.activate(actionBarSideConstraints)
            return
        }
        
        // Beside a vertical bar, what sits above the address bar ends where the address bar does.
        let keepsActionBarInsideSafeArea = state?.toolbarPlacement == .verticalBar
        NSLayoutConstraint.activate(keepsActionBarInsideSafeArea ? actionBarSafeAreaConstraints : actionBarEdgeConstraints)
    }
    
    private func overlayLayoutMode(for state: State) -> ChromeOverlayContentView.LayoutMode {
        switch (state.family, state.orientation) {
        case (.regular, .portrait):
            return .padPortrait
        case (.regular, .landscape) where state.isTwoThirdSplitScreenOrSmaller:
            return .padConstrained
        case (.regular, .landscape):
            return .padLandscape
        case (.compact, _):
            return .phoneLandscape
        }
    }
    
    private func configureOverlayPositioningIfNeeded() {
        guard overlayTopConstraint?.isActive != true,
              overlayCenterXConstraint?.isActive != true else {
            return
        }
        
        NSLayoutConstraint.deactivate([overlayTopConstraint, overlayCenterXConstraint].compactMap { $0 })
        let topConstraint = overlayContentView.topAnchor.constraint(
            equalTo: addressBar.bottomAnchor,
            constant: UX.overlayTopSpacing
        )
        // Just short of required, so that the fold of an iPhone Duo can hold the overlay to one side.
        let centerXConstraint = overlayContentView.centerXAnchor.constraint(equalTo: addressBar.centerXAnchor)
        centerXConstraint.priority = UILayoutPriority(UILayoutPriority.required.rawValue - 1)
        NSLayoutConstraint.activate([topConstraint, centerXConstraint])
        overlayTopConstraint = topConstraint
        overlayCenterXConstraint = centerXConstraint
    }
    
    // MARK: - Address Bar
    
    func configureAddressBar(
        delegate: AddressBarDelegate,
        searchDelegate: AddressBarSearchDelegate,
        gestureDelegate: AddressBarGestureDelegate
    ) {
        addressBar.configure(
            delegate: delegate,
            searchDelegate: searchDelegate,
            gestureDelegate: gestureDelegate
        )
    }
    
    func setAddressBarText(
        _ text: String?,
        locationText: String?,
        locationTitle: String?,
        showsBarMenu: Bool,
        isErrorPage: Bool
    ) {
        addressBar.setText(
            text,
            locationText: locationText,
            locationTitle: locationTitle,
            showsBarMenu: showsBarMenu,
            isErrorPage: isErrorPage
        )
        _ = updateToolbarTextTransition(textCenterProgress: toolbarTextCenterProgress)
    }
    
    func updateAddressBarMenu(url: String?, usesDesktopWebsite: Bool?, readerMode: ReaderModeState) {
        addressBar.updateMenu(url: url, usesDesktopWebsite: usesDesktopWebsite, readerMode: readerMode)
    }
    
    func updateAddressBarAudioButton(isVisible: Bool, isMuted: Bool) {
        addressBar.updateAudioButton(isVisible: isVisible, isMuted: isMuted)
    }
    
    func setAddressBarLoadingProgress(_ progress: Float, isLoading: Bool) {
        addressBar.setLoadingProgress(progress, isLoading: isLoading)
    }
    
    func setAddressBarEditingState(_ state: AddressBar.EditingState) {
        addressBar.setEditingState(state)
    }
    
    func setPreservesAddressBarAutocompleteAfterResign(_ preserves: Bool) {
        addressBar.setPreservesAutocompleteAfterResign(preserves)
    }
    
    func clearAddressBarAutocomplete() {
        addressBar.clearAutocomplete()
    }
    
    func recordAddressBarEdit(previousText: String, currentText: String, isDelete: Bool) {
        addressBar.recordEditForAutocomplete(previousText: previousText, currentText: currentText, isDelete: isDelete)
    }
    
    func applyAddressBarAutocomplete(query: String, result: UserDataSearchResult?, topDomain: String?) {
        addressBar.applySearchAutocomplete(query: query, result: result, topDomain: topDomain)
    }
    
    func resetAddressBarEditing() {
        _ = addressBar.resignFirstResponder()
        addressBar.clearAutocomplete()
        addressBar.setPreservesAutocompleteAfterResign(false)
        addressBar.setEditingState(.inactive)
    }
    
    func resetHorizontalTransition() { addressBar.resetHorizontalTransition() }
    
    func performAfterTransition(_ completion: @escaping () -> Void) -> Bool {
        addressBar.performAfterTransition(completion)
    }
    
    func resignAddressBarFirstResponder() { _ = addressBar.resignFirstResponder() }
    
    func performAfterAddressBarMenuDismissal(_ action: @escaping () -> Void) {
        addressBar.performAfterMenuDismissal(action)
    }
    
    func animateAutomaticTabTransition(to tab: Tab, returning: Bool = false, completion: @escaping () -> Void) {
        addressBar.animateAutomaticTabTransition(to: tab, returning: returning, completion: completion)
    }
    
    var isAddressBarEditing: Bool { return addressBar.isEditingText }
    var addressBarEditing: AddressBar.Editing? { return addressBar.editing }
    
    func resumeAddressBarEditing(_ editing: AddressBar.Editing) { addressBar.resumeEditing(editing) }
    var isShowingAddressBarAutocomplete: Bool { return addressBar.isShowingAutocomplete }
    
    // MARK: - Toolbar Updates
    
    func updateNavigation(canGoBack: Bool, canGoForward: Bool, canShare: Bool) {
        topToolbar.updateNavigation(canGoBack: canGoBack, canGoForward: canGoForward, canShare: canShare)
        bottomToolbar.updateNavigation(canGoBack: canGoBack, canGoForward: canGoForward, canShare: canShare)
        if #available(iOS 27.1, *) {
            verticalBarItems.updateNavigation(canGoBack: canGoBack, canGoForward: canGoForward, canShare: canShare)
        }
    }
    
    func configureNavigationMenus(
        itemsProvider: @escaping (ToolbarButtonMenus.NavigationDirection) -> [NavigationHistoryStore.HistoryItem],
        onSelect: @escaping (ToolbarButtonMenus.NavigationDirection, Int) -> Void
    ) {
        topToolbar.configureNavigationMenus(itemsProvider: itemsProvider, onSelect: onSelect)
        bottomToolbar.configureNavigationMenus(itemsProvider: itemsProvider, onSelect: onSelect)
        if #available(iOS 27.1, *) {
            verticalBarItems.configureNavigationMenus(itemsProvider: itemsProvider, onSelect: onSelect)
        }
    }
    
    func configureRecentlyClosedTabsMenu(
        isAvailable: @escaping () -> Bool,
        itemsProvider: @escaping () -> [TabManagementStore.RecentlyClosedTabSnapshot],
        onSelect: @escaping (UUID) -> Void
    ) {
        topToolbar.configureRecentlyClosedTabsMenu(
            isAvailable: isAvailable,
            itemsProvider: itemsProvider,
            onSelect: onSelect
        )
        if #available(iOS 27.1, *) {
            verticalBarItems.configureRecentlyClosedTabsMenu(
                isAvailable: isAvailable,
                itemsProvider: itemsProvider,
                onSelect: onSelect
            )
        }
    }
    
    func configureLibraryMenus(onSelect: @escaping (LibrarySection) -> Void) {
        topToolbar.configureLibraryMenus(onSelect: onSelect)
        bottomToolbar.configureLibraryMenus(onSelect: onSelect)
        if #available(iOS 27.1, *) {
            verticalBarItems.configureLibraryMenus(onSelect: onSelect)
        }
    }
    
    func configureTabOverviewMenus(
        tabCountProvider: @escaping () -> Int,
        onCloseAllTabs: @escaping () -> Void,
        onCloseTab: @escaping () -> Void,
        onNewPrivateTab: @escaping () -> Void,
        onNewTab: @escaping () -> Void
    ) {
        topToolbar.configureTabOverviewMenus(
            tabCountProvider: tabCountProvider,
            onCloseAllTabs: onCloseAllTabs,
            onCloseTab: onCloseTab,
            onNewPrivateTab: onNewPrivateTab,
            onNewTab: onNewTab
        )
        bottomToolbar.configureTabOverviewMenus(
            tabCountProvider: tabCountProvider,
            onCloseAllTabs: onCloseAllTabs,
            onCloseTab: onCloseTab,
            onNewPrivateTab: onNewPrivateTab,
            onNewTab: onNewTab
        )
        if #available(iOS 27.1, *) {
            verticalBarItems.configureTabOverviewMenus(
                tabCountProvider: tabCountProvider,
                onCloseAllTabs: onCloseAllTabs,
                onCloseTab: onCloseTab,
                onNewPrivateTab: onNewPrivateTab,
                onNewTab: onNewTab
            )
        }
    }
    
    func updateDownload(_ summary: DownloadStoreSummary) {
        bottomToolbar.updateDownload(summary)
        topToolbar.updateDownload(summary)
        if #available(iOS 27.1, *) {
            verticalBarItems.updateDownload(summary)
        }
    }
    
    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        topToolbar.setMenuButtonIndicatesUpdate(hasUpdate)
        bottomToolbar.setMenuButtonIndicatesUpdate(hasUpdate)
        if #available(iOS 27.1, *) {
            verticalBarItems.setMenuButtonIndicatesUpdate(hasUpdate)
        }
    }
    
    func syncSidebarButton(splitViewController: UISplitViewController?) {
        topToolbar.syncSidebarButton(splitViewController: splitViewController)
    }
    
    // MARK: - Action Wiring
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return toolbarCollapseProgress == 1 && state?.presentation == .browsing && state?.search == .inactive
    }
    
    private func configureToolbarActions() {
        for toolbar in [topToolbar as UIView, bottomToolbar] {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(expandToolbar))
            tapGesture.delegate = self
            toolbar.addGestureRecognizer(tapGesture)
        }
        
        topToolbar.onSidebar = { [weak self] in self?.onSidebar?() }
        topToolbar.onBack = { [weak self] in self?.onBack?() }
        topToolbar.onForward = { [weak self] in self?.onForward?() }
        topToolbar.onShare = { [weak self] in self?.onShare?() }
        topToolbar.onLibrary = { [weak self] in self?.onLibrary?() }
        topToolbar.onDownloads = { [weak self] in self?.onDownloads?() }
        topToolbar.onNewTab = { [weak self] in self?.onNewTab?() }
        topToolbar.onDropLinks = { [weak self] urls in self?.onDropLinks?(urls) }
        tabBar.onDropLinks = { [weak self] urls in self?.onDropLinks?(urls) }
        topToolbar.onTabOverview = { [weak self] in self?.onTabOverview?() }
        
        bottomToolbar.onBack = { [weak self] in self?.onBack?() }
        bottomToolbar.onForward = { [weak self] in self?.onForward?() }
        bottomToolbar.onShare = { [weak self] in self?.onShare?() }
        bottomToolbar.onLibrary = { [weak self] in self?.onLibrary?() }
        bottomToolbar.onDownloads = { [weak self] in self?.onDownloads?() }
        bottomToolbar.onTabOverview = { [weak self] in self?.onTabOverview?() }
        
        actionBar.onPageZoomOut = { [weak self] in self?.onPageZoomOut?() }
        actionBar.onPageZoomIn = { [weak self] in self?.onPageZoomIn?() }
        actionBar.onPageZoomReset = { [weak self] in self?.onPageZoomReset?() }
        actionBar.onFindInPage = { [weak self] query, backwards in
            return await self?.onFindInPage?(query, backwards)
        }
        actionBar.onClearFindInPage = { [weak self] in self?.onClearFindInPage?() }
        actionBar.onClose = { [weak self] in self?.dismissActionBar(animated: true) }
        actionBar.onKeyboardDismissal = { [weak self] in self?.onKeyboardDismissal?() }
    }
    
    @objc private func expandToolbar() {
        onToolbarExpansionRequested?()
    }
    
    // MARK: - Transitions
    
    func bottomToolbarTransitionView() -> UIView? {
        return bottomToolbar.snapshotView(afterScreenUpdates: false)
    }
    
    func bottomToolbarTransitionFrame(in view: UIView) -> CGRect {
        return bottomToolbar.convert(bottomToolbar.bounds, to: view)
    }
    
    func topToolbarTransitionView() -> UIView? {
        return topToolbar.snapshotView(afterScreenUpdates: false)
    }
    
    func topToolbarTransitionFrame(in view: UIView) -> CGRect {
        return topToolbar.convert(topToolbar.bounds, to: view)
    }
    
    func setToolbarTransition(
        topOffset: CGFloat,
        bottomOffset: CGFloat,
        tabBarCollapseOffset: CGFloat,
        collapseProgress: CGFloat,
        textCenterProgress: CGFloat,
        isBottomToolbarCollapsed: Bool,
        animatesContent: Bool
    ) {
        topToolbar.transform = CGAffineTransform(translationX: 0, y: topOffset)
        topToolbar.setBackgroundCollapseOffset(tabBarCollapseOffset)
        bottomToolbar.transform = CGAffineTransform(translationX: 0, y: bottomOffset)
        actionBar.transform = actionBarKeyboardBottomConstraint == nil
        ? CGAffineTransform(translationX: 0, y: bottomOffset)
        : .identity
        let previousProgress = toolbarCollapseProgress
        toolbarCollapseProgress = collapseProgress
        toolbarTextCenterProgress = textCenterProgress
        let isTextFullSize = updateToolbarTextTransition(textCenterProgress: textCenterProgress)
        if collapseProgress == 0 || (collapseProgress < previousProgress && isTextFullSize) {
            isToolbarContentHidden = false
        } else if collapseProgress > previousProgress {
            isToolbarContentHidden = true
        }
        
        let contentAlpha: CGFloat = isToolbarContentHidden ? 0 : 1
        let topAlpha: CGFloat = state?.mode == .phone ? 1 : contentAlpha
        let bottomAlpha: CGFloat = isBottomToolbarCollapsed ? 0 : (state?.mode == .pad ? 1 : contentAlpha)
        guard !animatesContent || toolbarContentAlphas != (topAlpha, bottomAlpha) else {
            return
        }
        toolbarContentAlphas = (topAlpha, bottomAlpha)
        UIView.animate(
            withDuration: animatesContent ? UX.toolbarContentFadeDuration : 0,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
        ) {
            self.topToolbar.setContentAlpha(topAlpha)
            self.bottomToolbar.setContentAlpha(bottomAlpha)
        }
    }
    
    func setChromeTransition(topAlpha: CGFloat, bottomAlpha: CGFloat, bottomTranslationY: CGFloat = 0) {
        topToolbar.alpha = topAlpha
        bottomToolbar.alpha = bottomAlpha
        bottomToolbar.transform = CGAffineTransform(translationX: 0, y: bottomTranslationY)
        actionBar.transform = actionBarKeyboardBottomConstraint == nil
        ? CGAffineTransform(translationX: 0, y: bottomTranslationY)
        : .identity
    }
    
    func setBottomToolbarHidden(_ hidden: Bool) {
        bottomToolbar.isHidden = hidden
    }
    
    func sidebarButtonFrame(in view: UIView) -> CGRect {
        return topToolbar.sidebarButtonFrame(in: view)
    }
    
    func setSidebarButtonTransition(alpha: CGFloat, hidden: Bool) {
        topToolbar.setSidebarButtonTransition(alpha: alpha, hidden: hidden)
    }
    
    private func updateToolbarTextTransition(textCenterProgress: CGFloat) -> Bool {
        guard toolbarCollapseProgress > 0,
              let state,
              state.presentation == .browsing,
              state.search == .inactive,
              let presentation = addressBar.toolbarTextPresentation(in: self) else {
            toolbarTextLabel.isHidden = true
            addressBar.setDisplayTextHidden(false)
            return true
        }
        addressBar.setDisplayTextHidden(true)
        let isBottom = state.mode == .phone
        let toolbar = isBottom ? bottomToolbar as UIView : topToolbar
        let offset = toolbar.transform.ty
        let totalTravel = abs(offset) / toolbarCollapseProgress
        let expandedFrame = presentation.frame.offsetBy(dx: 0, dy: -offset)
        let minimizedTextCenterY = isBottom
        ? bounds.maxY - safeAreaInsets.bottom - Self.minimizedToolbarContentHeight / 2
        : state.topInset + Self.minimizedToolbarContentHeight / 2
        let minimizedScale = BarMetrics.scaled(BarMetrics.minimizedTextSize) / presentation.font.pointSize
        let minimizedTextHeight = presentation.font.lineHeight * minimizedScale
        let targetEdge = minimizedTextCenterY + (isBottom ? minimizedTextHeight : -minimizedTextHeight) / 2
        let edgeTravel = max(0, isBottom ? targetEdge - expandedFrame.maxY : expandedFrame.minY - targetEdge)
        // Pin the outer text edge before scaling, leaving the last part of the travel for the toolbar.
        let shrinkTravel = max(1, (totalTravel - edgeTravel) * UX.textShrinkTravelFraction)
        let shrinkProgress = min(max((abs(offset) - edgeTravel) / shrinkTravel, 0), 1)
        let scale = 1 + (minimizedScale - 1) * shrinkProgress
        let textHeight = presentation.font.lineHeight * scale
        let textEdge = isBottom ? min(presentation.frame.maxY, targetEdge) : max(presentation.frame.minY, targetEdge)
        toolbarTextLabel.font = presentation.font
        toolbarTextLabel.attributedText = presentation.text
        toolbarTextLabel.bounds = CGRect(x: 0, y: 0, width: expandedFrame.width, height: presentation.font.lineHeight)
        // Beside a vertical bar the text is centred in what is left of the width, as the address bar is.
        let centerX = state.toolbarPlacement == .verticalBar
        ? bounds.inset(by: UIEdgeInsets(top: 0, left: safeAreaInsets.left, bottom: 0, right: safeAreaInsets.right)).midX
        : bounds.midX
        toolbarTextLabel.center = CGPoint(
            x: expandedFrame.midX + (centerX - expandedFrame.midX) * textCenterProgress,
            y: textEdge + (isBottom ? -textHeight : textHeight) / 2
        )
        toolbarTextLabel.transform = CGAffineTransform(scaleX: scale, y: scale)
        toolbarTextLabel.alpha = toolbar.alpha
        toolbarTextLabel.isHidden = toolbar.isHidden
        return shrinkProgress == 0
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
    }
    
    private func configureHierarchy() {
        addSubview(topToolbar)
        addSubview(tabBar)
        addSubview(bottomToolbar)
        addSubview(toolbarTextLabel)
        addSubview(overlayDismissView)
        addSubview(overlayContentView)
        addSubview(pageZoomDismissView)
        addSubview(actionBar)
    }
    
    private func configureConstraints() {
        overlayWidthConstraint = overlayContentView.widthAnchor.constraint(equalToConstant: 0)
        overlayHeightConstraint = overlayContentView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            topToolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topToolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topToolbar.topAnchor.constraint(equalTo: topAnchor),
            
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: topToolbar.bottomAnchor),
            
            bottomToolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomToolbar.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            overlayDismissView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            overlayDismissView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayDismissView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayDismissView.bottomAnchor.constraint(equalTo: bottomToolbar.topAnchor),
            
            overlayWidthConstraint,
            overlayHeightConstraint,
            
            pageZoomDismissView.topAnchor.constraint(equalTo: topAnchor),
            pageZoomDismissView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pageZoomDismissView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageZoomDismissView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
        ])
        actionBarEdgeConstraints = [
            actionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        actionBarSafeAreaConstraints = [
            actionBar.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
        ]
        // Left and right: the fold is a place on the hardware, whatever the language.
        actionBarSideConstraints = [
            actionBar.leftAnchor.constraint(equalTo: leftAnchor),
            actionBar.rightAnchor.constraint(equalTo: leftAnchor),
        ]
        overlaySideConstraints = [
            overlayContentView.leftAnchor.constraint(greaterThanOrEqualTo: leftAnchor),
            overlayContentView.rightAnchor.constraint(lessThanOrEqualTo: leftAnchor),
        ]
        NSLayoutConstraint.activate(actionBarEdgeConstraints)
        topToolbar.extendBackground(to: tabBar.bottomAnchor)
        bottomToolbar.configureTopAnchor(to: safeAreaLayoutGuide.bottomAnchor)
    }
    
    private func configureOverlayDismissGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(overlayDismissViewTapped))
        overlayDismissView.addGestureRecognizer(tapGesture)
    }
    
    private func setOverlayDismissViewVisible(_ visible: Bool) {
        overlayDismissView.isHidden = !visible
    }
    
    @objc private func overlayDismissViewTapped() {
        onOverlayDismiss?()
    }
    
    @objc private func pageZoomOutsideTapped() {
        dismissActionBar(animated: true)
    }
    
    // MARK: - State Resolution
    
    private func attachAddressBar(for mode: BrowserChromeMode) {
        topToolbar.detachAddressBar()
        bottomToolbar.detachAddressBar()
        switch mode {
        case .phone:
            bottomToolbar.attachAddressBar(addressBar)
        case .compact, .pad:
            topToolbar.attachAddressBar(addressBar)
        }
    }
    
    private func attachActionBar(for mode: BrowserChromeMode) {
        NSLayoutConstraint.deactivate([
            actionBarTopConstraint,
            actionBarBottomConstraint,
            actionBarKeyboardBottomConstraint,
        ].compactMap { $0 })
        actionBarKeyboardBottomConstraint = nil
        switch mode {
        case .pad:
            let constraint = actionBar.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -UX.actionBarSpacing
            )
            constraint.isActive = true
            actionBarBottomConstraint = constraint
            actionBarTopConstraint = nil
        case .phone, .compact:
            let constraint = actionBar.bottomAnchor.constraint(
                equalTo: bottomToolbar.topAnchor,
                constant: -UX.actionBarSpacing
            )
            constraint.isActive = true
            actionBarBottomConstraint = constraint
            actionBarTopConstraint = nil
        }
        
        if actionBarDockOffset != 0 {
            actionBarBottomConstraint?.isActive = false
            actionBarKeyboardBottomConstraint = actionBar.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: actionBarDockOffset
            )
            actionBarKeyboardBottomConstraint?.isActive = true
        }
    }
    
    private func showActionBar(animated: Bool) {
        actionBar.isHidden = false
        let animations = {
            self.actionBar.alpha = 1
        }
        
        guard animated else {
            animations()
            return
        }
        
        UIView.animate(withDuration: UX.actionBarFadeDuration, animations: animations)
    }
    
    private func resolvedTopState(for state: State) -> TopToolbar.LayoutState {
        switch state.mode {
        case .phone: return .hidden
        case .compact: return .compact
        case .pad: return .standard
        }
    }
    
    private func resolvedBottomState(for state: State) -> BottomToolbar.LayoutState {
        switch state.mode {
        case .pad:
            return .hidden
        case .compact:
            return state.toolbarPlacement == .verticalBar ? .empty : .compact
        case .phone:
            switch state.search {
            case .inactive, .focused, .scrollingEmbeddedSuggestions:
                return state.toolbarPlacement == .verticalBar ? .addressOnly : .standard
            case .scrollingDetachedSuggestions: return .hidden
            }
        }
    }
}
