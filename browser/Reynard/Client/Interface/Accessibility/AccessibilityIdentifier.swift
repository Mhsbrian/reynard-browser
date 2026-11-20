//
//  AccessibilityIdentifier.swift
//  Reynard
//

import Foundation

/// What UI tests find Reynard's controls by. An identifier is never localized and never read aloud, so a
/// test written against these works in every language and at every text size.
enum AccessibilityIdentifier {
    enum Toolbar {
        static let back = "toolbar.back"
        static let forward = "toolbar.forward"
        static let share = "toolbar.share"
        static let library = "toolbar.library"
        static let tabOverview = "toolbar.tabs"
        static let downloads = "toolbar.downloads"
        static let newTab = "toolbar.newTab"
        static let sidebar = "toolbar.sidebar"
    }

    enum AddressBar {
        static let bar = "addressBar"
        static let textField = "addressBar.textField"
        static let pageMenu = "addressBar.pageMenu"
        static let reload = "addressBar.reload"
        static let audio = "addressBar.audio"
        static let cancel = "addressBar.cancel"
    }

    enum TabBar {
        static let bar = "tabBar"
        static let tab = "tabBar.tab"
        static let closeTab = "tabBar.closeTab"
    }

    enum TabOverview {
        static let card = "tabOverview.tab"
        static let closeTab = "tabOverview.closeTab"
        static let closeTabs = "tabOverview.closeTabs"
        static let newTab = "tabOverview.newTab"
        static let done = "tabOverview.done"
        static let mode = "tabOverview.mode"
    }

    enum FindInPage {
        static let bar = "findInPage"
        static let textField = "findInPage.textField"
        static let previous = "findInPage.previous"
        static let next = "findInPage.next"
        static let done = "findInPage.done"
        static let count = "findInPage.count"
    }

    enum PageZoom {
        static let bar = "pageZoom"
        static let zoomOut = "pageZoom.zoomOut"
        static let zoomIn = "pageZoom.zoomIn"
        static let reset = "pageZoom.reset"
    }

    enum Homepage {
        static let view = "homepage"
        static let welcome = "homepage.welcome"
        static let welcomeDismiss = "homepage.welcome.dismiss"
        static let favorite = "homepage.favorite"
        static let frequentlyVisited = "homepage.frequentlyVisited"
        static let recentlyClosed = "homepage.recentlyClosed"
    }

    enum Reader {
        static let theme = "reader.theme"
    }
}
