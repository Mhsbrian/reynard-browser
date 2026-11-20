//
//  BrowserLayout.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

struct BrowserLayout: Equatable {
    enum ViewportOrientation: Equatable {
        case portrait
        case landscape
    }

    /// Which of Reynard's two interfaces a layout belongs to.
    ///
    /// The window chooses it, not the kind of device: see `resolve(in:addressBarPosition:)`.
    enum Family: Equatable {
        /// One column: the library opens as a sheet and the tab strip is a setting.
        /// An iPhone, and the cover display of an iPhone Duo.
        case compact
        /// Room for one more level of hierarchy: the sidebar, the library inside it, and the tab strip.
        /// An iPad, and the inner display of an iPhone Duo.
        case regular
    }

    let family: Family
    let orientation: ViewportOrientation
    let chromeMode: BrowserChromeMode
    let chromePosition: BrowserChromePosition
    let tabOverviewToolbarPosition: TabOverview.ToolbarPosition
    let overlayHost: OverlayCoordinator.Host

    static func initial(family: Family) -> BrowserLayout {
        BrowserLayout(
            family: family,
            orientation: .portrait,
            chromeMode: family == .regular ? .pad : .phone,
            chromePosition: .bottom,
            tabOverviewToolbarPosition: family == .regular ? .top : .bottom,
            overlayHost: family == .regular ? .detached : .embedded
        )
    }
}

// MARK: - Resolution

extension BrowserLayout {
    /// What a layout is chosen from: the window's size classes and its own bounds.
    struct Environment: Equatable {
        /// The size classes of the window. Not those of a view inside the sidebar's split view, which are overridden.
        let horizontalSizeClass: UIUserInterfaceSizeClass
        let verticalSizeClass: UIUserInterfaceSizeClass
        /// The bounds of the window's root view.
        let windowSize: CGSize
        /// Whether the browser sits beside a sidebar it can show. The regular interface needs one for its library.
        let hasSidebar: Bool
        /// Set on iPad only: see `TabletWindow`.
        let tabletWindow: TabletWindow?
    }

    /// How an iPad window relates to its display.
    ///
    /// iPad keeps the rules it had before layouts were chosen from size classes, so that Split View, Slide Over
    /// and resizable windows look as they always did. Those rules ask how much of the display a window takes
    /// and which way the display is turned, which size classes do not say. No other device uses them.
    struct TabletWindow: Equatable {
        let orientation: ViewportOrientation
        let isOneThirdSplitScreenOrSmaller: Bool
        let isHalfSplitScreenOrSmaller: Bool
        let isTwoThirdSplitScreenOrSmaller: Bool
    }

    /// True on iPad, where `TabletWindow` applies and the sidebar's container is built at launch.
    ///
    /// This is the one question the browser's layout asks about the device rather than the window.
    static var usesTabletWindowRules: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }

    static func resolve(
        in environment: Environment,
        addressBarPosition: BrowserChromePosition
    ) -> BrowserLayout {
        if let tabletWindow = environment.tabletWindow {
            return tabletWindow.isOneThirdSplitScreenOrSmaller
            ? .regularNarrow(orientation: tabletWindow.orientation)
            : .regular(
                orientation: tabletWindow.orientation,
                isHalfSplitScreenOrSmaller: tabletWindow.isHalfSplitScreenOrSmaller
            )
        }

        // A short window: an iPhone on its side.
        guard environment.verticalSizeClass != .compact else {
            return .compactWide(isHalfSplitScreenOrSmaller: environment.isHalfSplitScreenOrSmaller)
        }

        // Compact width with regular height: an iPhone held upright, or the cover display of an iPhone Duo.
        guard environment.horizontalSizeClass == .regular else {
            return addressBarPosition == .top ? .compactTop : .compactBottom
        }

        // Regular in both dimensions, which among iPhones only the inner display of an iPhone Duo is.
        // Until the sidebar's container is in place the window gets the widest compact layout instead,
        // because the regular interface opens its library in the sidebar.
        guard environment.hasSidebar else {
            return .compactWide(isHalfSplitScreenOrSmaller: environment.isHalfSplitScreenOrSmaller)
        }

        return .regular(
            orientation: environment.viewportOrientation,
            isHalfSplitScreenOrSmaller: environment.isHalfSplitScreenOrSmaller
        )
    }
}

