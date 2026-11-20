//
//  SidebarCoordinator.swift
//  Reynard
//
//  Created by Minh Ton on 16/6/26.
//

import UIKit

/// Where a browser view controller stands with the sidebar's container.
enum SidebarRole: Equatable {
    /// Holds the sidebar's split view and, inside it, the browser that does the work.
    case host
    /// The browser inside a host's split view.
    case content
    /// A browser on its own, which moves into a host if its window can ever be regular in both dimensions.
    case standalone
}

protocol SidebarContentController: AnyObject {
    var sidebarContentViewController: UIViewController { get }
    var sidebarContentChrome: BrowserChrome { get }
    var sidebarContentLayout: BrowserLayout { get }
    var sidebarContentIsPrivate: Bool { get }
    var isCompactPadLayout: Bool { get }
    var isSidebarOverlayLayout: Bool { get }
    
    func updateBrowserLayout(animated: Bool, duration: TimeInterval)
    func updateBrowserLayoutIfNeeded(animated: Bool, duration: TimeInterval)
    func openExternalURL(_ url: URL)
    func notifyScreenOrientationChanged(to interfaceOrientation: UIInterfaceOrientation)
    func sidebarDidEndEditing()
}

protocol SidebarCoordinatorHost: AnyObject {
    var sidebarHostViewController: UIViewController { get }
    var sidebarLayoutFamily: BrowserLayout.Family { get }
    var sidebarChromeMode: BrowserChromeMode { get }
    var sidebarSplitViewController: UISplitViewController? { get }
    var sidebarFallbackTopInsetSourceView: UIView { get }
    
    func makeSidebarContentController() -> SidebarContentController
    func sidebarCoordinatorDidChangeVisibility(_ coordinator: SidebarCoordinator, animated: Bool)
}

final class SidebarCoordinator {
    private weak var host: SidebarCoordinatorHost?
    private let canHostSidebar: Bool
    private var sidebar: SidebarViewController?
    private var overridesSidebarSizeClass: Bool?
    private var preFullscreenVisibility: Bool?
    private var preCompactVisibility: Bool?
    
    var statusBarController: UIViewController? {
        return hostsSidebar ? sidebar : nil
    }
    
    var contentBrowser: SidebarContentController? {
        return sidebar?.contentBrowser ?? host as? SidebarContentController
    }
    
    var showChromeSidebarButton: Bool {
        return (host?.sidebarSplitViewController as? SidebarViewController)?.showChromeSidebarButton ?? true
    }
    
    var hostsSidebar: Bool {
        return canHostSidebar
    }
    
    // MARK: - Lifecycle
    
    init(host: SidebarCoordinatorHost, canHostSidebar: Bool) {
        self.host = host
        self.canHostSidebar = canHostSidebar
    }
    
    // MARK: - Installation
    
    @discardableResult
    func installHostIfNeeded() -> Bool {
        guard hostsSidebar else {
            return false
        }
        
        guard sidebar == nil else {
            return true
        }
        
        guard let host else {
            return false
        }
        
        let contentBrowser = host.makeSidebarContentController()
        let sidebar = SidebarViewController(contentController: contentBrowser)
        host.sidebarHostViewController.addChild(sidebar)
        sidebar.view.translatesAutoresizingMaskIntoConstraints = false
        host.sidebarHostViewController.view.addSubview(sidebar.view)
        NSLayoutConstraint.activate([
            sidebar.view.topAnchor.constraint(equalTo: host.sidebarHostViewController.view.topAnchor),
            sidebar.view.leadingAnchor.constraint(equalTo: host.sidebarHostViewController.view.leadingAnchor),
            sidebar.view.trailingAnchor.constraint(equalTo: host.sidebarHostViewController.view.trailingAnchor),
            sidebar.view.bottomAnchor.constraint(equalTo: host.sidebarHostViewController.view.bottomAnchor),
        ])
        sidebar.didMove(toParent: host.sidebarHostViewController)
        self.sidebar = sidebar
        updateSidebarSizeClassOverride()
        return true
    }
    
    // MARK: - Trait Overrides
    
