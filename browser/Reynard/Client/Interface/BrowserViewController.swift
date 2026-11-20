//
//  BrowserViewController.swift
//  Reynard
//
//  Created by Minh Ton on 4/3/26.
//

import GeckoView
import UIKit

final class BrowserViewController: UIViewController, GeckoScreenOrientationDelegate {
    private enum UX {
        static let layoutAnimationDuration: TimeInterval = 0.22
        static let fallbackTopInset: CGFloat = 24
        static let keyboardAnimationDuration: TimeInterval = 0.25
        static let keyboardAnimationCurve: UInt = 7
        static let floatingKeyboardWidthRatio: CGFloat = 0.8
    }
    
    private struct KeyboardAnimation {
        let duration: TimeInterval
        let curve: UIView.AnimationOptions
    }
    
    // MARK: - State
    
    let sessionManager: SessionManager
    lazy var tabManager: TabManagerImplementation = adoptedSidebarContent?.tabManager ?? TabManagerImplementation(
        delegate: self,
        sessionManager: sessionManager
    )
    private var lockedOrientations: UIInterfaceOrientationMask?
    private var pendingOrientationRequest: (
        id: UUID,
        orientations: UIInterfaceOrientationMask,
        completion: (GeckoOrientationLockResult) -> Void
    )?
    private var preFullscreenOrientation: UIInterfaceOrientation?
    weak var fullscreenSession: GeckoSession?
    private(set) var sidebarRole: SidebarRole
    private let adoptedSidebarContent: BrowserViewController?
    var sidebarContentToAdopt: BrowserViewController? { return adoptedSidebarContent }
    private var needsSidebarHost = false
    private var isSidebarHostAdoptionScheduled = false
    private var hingeInteraction: UIInteraction?
    private var shouldRestoreContentFocus = false
    private(set) var browserLayout = BrowserLayout.initial(
        family: BrowserLayout.usesTabletWindowRules ? .regular : .compact
    )
    private var resolvedLayoutEnvironment: BrowserLayout.Environment?
    private var appliedHomepageGridWidth: HomepageGridWidth?
    
    // MARK: - Views And Coordinators
    
    let tabOverview = TabOverview()
    let contentView = ContentView()
    lazy var browserChrome = BrowserChrome()
    var tabBar: TabBar { return browserChrome.tabBar }
    
    private(set) lazy var toolbarController = ToolbarController(
        browserChrome: browserChrome,
        tabBar: tabBar,
        contentView: contentView,
        rootView: view
    )
    
    lazy var overlayCoordinator = OverlayCoordinator(host: self)
    lazy var homepageOverlayCoordinator = HomepageOverlayCoordinator(
        delegate: self,
        overlayCoordinator: overlayCoordinator,
        toolbarController: toolbarController
    )
    lazy var searchOverlayCoordinator = SearchOverlayCoordinator(
        delegate: self,
        overlayCoordinator: overlayCoordinator,
        toolbarController: toolbarController
    )
    lazy var contextMenuCoordinator = ContextMenuCoordinator(host: self, sessionManager: sessionManager)
    lazy var downloadsCoordinator = DownloadsCoordinator(delegate: self)
    lazy var sidebarCoordinator = SidebarCoordinator(
        host: self,
        canHostSidebar: sidebarRole == .host
    )
    lazy var addonCoordinator = AddonCoordinator(
        dataSource: self,
        delegate: self,
        sessionManager: sessionManager
    )
    
    private(set) var isShowingFullscreenMedia = false {
        didSet {
            setNeedsStatusBarAppearanceUpdate()
        }
    }
    