extension BrowserLayout.Environment {
    private enum UX {
        static let halfSplitScreenWidthRatio: CGFloat = 3.0 / 5.0
        static let twoThirdSplitScreenWidthRatio: CGFloat = 3.0 / 4.0
        static let widthRatioTolerance: CGFloat = 0.5
    }

    /// Whether the window is regular in both dimensions, which is what the regular interface asks for.
    var isRegular: Bool {
        return horizontalSizeClass == .regular && verticalSizeClass != .compact
    }

    /// Whether getting here from `previous` was a move between the displays of an iPhone Duo: the width class
    /// changed and the height stayed regular. Turning an iPhone changes the height class instead, and an iPad
    /// window follows its own rules.
    func isDisplayChange(from previous: BrowserLayout.Environment) -> Bool {
        return tabletWindow == nil
        && previous.tabletWindow == nil
        && verticalSizeClass != .compact
        && previous.verticalSizeClass != .compact
        && horizontalSizeClass != previous.horizontalSizeClass
    }
    
    var viewportOrientation: BrowserLayout.ViewportOrientation {
        if let tabletWindow {
            return tabletWindow.orientation
        }
        return windowSize.width > windowSize.height ? .landscape : .portrait
    }

    /// Too narrow to give the tab overview's toolbar the top edge.
    var isHalfSplitScreenOrSmaller: Bool {
        if let tabletWindow {
            return tabletWindow.isHalfSplitScreenOrSmaller
        }
        return isNoWider(than: UX.halfSplitScreenWidthRatio)
    }

    /// Too narrow to put the sidebar beside the page, so it goes over it.
    var isTwoThirdSplitScreenOrSmaller: Bool {
        if let tabletWindow {
            return tabletWindow.isTwoThirdSplitScreenOrSmaller
        }
        return isNoWider(than: UX.twoThirdSplitScreenWidthRatio)
    }

    // Away from iPad a window is measured against its own longer side. For a window that fills its display
    // this is the same number the iPad rules get from the display.
    private func isNoWider(than ratio: CGFloat) -> Bool {
        let longerSide = max(windowSize.width, windowSize.height)
        return windowSize.width <= ratio * longerSide + UX.widthRatioTolerance
    }
}

// MARK: - Layouts

private extension BrowserLayout {
    /// Address bar and toolbar together at the bottom.
    static let compactBottom = BrowserLayout(
        family: .compact,
        orientation: .portrait,
        chromeMode: .phone,
        chromePosition: .bottom,
        tabOverviewToolbarPosition: .bottom,
        overlayHost: .embedded
    )

    /// Address bar at the top, toolbar at the bottom.
    static let compactTop = BrowserLayout(
        family: .compact,
        orientation: .portrait,
        chromeMode: .compact,
        chromePosition: .top,
        tabOverviewToolbarPosition: .bottom,
        overlayHost: .embedded
    )

    /// One bar along the top, in a window with no sidebar.
    static func compactWide(isHalfSplitScreenOrSmaller: Bool) -> BrowserLayout {
        return BrowserLayout(
            family: .compact,
            orientation: .landscape,
            chromeMode: .pad,
            chromePosition: .bottom,
            tabOverviewToolbarPosition: isHalfSplitScreenOrSmaller ? .bottom : .top,
            overlayHost: .detached
        )
    }

    /// The regular interface in a window too narrow for its one bar: address bar at the top, toolbar at the bottom.
    static func regularNarrow(orientation: ViewportOrientation) -> BrowserLayout {
        return BrowserLayout(
            family: .regular,
            orientation: orientation,
            chromeMode: .compact,
            chromePosition: .bottom,
            tabOverviewToolbarPosition: .bottom,
            overlayHost: .embedded
        )
    }

    /// One bar along the top, with the sidebar and the tab strip.
    static func regular(
        orientation: ViewportOrientation,
        isHalfSplitScreenOrSmaller: Bool
    ) -> BrowserLayout {
        return BrowserLayout(
            family: .regular,
            orientation: orientation,
            chromeMode: .pad,
            chromePosition: .bottom,
            tabOverviewToolbarPosition: isHalfSplitScreenOrSmaller ? .bottom : .top,
            overlayHost: .detached
        )
    }
}