    private func updateSidebarSizeClassOverride() {
        guard let host,
              let sidebar else {
            return
        }
        
        guard BrowserLayout.usesTabletWindowRules else {
            updateSidebarForWindowSizeClass()
            return
        }
        
        let shouldOverrideSidebarSizeClass = !(contentBrowser?.isCompactPadLayout ?? UIApplication.shared.isOneThirdSplitScreenOrSmaller)
        guard overridesSidebarSizeClass != shouldOverrideSidebarSizeClass else {
            return
        }
        
        overridesSidebarSizeClass = shouldOverrideSidebarSizeClass
        let sidebarSizeClassOverride = shouldOverrideSidebarSizeClass
        ? UITraitCollection(horizontalSizeClass: .regular)
        : nil
        host.sidebarHostViewController.setOverrideTraitCollection(sidebarSizeClassOverride, forChild: sidebar)
    }
    
    /// Away from iPad the split view stays expanded whatever the window's width, and a compact window simply
    /// has no sidebar to show. Collapsing would move the browser into another navigation stack each time an
    /// iPhone Duo is closed, and take the keyboard and what is being typed away with it. The browser itself is
    /// told the window's real width class.
    private func updateSidebarForWindowSizeClass() {
        guard let host,
              let sidebar else {
            return
        }
        
        let hostViewController = host.sidebarHostViewController
        if overridesSidebarSizeClass != true {
            overridesSidebarSizeClass = true
            hostViewController.setOverrideTraitCollection(
                UITraitCollection(horizontalSizeClass: .regular),
                forChild: sidebar
            )
        }
        
        let traits = hostViewController.traitCollection
        sidebar.setContentHorizontalSizeClass(traits.horizontalSizeClass)
        
        let isRegular = traits.horizontalSizeClass == .regular && traits.verticalSizeClass != .compact
        if !isRegular {
            if sidebar.isSidebarVisible {
                preCompactVisibility = true
                sidebar.setVisible(false)
            }
        } else if preCompactVisibility == true {
            preCompactVisibility = nil
            sidebar.setVisible(true)
        }
    }
    
    // MARK: - Visibility
    
    func toggle(animated: Bool) {
        guard host?.sidebarLayoutFamily == .regular else {
            return
        }
        
        (host?.sidebarSplitViewController as? SidebarViewController)?.toggleVisibility()
        host?.sidebarCoordinatorDidChangeVisibility(self, animated: animated)
    }
    
    func refreshVisibility() {
        sidebar?.refreshVisibility()
    }
    
    func setFullscreen(_ fullscreen: Bool) {
        guard let splitViewController = host?.sidebarSplitViewController as? SidebarViewController else {
            return
        }
        
        if fullscreen {
            preFullscreenVisibility = splitViewController.isSidebarVisible
            splitViewController.setVisible(false)
        } else if let preFullscreenVisibility {
            splitViewController.setVisible(preFullscreenVisibility)
            self.preFullscreenVisibility = nil
        }
    }
    
    @discardableResult
    func refreshHostVisibility() -> Bool {
        guard hostsSidebar else {
            return false
        }
        
        updateSidebarSizeClassOverride()
        refreshVisibility()
        return true
    }
    
    // MARK: - Sections
    
    func showSection(_ section: LibrarySection, startsEditingBookmarks: Bool = false) {
        (host?.sidebarSplitViewController as? SidebarViewController)?.showSection(
            section,
            startsEditingBookmarks: startsEditingBookmarks
        )
    }
    
    func topInset(fallback: CGFloat) -> CGFloat {
        guard let host else {
            return fallback
        }
        
        guard host.sidebarLayoutFamily == .regular,
              host.sidebarSplitViewController is SidebarViewController,
              BrowserLayout.usesTabletWindowRules else {
            return host.sidebarFallbackTopInsetSourceView.safeAreaInsets.top
        }
        
        if let statusBarHeight = host.sidebarHostViewController.view.window?.windowScene?.statusBarManager?.statusBarFrame.height,
           statusBarHeight > 0 {
            return statusBarHeight
        }
        
        return fallback
    }
    
    // MARK: - Content
    
    func loadContentIfNeeded() {
        contentBrowser?.sidebarContentViewController.loadViewIfNeeded()
    }
    
    func updateContentLayout(animated: Bool, duration: TimeInterval) {
        updateSidebarSizeClassOverride()
        contentBrowser?.updateBrowserLayout(animated: animated, duration: duration)
    }
    
    func openExternalURL(_ url: URL) {
        contentBrowser?.openExternalURL(url)
    }
    
    func notifyScreenOrientationChanged(to interfaceOrientation: UIInterfaceOrientation) {
        contentBrowser?.notifyScreenOrientationChanged(to: interfaceOrientation)
    }
}