    // MARK: - Lifecycle
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if #available(iOS 26.0, *) {
            return .default
        }
        
        guard browserLayout.chromeMode == .phone,
              !tabOverview.isPresented else {
            return .default
        }
        
        switch contentView.state.overlayPresentation {
        case .visible(.homepage):
            let foregroundColor = HomepageWallpaper.foregroundColor(for: .embedded(layout: browserLayout))
            return foregroundColor.isLightColor(in: traitCollection) ? .lightContent : .darkContent
        case .visible(.search):
            return .default
        case .hidden:
            let backgroundColor = tabManager.selectedTab.map {
                sessionManager.pageBackgroundColor(for: $0.session)
            } ?? .systemBackground
            return backgroundColor.isLightColor(in: traitCollection) ? .darkContent : .lightContent
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return isShowingFullscreenMedia
    }
    
    override var childForStatusBarHidden: UIViewController? {
        return sidebarCoordinator.statusBarController
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if let lockedOrientations {
            return lockedOrientations
        }
        
        // Which way up a device may be held is about the device, not about the window.
        return BrowserLayout.usesTabletWindowRules ? .all : .allButUpsideDown
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        let allowedOrientations = lockedOrientations ?? supportedInterfaceOrientations
        return preferredInterfaceOrientation(allowedBy: allowedOrientations) ?? .portrait
    }
    
    init(canHostSidebar: Bool = true) {
        if !canHostSidebar {
            sidebarRole = .content
        } else {
            sidebarRole = BrowserLayout.usesTabletWindowRules ? .host : .standalone
        }
        adoptedSidebarContent = nil
        sessionManager = SessionManager()
        super.init(nibName: nil, bundle: nil)
    }
    
    /// The container for a browser that is already running: see `adoptSidebarHostIfPossible()`.
    ///
    /// It shares the browser's session and tab managers, so that what the scene tells its root view controller
    /// goes on reaching the browser.
    private init(adopting content: BrowserViewController) {
        sidebarRole = .host
        adoptedSidebarContent = content
        sessionManager = content.sessionManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopScreenOrientationHandling()
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        observeLayoutTraits()
        
        if sidebarCoordinator.installHostIfNeeded() {
            return
        }
        
        RuntimePreferences.apply() // Gecko prefs
        
        configureBrowserInterface()
        observeNotifications()
        contextMenuCoordinator.configure()
        downloadsCoordinator.startObservingStore()
        downloadsCoordinator.syncToolbarButtonState()
        tabOverview.restoreMode(TabOverview.Mode(tabMode: TabManagementStore.shared.preferredRestoredMode()))
        syncBrowserNavigationChrome(animated: false)
        browserChrome.syncSidebarButton(splitViewController: splitViewController)
        applyUpdateMenuButtonBadge()
        
        observeHinge()
        
        tabManager.createInitialTab()
        refreshAddressBar()
        homepageOverlayCoordinator.updatePresentation(animated: false)
        
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            await self.addonCoordinator.start()
            if let session = self.tabManager.selectedTab?.session {
                self.sessionManager.setAddonTabActive(true, for: session)
            }
        }
        
        updateBrowserLayout(animated: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        toolbarController.unlock(for: .viewPresentation)
        performContentLifecycle {
            syncBrowserNavigationChrome(animated: animated)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        performContentLifecycle {
            toolbarController.lock(for: .viewPresentation)
            shouldRestoreContentFocus =
            tabManager.selectedTab?.session.engineView?.isFirstResponder == true
            view.endEditing(true)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        performContentLifecycle {
            syncBrowserNavigationChrome(animated: false)
            browserChrome.syncSidebarButton(splitViewController: splitViewController)
            downloadsCoordinator.syncToolbarButtonState()
            updateBrowserLayout(animated: false)
            if shouldRestoreContentFocus {
                shouldRestoreContentFocus = false
                requestContentKeyboardFocus()
            }
            
            requestHomepageAddressBarFocus()
            scheduleSidebarHostAdoption()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let showsHomepage = tabManager.selectedTab.map(homepageOverlayCoordinator.isHomepageTab) ?? false
        toolbarController.updateLayout(
            chromeMode: browserLayout.chromeMode,
            isToolbarEnabled: !isShowingFullscreenMedia,
            extendsContentBehindToolbar: showsHomepage
        )
        homepageOverlayCoordinator.updateVisibleContentInsets()
        invalidateNavigationThumbnailsIfNeeded()
        updateHomepageGridWidthIfNeeded()
        scheduleSidebarHostAdoption()
    }
    
    /// The sidebar changes the width of the page area without changing the layout, and the homepage's grid
    /// follows that width wherever the layout comes from size classes.
    private func updateHomepageGridWidthIfNeeded() {
        guard !BrowserLayout.usesTabletWindowRules,
              browserLayout.family == .regular else {
            appliedHomepageGridWidth = nil
            return
        }
        
        let gridWidth = homepageGridWidth
        guard appliedHomepageGridWidth != gridWidth else {
            return
        }
        
        let isFirstPass = appliedHomepageGridWidth == nil
        appliedHomepageGridWidth = gridWidth
        if !isFirstPass {
            homepageOverlayCoordinator.updatePresentation(animated: false)
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *),
           let previousTraitCollection,
           previousTraitCollection.horizontalSizeClass != traitCollection.horizontalSizeClass
            || previousTraitCollection.verticalSizeClass != traitCollection.verticalSizeClass {
            // The size classes have their own registration on these systems: see `observeLayoutTraits()`.
            return
        }
        layoutTraitsDidChange()
    }
    
    /// Follows the size classes the layout is chosen from. Before iOS 17 `traitCollectionDidChange(_:)` does it.
    private func observeLayoutTraits() {
        guard #available(iOS 17.0, *) else {
            return
        }
        
        registerForTraitChanges(
            [UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]
        ) { (viewController: BrowserViewController, _: UITraitCollection) in
            viewController.layoutTraitsDidChange()
        }
    }
    
    private func layoutTraitsDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isViewLoaded,
                  self.view.window != nil,
                  !self.sidebarCoordinator.refreshHostVisibility() else {
                return
            }
            self.syncBrowserNavigationChrome(animated: false)
            self.browserChrome.syncSidebarButton(splitViewController: self.splitViewController)
            self.refreshAddressBar()
            self.updateBrowserLayout(animated: false)
            self.tabOverview.invalidateCollectionLayouts()
            self.tabBar.invalidateLayout()
            self.tabOverview.refreshForCurrentOrientation()
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if let readerSettings = presentedViewController as? ReaderSettingsViewController {
            readerSettings.dismiss(animated: false)
        }
        performContentLifecycle {
            toolbarController.reset(animated: false)
            coordinator.animate { _ in
                self.syncBrowserNavigationChrome(animated: false)
                self.browserChrome.syncSidebarButton(splitViewController: self.splitViewController)
                self.tabOverview.invalidateCollectionLayouts()
                self.tabBar.invalidateLayout()
            } completion: { _ in
                self.syncBrowserNavigationChrome(animated: false)
                self.browserChrome.syncSidebarButton(splitViewController: self.splitViewController)
                self.contentView.setTransitionTransform(.identity)
                self.browserChrome.resetHorizontalTransition()
                self.tabOverview.refreshForCurrentOrientation()
                DispatchQueue.main.async {
                    guard self.isViewLoaded, self.view.window != nil else {
                        return
                    }
                    self.updateBrowserLayout(animated: false)
                }
            }
        }
    }
    
    // MARK: - Browser Layout
    
    private func configureBrowserInterface() {
        contentView.keyCommandDelegate = self
        contentView.onAppearanceChanged = { [weak self] in
            self?.setNeedsStatusBarAppearanceUpdate()
        }
        browserChrome.configureAddressBar(
            delegate: self,
            searchDelegate: self,
            gestureDelegate: self
        )
        configureBrowserChromeActions()
        tabBar.dataSource = self
        tabOverview.configure(dataSource: self, delegate: self, presentationContext: self)
        
        view.addSubview(contentView)
        view.addSubview(browserChrome)
        view.addSubview(tabOverview)
        contentView.configureLayout(
            topAnchor: view.topAnchor,
            bottomAnchor: view.bottomAnchor
        )
        
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).withPriority(.defaultHigh),
            contentView.bottomAnchor.constraint(equalTo: browserChrome.bottomToolbarTopAnchor).withPriority(.defaultHigh),
            browserChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browserChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browserChrome.topAnchor.constraint(equalTo: view.topAnchor),
            browserChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            tabOverview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabOverview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabOverview.topAnchor.constraint(equalTo: view.topAnchor),
            tabOverview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    private func configureBrowserChromeActions() {
        contentView.onBack = { [weak self] in
            self?.tabManager.goBack()
        }
        contentView.onForward = { [weak self] in
            self?.tabManager.goForward()
        }
        contentView.onHistorySwipeBegan = { [weak self] in
            self?.captureOutgoingHistoryThumbnail()
        }
        contentView.onErrorAction = { [weak self] action in
            self?.performErrorPageAction(action)
        }
        browserChrome.onSidebar = { [weak self] in
            self?.sidebarCoordinator.toggle(animated: true)
        }
        browserChrome.onBack = { [weak self] in
            self?.toolbarController.reset(preserveManualCollapse: true)
            self?.prepareThumbnailForNavigation()
            self?.tabManager.goBack()
        }
        browserChrome.onForward = { [weak self] in
            self?.toolbarController.reset(preserveManualCollapse: true)
            self?.prepareThumbnailForNavigation()
            self?.tabManager.goForward()
        }
        browserChrome.configureNavigationMenus(
            itemsProvider: { [weak self] direction in
                guard let self,
                      let tab = self.tabManager.selectedTab else {
                    return []
                }
                
                let snapshot = self.tabManager.navigationHistory(for: tab)
                switch direction {
                case .back:
                    return snapshot.backHistory
                case .forward:
                    return snapshot.forwardHistory
                }
            },
            onSelect: { [weak self] direction, index in
                guard let self else {
                    return
                }
                
                self.toolbarController.reset(preserveManualCollapse: true)
                self.prepareThumbnailForNavigation()
                switch direction {
                case .back:
                    self.tabManager.goBack(to: index)
                case .forward:
                    self.tabManager.goForward(to: index)
                }
            }
        )
        browserChrome.configureLibraryMenus { [weak self] section in
            self?.presentLibrary(initialSection: section)
        }
        browserChrome.configureRecentlyClosedTabsMenu(
            isAvailable: { [weak self] in
                guard let self else {
                    return false
                }
                return self.tabManager.selectedTabMode == .regular
            },
            itemsProvider: {
                TabManagementStore.shared.recentlyClosedTabs(
                    limit: Prefs.HomepageSettings.recentlyClosedTabLimit
                )
            },
            onSelect: { [weak self] id in
                guard let self,
                      self.tabManager.selectedTabMode == .regular else {
                    return
                }
                
                self.toolbarController.reset()
                self.dismissAddressBarEditingAndOverlays()
                _ = self.tabManager.restoreRecentlyClosedTab(id: id)
            }
        )
        browserChrome.configureTabOverviewMenus(
            tabCountProvider: { [weak self] in
                self?.tabManager.activeTabs.count ?? 0
            },
            onCloseAllTabs: { [weak self] in
                self?.closeAllTabs()
            },
            onCloseTab: { [weak self] in
                self?.closeTab()
            },
            onNewPrivateTab: { [weak self] in
                self?.createNewTabAnimated(mode: .private)
            },
            onNewTab: { [weak self] in
                self?.createNewTabAnimated(mode: .regular)
            }
        )
        browserChrome.onShare = { [weak self] in
            guard let self else {
                return
            }
            guard let tab = self.tabManager.selectedTab,
                  let url = self.tabManager.shareableURL(for: tab) else {
                return
            }
            let sourceView = self.browserChrome.sharePopoverSourceView()
            self.presentShareSheet(
                items: [url],
                sourceView: sourceView,
                sourceRect: sourceView.bounds,
                applicationActivities: [
                    BookmarkActivity(url: url),
                    AddToFavoritesActivity(url: url),
                    FindInPageActivity(url: url),
                    PagePrintActivity(session: tab.session, jobName: tab.title)
                ],
                onActivityPerformed: { [weak self] activityType in
                    guard let self else {
                        return
                    }
                    if activityType == BookmarkActivity.identifier {
                        self.presentBookmarkEditor(addToFavorites: false)
                    } else if activityType == AddToFavoritesActivity.identifier {
                        self.presentBookmarkEditor(addToFavorites: true)
                    } else if activityType == FindInPageActivity.identifier {
                        self.browserChrome.showActionBar(.findInPage(), animated: true)
                    }
                }
            )
        }
        browserChrome.onLibrary = { [weak self] in
            self?.presentLibrary()
        }
        browserChrome.onDownloads = { [weak self] in
            self?.presentLibrary(initialSection: .downloads)
        }
        browserChrome.onNewTab = { [weak self] in
            self?.createNewTab()
        }
        browserChrome.onTabOverview = { [weak self] in
            self?.setTabOverviewVisible(true, animated: true)
        }
        browserChrome.onOverlayDismiss = { [weak self] in
            self?.toolbarController.reset()
            self?.dismissAddressBarEditingAndChromeOverlay()
        }
        browserChrome.onPageZoomOut = { [weak self] in
            self?.setSelectedPageZoomToPreviousLevel()
        }
        browserChrome.onPageZoomIn = { [weak self] in
            self?.setSelectedPageZoomToNextLevel()
        }
        browserChrome.onPageZoomReset = { [weak self] in
            self?.setSelectedPageZoomLevel(Prefs.BrowsingSettings.defaultPageZoomLevel)
        }
        browserChrome.onFindInPage = { [weak self] query, backwards in
            guard let self,
                  let session = self.tabManager.selectedTab?.session else {
                return nil
            }
            
            if query != nil {
                session.setFindInPageMatchHighlighting(true)
            }
            let result = try? await session.findInPage(query, backwards: backwards)
            guard self.tabManager.selectedTab?.session === session else {
                return nil
            }
            guard let result else {
                return nil
            }
            return (result.current, result.total)
        }
        browserChrome.onClearFindInPage = { [weak self] in
            self?.tabManager.selectedTab?.session.clearFindInPageMatches()
        }
        browserChrome.onFindInPageVisibilityChanged = { [weak self] visible in
            if visible {
                self?.toolbarController.collapseBottomToolbar()
            } else {
                self?.toolbarController.restoreBottomToolbar()
                self?.requestContentKeyboardFocus()
            }
        }
        browserChrome.onKeyboardDismissal = { [weak self] in
            self?.tabManager.selectedTab?.session.dismissSoftwareKeyboard()
        }
    }
    
    func updateBrowserLayout(
        animated: Bool,
        duration: TimeInterval = UX.layoutAnimationDuration
    ) {
        if sidebarCoordinator.hostsSidebar {
            sidebarCoordinator.updateContentLayout(
                animated: animated,
                duration: duration
            )
            return
        }
        
        let previousLayout = browserLayout
        let previousEnvironment = resolvedLayoutEnvironment
        let environment = currentLayoutEnvironment()
        resolvedLayoutEnvironment = environment
        browserLayout = resolveBrowserLayout(in: environment)
        
        // A new layout moves the address bar, which ends its editing. When the layout is new because the
        // window moved to the other display of an iPhone Duo, what was being typed goes with it.
        var addressBarEditing: AddressBar.Editing?
        if browserLayout != previousLayout {
            if let previousEnvironment,
               environment.isDisplayChange(from: previousEnvironment) {
                addressBarEditing = browserChrome.addressBarEditing
            }
            if let readerSettings = presentedViewController as? ReaderSettingsViewController {
                readerSettings.dismiss(animated: false)
            }
            if addressBarEditing == nil {
                dismissAddressBarEditingAndOverlays()
            } else {
                searchOverlayCoordinator.withoutDismissalAnimation(dismissAddressBarEditingAndOverlays)
            }
        }
        applyBrowserLayout(animated: animated)
        homepageOverlayCoordinator.updatePresentation(animated: false)
        searchOverlayCoordinator.updatePresentedLayout()
        
        let layoutBlock = {
            self.view.layoutIfNeeded()
            self.tabOverview.collection.applyPresentationTransforms()
        }
        
        animated
        ? UIView.animate(withDuration: duration, animations: layoutBlock)
        : layoutBlock()
        
        if let addressBarEditing {
            browserChrome.resumeAddressBarEditing(addressBarEditing)
        }
        
        if environment.isRegular {
            requestSidebarHost()
        }
    }
    
    func dismissAddressBarEditingAndOverlays() {
        homepageOverlayCoordinator.resetPresentationSession()
        searchOverlayCoordinator.resetPresentationSession()
        browserChrome.resetAddressBarEditing()
        overlayCoordinator.discardAll(animated: false)
        applyBrowserLayout(animated: false)
    }
    
    func dismissAddressBarEditingAndChromeOverlay() {
        homepageOverlayCoordinator.resetPresentationSession()
        searchOverlayCoordinator.resetPresentationSession()
        browserChrome.resetAddressBarEditing()
        overlayCoordinator.dismiss(.homepage, on: .detached, animated: false)
        overlayCoordinator.dismiss(.search, on: .detached, animated: false)
        applyBrowserLayout(animated: false)
        requestContentKeyboardFocus()
    }
    
    func updateBrowserLayoutIfNeeded(
        animated: Bool,
        duration: TimeInterval = UX.layoutAnimationDuration
    ) {
        guard browserLayout != resolveBrowserLayout(in: currentLayoutEnvironment()) else {
            return
        }
        
        updateBrowserLayout(animated: animated, duration: duration)
    }
    
    func applyBrowserLayout(animated: Bool = false) {
        if isShowingFullscreenMedia {
            applyFullscreenLayout()
        } else {
            switch browserLayout.chromeMode {
            case .phone:
                applyPhoneLayout()
            case .compact:
                applyCompactLayout()
            case .pad:
                applyPadLayout(animated: animated)
            }
        }
        
        applyTabOverviewLayout()
        applyBrowserChromeLayout(animated: animated)
        updateNavigationButtons()
        setNeedsStatusBarAppearanceUpdate()
    }
    
    private func applyFullscreenLayout() {
        contentView.applyLayout(
            ContentView.LayoutState(mode: .fullscreen),
            topAnchor: view.topAnchor,
            bottomAnchor: view.bottomAnchor
        )
        tabBar.setVisibility(.hidden, animated: false)
    }
    
    private func applyPhoneLayout() {
        let isSearchFocused = searchOverlayCoordinator.isFocused && !tabOverview.isPresented
        contentView.applyLayout(
            ContentView.LayoutState(mode: isSearchFocused ? .searchFocused : .standard),
            topAnchor: view.safeAreaLayoutGuide.topAnchor,
            bottomAnchor: isSearchFocused
            ? view.safeAreaLayoutGuide.bottomAnchor
            : browserChrome.bottomToolbarTopAnchor
        )
        tabBar.setVisibility(.hidden, animated: false)
    }
    
    private func applyCompactLayout() {
        contentView.applyLayout(
            ContentView.LayoutState(mode: .standard),
            topAnchor: browserChrome.topToolbarBottomAnchor,
            bottomAnchor: browserChrome.bottomToolbarTopAnchor
        )
        tabBar.setVisibility(.hidden, animated: false)
    }
    
    private func applyPadLayout(animated: Bool) {
        contentView.applyLayout(
            ContentView.LayoutState(mode: .standard),
            topAnchor: browserChrome.tabBarBottomAnchor,
            bottomAnchor: view.bottomAnchor
        )
        tabBar.keepsTabsInsideSafeArea = browserLayout.family == .regular
        tabBar.setVisibility(targetTabBarVisibility, animated: animated)
    }
    
    private var visibleTabCount: Int {
        let tabs = tabManager.selectedTabMode == .private
        ? tabManager.privateTabs
        : tabManager.regularTabs
        return tabs.count
    }
    
    var targetTabBarVisibility: TabBar.Visibility {
        guard browserLayout.chromeMode == .pad else {
            return .hidden
        }
        
        let showsTabBar = browserLayout.family == .regular
        ? visibleTabCount > 1
        : visibleTabCount > 1 && Prefs.AppearanceSettings.showsLandscapeTabBar
        guard showsTabBar else {
            return .hidden
        }
        return tabOverview.isPresented ? .layoutReserved : .visible
    }
    
    private func applyTabOverviewLayout() {
        tabOverview.applyLayout(
            toolbarPosition: browserLayout.tabOverviewToolbarPosition,
            animated: false
        )
    }
    
    private func applyBrowserChromeLayout(animated: Bool) {
        let searchState = isShowingFullscreenMedia
        ? BrowserChrome.SearchState.inactive
        : (overlayCoordinator.chromeStateForAddressBarScrollDismissal(layout: browserLayout) ?? searchOverlayCoordinator.chromeState)
        browserChrome.apply(state: BrowserChrome.State(
            position: browserLayout.chromePosition,
            mode: browserLayout.chromeMode,
            presentation: isShowingFullscreenMedia
            ? .fullscreenMedia
            : (tabOverview.isPresented ? .tabOverview : .browsing),
            search: searchState,
            topInset: browserTopInset(),
            family: browserLayout.family,
            orientation: browserLayout.orientation,
            isTwoThirdSplitScreenOrSmaller: isSidebarOverlayLayout,
            sidebarButtonVisible: sidebarCoordinator.showChromeSidebarButton,
            animatesChromeStateChanges: animated
        ))
    }
    
    private func resolveBrowserLayout(in environment: BrowserLayout.Environment) -> BrowserLayout {
        return BrowserLayout.resolve(
            in: environment,
            addressBarPosition: Prefs.AppearanceSettings.addressBarPosition
        )
    }
    
    /// What the layout is chosen from: the window's size classes and bounds.
    ///
    /// The size classes are read from the window because the sidebar's split view overrides them for its children.
    private func currentLayoutEnvironment() -> BrowserLayout.Environment {
        let traits = view.window?.traitCollection ?? traitCollection
        return BrowserLayout.Environment(
            horizontalSizeClass: traits.horizontalSizeClass,
            verticalSizeClass: traits.verticalSizeClass,
            windowSize: browserWindowSize(),
            hasSidebar: splitViewController is SidebarViewController,
            tabletWindow: BrowserLayout.usesTabletWindowRules ? currentTabletWindow() : nil
        )
    }
    
    private func browserWindowSize() -> CGSize {
        if let rootView = view.window?.rootViewController?.view,
           rootView.bounds.width > 0 {
            return rootView.bounds.size
        }
        
        return view.window?.bounds.size ?? view.bounds.size
    }
    
    // MARK: - iPad Window Rules
    
    private func currentTabletWindow() -> BrowserLayout.TabletWindow {
        return BrowserLayout.TabletWindow(
            orientation: currentDisplayOrientation(),
            isOneThirdSplitScreenOrSmaller: isOneThirdOfDisplayOrSmaller,
            isHalfSplitScreenOrSmaller: isHalfOfDisplayOrSmaller,
            isTwoThirdSplitScreenOrSmaller: isTwoThirdsOfDisplayOrSmaller
        )
    }
    
    private func currentDisplayOrientation() -> BrowserLayout.ViewportOrientation {
        if let interfaceOrientation = view.window?.windowScene?.interfaceOrientation,
           interfaceOrientation != .unknown {
            return interfaceOrientation.isLandscape ? .landscape : .portrait
        }
        
        return view.bounds.width > view.bounds.height ? .landscape : .portrait
    }
    
    private var isOneThirdOfDisplayOrSmaller: Bool {
        guard let window = view.window else {
            return UIApplication.shared.isOneThirdSplitScreenOrSmaller
        }
        
        return UIApplication.shared.isOneThirdSplitScreenOrSmaller(
            forWindowWidth: browserWindowWidth(fallback: window.bounds.width),
            screen: window.screen
        )
    }
    
    private var isTwoThirdsOfDisplayOrSmaller: Bool {
        guard let window = view.window else {
            return UIApplication.shared.isTwoThirdSplitScreenOrSmaller
        }
        
        return UIApplication.shared.isTwoThirdSplitScreenOrSmaller(
            forWindowWidth: browserWindowWidth(fallback: window.bounds.width),
            screen: window.screen
        )
    }
    
    private var isHalfOfDisplayOrSmaller: Bool {
        guard let window = view.window else {
            return UIApplication.shared.isHalfSplitScreenOrSmaller
        }
        
        return UIApplication.shared.isHalfSplitScreenOrSmaller(
            forWindowWidth: browserWindowWidth(fallback: window.bounds.width),
            screen: window.screen
        )
    }
    
    private func browserWindowWidth(fallback: CGFloat) -> CGFloat {
        guard let rootView = view.window?.rootViewController?.view,
              rootView.bounds.width > 0 else {
            return fallback
        }
        
        return rootView.bounds.width
    }
    
    // MARK: - Window Width
    
    /// Too narrow for the regular interface, so the sidebar's split view collapses.
    var isCompactPadLayout: Bool {
        guard BrowserLayout.usesTabletWindowRules else {
            return !currentLayoutEnvironment().isRegular
        }
        
        return isOneThirdOfDisplayOrSmaller
    }
    
    var isSidebarOverlayLayout: Bool {
        return currentLayoutEnvironment().isTwoThirdSplitScreenOrSmaller
    }
    
    var isHalfSplitScreenOrSmaller: Bool {
        return currentLayoutEnvironment().isHalfSplitScreenOrSmaller
    }
    
    private func invalidateNavigationThumbnailsIfNeeded() {
        let didResizeWebContent = contentView.updateWebContentSize()
        guard didResizeWebContent else {
            return
        }
        
        tabManager.invalidateNavigationThumbnails()
        updateNavigationButtons()
    }
    
    private func browserTopInset() -> CGFloat {
        return sidebarCoordinator.topInset(fallback: UX.fallbackTopInset)
    }
    
    // MARK: - Sidebar
    
    private func performContentLifecycle(_ action: () -> Void) {
        guard !sidebarCoordinator.hostsSidebar else {
            return
        }
        
        action()
    }
    
    /// Watches for a hinge, which tells an iPhone Duo from other iPhones before it is opened.
    private func observeHinge() {
        guard sidebarRole == .standalone,
              #available(iOS 27.1, *) else {
            return
        }
        
        let interaction = UIHingeInteraction { [weak self] _, update in
            guard update.hinge != nil else {
                return
            }
            self?.requestSidebarHost()
        }
        view.addInteraction(interaction)
        hingeInteraction = interaction
    }
    
    private func requestSidebarHost() {
        guard sidebarRole == .standalone else {
            return
        }
        
        needsSidebarHost = true
        scheduleSidebarHostAdoption()
    }
    
    /// Tries the move on the next turn of the run loop, never in the middle of a layout pass. Called again
    /// whenever what held it back, such as an open sheet, may have gone.
    private func scheduleSidebarHostAdoption() {
        guard sidebarRole == .standalone,
              needsSidebarHost,
              !isSidebarHostAdoptionScheduled else {
            return
        }
        
        isSidebarHostAdoptionScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.isSidebarHostAdoptionScheduled = false
            self?.adoptSidebarHostIfPossible()
        }
    }
    
    /// Moves this browser into a sidebar container once the system shows it can reach a window with room for one.
    ///
    /// iPad builds the container at launch. An iPhone Duo starts on its cover display reporting what every
    /// iPhone reports, so there the container waits for a hinge, or for a window that is regular in both
    /// dimensions. The browser is not rebuilt: its views, tabs and sessions go into the container as they are,
    /// and from then on opening and closing the phone only resizes them.
    private func adoptSidebarHostIfPossible() {
        guard sidebarRole == .standalone,
              needsSidebarHost,
              isViewLoaded,
              let window = view.window,
              window.rootViewController === self,
              presentedViewController == nil,
              !isShowingFullscreenMedia,
              lockedOrientations == nil,
              pendingOrientationRequest == nil else {
            return
        }
        
        let addressBarEditing = browserChrome.addressBarEditing
        let restoresContentFocus = tabManager.selectedTab?.session.engineView?.isFirstResponder == true
        let isActive = window.windowScene?.activationState == .foregroundActive
        
        if let hingeInteraction {
            view.removeInteraction(hingeInteraction)
            self.hingeInteraction = nil
        }
        stopScreenOrientationHandling()
        sidebarRole = .content
        
        let host = BrowserViewController(adopting: self)
        window.rootViewController = host
        host.view.layoutIfNeeded()
        if isActive {
            host.startScreenOrientationHandling()
        }
        
        toolbarController.unlock(for: .viewPresentation)
        shouldRestoreContentFocus = false
        updateBrowserLayout(animated: false)
        if let addressBarEditing {
            browserChrome.resumeAddressBarEditing(addressBarEditing)
        } else if restoresContentFocus {
            requestContentKeyboardFocus()
        }
    }
    
    // MARK: - Notifications
    
    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(setNeedsStatusBarAppearanceUpdate),
            name: .homepageSettingsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionSystemUIDidDismiss(_:)),
            name: .selectionSystemUIDidDismiss,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addressBarPositionDidChange),
            name: .addressBarPositionDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(landscapeTabBarDidChange),
            name: .landscapeTabBarDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceGestureSettingsDidChange),
            name: .appearanceGestureSettingsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyUpdateMenuButtonBadge),
            name: .appUpdateAvailable,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(newTabDisplayOptionDidChange),
            name: .newTabDisplayOptionDidChange,
            object: nil
        )
    }
    
    @objc private func newTabDisplayOptionDidChange() {
        homepageOverlayCoordinator.updatePresentation(animated: true)
        captureThumbnail(forTabAt: tabManager.selectedTabIndex, mode: tabManager.selectedTabMode)
    }
    
    @objc func addressBarPositionDidChange() {
        updateBrowserLayout(animated: true)
    }
    
    @objc func landscapeTabBarDidChange() {
        updateBrowserLayout(animated: true)
    }
    
    @objc private func appearanceGestureSettingsDidChange() {
        updateBrowserLayout(animated: false)
    }
    
    @objc func applyUpdateMenuButtonBadge() {
        browserChrome.setMenuButtonIndicatesUpdate(BrowserUpdates.shared.hasUpdate)
    }
    
    // MARK: - Keyboard
    
    func requestHomepageAddressBarFocus() {
        let expectedSession = tabManager.selectedTab?.session
        
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let tab = tabManager.selectedTab,
                  tab.session === expectedSession else {
                return
            }
            
            guard homepageOverlayCoordinator.isHomepageTab(tab),
                  tab.session.isInHardwareKeyboardMode() else {
                return
            }
            
            guard !tabOverview.isPresented,
                  !tabOverview.isTransitionRunning else {
                return
            }
            
            guard !browserChrome.isAddressBarEditing,
                  presentedControllerInHierarchy == nil else {
                return
            }
            
            browserChrome.addressBar.focusForHardwareKeyboard()
        }
    }
    
    func requestContentKeyboardFocus(for expectedSession: GeckoSession? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let presentedController = presentedControllerInHierarchy {
                guard let transitionCoordinator = presentedController.transitionCoordinator else {
                    return
                }
                transitionCoordinator.animate(alongsideTransition: nil) { [weak self] _ in
                    self?.requestContentKeyboardFocus(for: expectedSession)
                }
                return
            }
            restoreContentKeyboardFocus(for: expectedSession)
        }
    }
    
    private func restoreContentKeyboardFocus(for expectedSession: GeckoSession? = nil) {
        guard !browserChrome.isAddressBarEditing,
              let selectedSession = tabManager.selectedTab?.session else {
            return
        }
        if let expectedSession, expectedSession !== selectedSession {
            return
        }
        guard contentView.isDisplaying(session: selectedSession),
              let engineView = selectedSession.engineView,
              let window = engineView.window,
              window.isKeyWindow,
              window.windowScene?.activationState == .foregroundActive else {
            return
        }
        selectedSession.focusForHardwareKeyboard()
    }
    
    private var presentedControllerInHierarchy: UIViewController? {
        var controller: UIViewController? = self
        while let currentController = controller {
            if let presentedController = currentController.presentedViewController {
                return presentedController
            }
            controller = currentController.parent
        }
        return nil
    }
    
    @objc private func selectionSystemUIDidDismiss(_ notification: Notification) {
        guard let source = notification.object as? UIView,
              let session = tabManager.selectedTab?.session,
              let engineView = session.engineView,
              source.isDescendant(of: engineView) else {
            return
        }
        
        requestContentKeyboardFocus(for: session)
    }
    
    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
        
        let isHardwareKeyboardMode = tabManager.selectedTab?.session.isInHardwareKeyboardMode() == true
        
        if !isHardwareKeyboardMode {
            browserChrome.addressBar.restoreEditingLayout()
        }
        
        let keyboardFrame = view.convert(frameValue.cgRectValue, from: nil)
        let keyboardOverlap = max(0, view.bounds.maxY - keyboardFrame.minY)
        let keyboardInset = max(0, keyboardOverlap - view.safeAreaInsets.bottom)
        let spansWindow = view.bounds.width > 0
        && keyboardFrame.width >= view.bounds.width * UX.floatingKeyboardWidthRatio
        let sitsFlushWithBottom = keyboardFrame.maxY >= view.bounds.maxY - 8
        let isFloatingKeyboard = browserLayout.family == .regular
        && !(spansWindow && sitsFlushWithBottom)
        let shouldAdjustForKeyboard = keyboardInset > 0
        && !isFloatingKeyboard
        && !tabOverview.isPresented
        && !isHardwareKeyboardMode
        
        let presentedController = presentedControllerInHierarchy
        let shouldRelocateInput = shouldAdjustForKeyboard
        && !searchOverlayCoordinator.isFocused
        && !browserChrome.isShowingFindInPage
        && (presentedController == nil || presentedController?.isBeingDismissed == true)
        
        if shouldRelocateInput {
            toolbarController.lock(for: .inputRelocation)
        } else {
            toolbarController.unlock(for: .inputRelocation)
        }
        
        let animation = keyboardAnimation(from: notification)
        if shouldRelocateInput && browserLayout.family == .compact {
            browserChrome.showActionBar(.keyboardDismissal, animated: false)
        } else if browserChrome.isShowingKeyboardDismissal {
            browserChrome.dismissActionBar(animated: false)
        }
        let shouldDockActionBar = shouldAdjustForKeyboard
        && (browserChrome.isShowingFindInPage || browserChrome.isShowingKeyboardDismissal)
        let shouldDockAddressBar = shouldAdjustForKeyboard
        && browserLayout.chromeMode == .phone && searchOverlayCoordinator.isFocused
        browserChrome.dockActionBar(offset: shouldDockActionBar ? -keyboardOverlap : 0)
        browserChrome.dockAddressBar(offset: shouldDockAddressBar ? -keyboardInset : 0)
        animateLayout(animation)
        
        contentView.updateFocusedInputRelocation(
            above: shouldRelocateInput ? keyboardFrame : nil,
            bottomInset: browserChrome.isShowingKeyboardDismissal ? ActionBarStyle.compact.height : 0,
            animationDuration: animation.duration,
            animationOptions: animation.curve
        )
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        toolbarController.unlock(for: .inputRelocation)
        let animation = keyboardAnimation(from: notification)
        if browserChrome.isShowingKeyboardDismissal {
            browserChrome.dismissActionBar(animated: false)
        }
        contentView.resetFocusedInputRelocation(
            animationDuration: animation.duration,
            animationOptions: animation.curve
        )
        browserChrome.dockActionBar(offset: 0)
        browserChrome.dockAddressBar(offset: 0)
        animateLayout(animation)
    }
    
    private func keyboardAnimation(from notification: Notification) -> KeyboardAnimation {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        ?? UX.keyboardAnimationDuration
        let rawCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        ?? UX.keyboardAnimationCurve
        return KeyboardAnimation(
            duration: duration,
            curve: UIView.AnimationOptions(rawValue: rawCurve << 16)
        )
    }
    
    private func animateLayout(_ animation: KeyboardAnimation) {
        UIView.animate(withDuration: animation.duration, delay: 0, options: [animation.curve]) {
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Browser UI Updates
    
    func syncBrowserNavigationChrome(animated: Bool) {
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationItem.leftItemsSupplementBackButton = false
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItems = []
        navigationItem.leftBarButtonItem = nil
    }
    
    func updateNavigationButtons() {
        guard let tab = tabManager.selectedTab else {
            contentView.setHistoryNavigation(
                canGoBack: false,
                canGoForward: false,
                backPreviewImage: nil,
                forwardPreviewImage: nil,
                isSwipeEnabled: false
            )
            return
        }
        
        browserChrome.updateNavigation(
            canGoBack: tabManager.canGoBack,
            canGoForward: tab.state.navigationState.canGoForward,
            canShare: tabManager.shareableURL(for: tab) != nil
        )
        
        let previewImages = tabManager.navigationPreviewImages(for: tab)
        contentView.setHistoryNavigation(
            canGoBack: tabManager.canGoBack,
            canGoForward: tab.state.navigationState.canGoForward,
            backPreviewImage: tab.state.navigationState.canGoBack ? previewImages.backImage : nil,
            forwardPreviewImage: previewImages.forwardImage,
            isSwipeEnabled: true
        )
    }
    
    func applyFullscreenState(_ fullScreen: Bool, for session: GeckoSession?) {
        if fullScreen {
            fullscreenSession = session
        } else if fullscreenSession === session || session == nil {
            fullscreenSession = nil
        }
        
        guard isShowingFullscreenMedia != fullScreen else {
            return
        }
        
        if fullScreen {
            if tabOverview.isPresented {
                tabOverview.setPresented(false, animated: false)
            }
            searchOverlayCoordinator.setFocused(false, animated: false)
            view.endEditing(true)
        }
        
        sidebarCoordinator.setFullscreen(fullScreen)
        isShowingFullscreenMedia = fullScreen
        updateBrowserLayout(animated: false)
        updateFullscreenOrientation(fullScreen)
        requestContentKeyboardFocus(for: tabManager.selectedTab?.session)
    }
    
    func exitFullscreenIfNeeded() {
        guard isShowingFullscreenMedia,
              let session = fullscreenSession else {
            return
        }
        session.exitFullScreen()
        applyFullscreenState(false, for: session)
    }
    
    // MARK: - Orientation
    
    func lockScreenOrientation(
        to requestedOrientations: UIInterfaceOrientationMask,
        completion: @escaping (GeckoOrientationLockResult) -> Void
    ) {
        guard !requestedOrientations.isEmpty else {
            completion(.notSupported)
            return
        }
        
        rejectPendingOrientationRequest()
        
        if #available(iOS 16.0, *) {
            guard let windowScene = view.window?.windowScene else {
                completion(.notSupported)
                return
            }
            
            lockedOrientations = requestedOrientations
            setNeedsUpdateOfSupportedInterfaceOrientations()
            if let currentOrientationMask = orientationMask(
                for: windowScene.interfaceOrientation
            ), requestedOrientations.contains(currentOrientationMask) {
                completion(.success)
                return
            }
            
            let requestID = UUID()
            pendingOrientationRequest = (requestID, requestedOrientations, completion)
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: requestedOrientations
            )
            windowScene.requestGeometryUpdate(geometryPreferences) { [weak self] error in
                let geometryError = error as NSError
                let lockResult: GeckoOrientationLockResult =
                geometryError.domain == UISceneErrorDomain &&
                geometryError.code == UISceneError.Code.geometryRequestUnsupported.rawValue
                ? .notSupported
                : .rejected
                self?.completePendingOrientationRequest(id: requestID, with: lockResult)
            }
            return
        }
        
        guard let preferredOrientation = preferredInterfaceOrientation(
            allowedBy: requestedOrientations
        ) else {
            completion(.notSupported)
            return
        }
        
        lockedOrientations = requestedOrientations
        forceInterfaceOrientation(preferredOrientation)
        completion(.success)
    }
    
    func unlockScreenOrientation() {
        rejectPendingOrientationRequest()
        lockedOrientations = nil
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        updateFullscreenOrientation(false)
    }
    
    private func updateFullscreenOrientation(_ fullScreen: Bool) {
        guard browserLayout.family == .compact else {
            return
        }
        
        if fullScreen {
            if let interfaceOrientation = view.window?.windowScene?.interfaceOrientation,
               interfaceOrientation != .unknown {
                preFullscreenOrientation = interfaceOrientation
            } else {
                preFullscreenOrientation = .portrait
            }
            return
        }
        
        guard !isShowingFullscreenMedia,
              lockedOrientations == nil,
              let preFullscreenOrientation else {
            return
        }
        self.preFullscreenOrientation = nil
        forceInterfaceOrientation(preFullscreenOrientation)
    }
    
    private func completePendingOrientationRequestIfSatisfied() {
        guard let pendingOrientationRequest,
              let interfaceOrientation = view.window?.windowScene?.interfaceOrientation,
              let currentOrientationMask = orientationMask(for: interfaceOrientation),
              pendingOrientationRequest.orientations.contains(currentOrientationMask) else {
            return
        }
        
        completePendingOrientationRequest(id: pendingOrientationRequest.id, with: .success)
    }
    
    private func completePendingOrientationRequest(
        id: UUID,
        with result: GeckoOrientationLockResult
    ) {
        guard let pendingOrientationRequest,
              pendingOrientationRequest.id == id else {
            return
        }
        
        self.pendingOrientationRequest = nil
        if result != .success {
            lockedOrientations = nil
            if #available(iOS 16.0, *) {
                setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
        pendingOrientationRequest.completion(result)
    }
    
    private func rejectPendingOrientationRequest() {
        guard let pendingOrientationRequest else {
            return
        }
        
        self.pendingOrientationRequest = nil
        pendingOrientationRequest.completion(.rejected)
    }
    
    func startScreenOrientationHandling() {
        guard sidebarRole != .content else {
            return
        }
        
        GeckoRuntime.orientationController.delegate = self
        guard let interfaceOrientation = view.window?.windowScene?.interfaceOrientation else {
            return
        }
        screenOrientationChanged(to: interfaceOrientation)
    }
    
    func stopScreenOrientationHandling() {
        guard let registeredDelegate = GeckoRuntime.orientationController.delegate,
              registeredDelegate === self else {
            return
        }
        
        rejectPendingOrientationRequest()
        GeckoRuntime.orientationController.delegate = nil
    }
    
    func screenOrientationChanged(to interfaceOrientation: UIInterfaceOrientation) {
        guard interfaceOrientation != .unknown else {
            return
        }
        
        sidebarCoordinator.notifyScreenOrientationChanged(to: interfaceOrientation)
        completePendingOrientationRequestIfSatisfied()
    }
    
    private func preferredInterfaceOrientation(
        allowedBy orientations: UIInterfaceOrientationMask
    ) -> UIInterfaceOrientation? {
        if let currentOrientation = view.window?.windowScene?.interfaceOrientation,
           currentOrientation != .unknown,
           let currentOrientationMask = orientationMask(for: currentOrientation),
           orientations.contains(currentOrientationMask) {
            return currentOrientation
        }
        
        if orientations.contains(.portrait) {
            return .portrait
        }
        if orientations.contains(.portraitUpsideDown) {
            return .portraitUpsideDown
        }
        if orientations.contains(.landscapeRight) {
            return .landscapeRight
        }
        if orientations.contains(.landscapeLeft) {
            return .landscapeLeft
        }
        return nil
    }
    
    private func orientationMask(
        for orientation: UIInterfaceOrientation
    ) -> UIInterfaceOrientationMask? {
        switch orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return nil
        }
    }
    
    private func forceInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        let orientationMask: UIInterfaceOrientationMask
        switch orientation {
        case .portrait:
            orientationMask = .portrait
        case .portraitUpsideDown:
            orientationMask = .portraitUpsideDown
        case .landscapeLeft:
            orientationMask = .landscapeLeft
        case .landscapeRight:
            orientationMask = .landscapeRight
        default:
            return
        }
        
        if #available(iOS 16.0, *) {
            guard let windowScene = view.window?.windowScene else {
                return
            }
            
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientationMask)
            windowScene.requestGeometryUpdate(geometryPreferences)
            UIViewController.attemptRotationToDeviceOrientation()
            return
        }
        
        let deviceOrientation: UIDeviceOrientation
        switch orientation {
        case .portrait:
            deviceOrientation = .portrait
        case .portraitUpsideDown:
            deviceOrientation = .portraitUpsideDown
        case .landscapeLeft:
            deviceOrientation = .landscapeRight
        case .landscapeRight:
            deviceOrientation = .landscapeLeft
        default:
            return
        }
        
        UIDevice.current.setValue(deviceOrientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}
