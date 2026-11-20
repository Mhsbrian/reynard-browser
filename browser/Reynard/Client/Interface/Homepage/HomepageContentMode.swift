//
//  HomepageContentMode.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

enum HomepageContentMode: Equatable {
    case embeddedNarrow
    case embeddedWide
    case embeddedExpanded
    case detachedNarrow
    case detachedWide
    
    var favoriteColumnCount: Int {
        switch self {
        case .embeddedNarrow, .detachedNarrow:
            return 4
        case .embeddedWide, .detachedWide:
            return 6
        case .embeddedExpanded:
            return 8
        }
    }
    
    var recentlyCloseTabsColumnCount: Int {
        switch self {
        case .embeddedNarrow, .detachedNarrow:
            return 1
        case .embeddedWide, .detachedWide:
            return 2
        case .embeddedExpanded:
            return 3
        }
    }
    
    var isDetached: Bool {
        switch self {
        case .detachedNarrow, .detachedWide:
            return true
        case .embeddedNarrow, .embeddedWide, .embeddedExpanded:
            return false
        }
    }
    
    static func embedded(
        layout: BrowserLayout,
        gridWidth: HomepageGridWidth = .eightColumn
    ) -> HomepageContentMode {
        if layout.family == .regular {
            switch gridWidth {
            case .fourColumn:
                return .embeddedNarrow
            case .sixColumn:
                return .embeddedWide
            case .eightColumn:
                if layout.chromeMode == .compact {
                    return .embeddedNarrow
                }
                return .embeddedExpanded
            }
        }
        
        switch layout.orientation {
        case .portrait:
            return .embeddedNarrow
        case .landscape:
            return .embeddedWide
        }
    }
    
    static func detached(layout: BrowserLayout) -> HomepageContentMode {
        switch layout.family {
        case .compact:
            return .detachedNarrow
        case .regular:
            return .detachedWide
        }
    }
}

enum HomepageGridWidth: Equatable {
    case fourColumn
    case sixColumn
    case eightColumn
    
    private enum UX {
        static let sixColumnMinimumWidth: CGFloat = 600
        static let eightColumnMinimumWidth: CGFloat = 850
    }
    
    /// The grid for a page area of this width.
    ///
    /// iPad chooses the grid from the window's share of its display. Elsewhere the page area's own width
    /// decides, so that showing the sidebar beside the page gives the grid fewer columns.
    static func fitting(width: CGFloat) -> HomepageGridWidth {
        if width < UX.sixColumnMinimumWidth {
            return .fourColumn
        }
        if width < UX.eightColumnMinimumWidth {
            return .sixColumn
        }
        return .eightColumn
    }
}
