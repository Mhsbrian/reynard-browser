//
//  HomepageSection.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

import UIKit

enum HomepageRecommendation: CaseIterable, Hashable {
    case welcome
    case performance
    case updateAvailable
    case donation
}

enum HomepageSection: CaseIterable, Hashable {
    case recommendation(HomepageRecommendation)
    case privateBrowsing
    case favorites
    case frequentlyVisited
    case recentlyClosedTabs
    /// What the page says when every other section has nothing to show.
    case emptyState
    
    /// From the top of the homepage to its foot.
    ///
    /// The cards that are about the moment come first: the welcome on a new install, an update that is
    /// waiting. Then what people come to the page for. The standing advice to enable JIT is at the foot,
    /// where it can be read and acted on without being the first thing on every new tab.
    static var allCases: [HomepageSection] {
        return [
            .recommendation(.welcome),
            .recommendation(.updateAvailable),
            .recommendation(.donation),
            .privateBrowsing,
            .favorites,
            .frequentlyVisited,
            .recentlyClosedTabs,
            .emptyState,
            .recommendation(.performance),
        ]
    }
}

protocol HomepageSectionDelegate: AnyObject {
    func homepageSection(_ viewController: UIViewController, didRequestOpenURL url: URL, disposition: TabOpenDisposition)
    func homepageSection(
        _ viewController: UIViewController,
        didRequestShareURL url: URL,
        sourceView: UIView
    )
    func homepageSection(_ viewController: UIViewController, didRequestHideFromSuggestions siteID: Int64)
    func homepageSection(_ viewController: UIViewController, didSelectRecentlyClosedTab id: UUID)
    func homepageSectionDidSelectSettings(_ viewController: UIViewController)
}
