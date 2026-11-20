//
//  VerticalBarItems.swift
//  Reynard
//

import UIKit

/// The toolbar's buttons as bar button items, for the bar the system stands on its side.
///
/// On the cover display of an iPhone Duo the system draws a navigation controller's bars as one column beside
/// the status items. It places and compresses the items, moves what does not fit into its own overflow menu,
/// and keeps the column on the same side in right-to-left languages. Reynard's own `ToolbarButton`s can do
/// none of that, so there the same actions are handed to the system as items.
///
/// Every item has a title as well as a symbol: the column shows the symbol, the overflow menu shows both.
@available(iOS 27.1, *)
final class VerticalBarItems {
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onShare: (() -> Void)?
    var onLibrary: (() -> Void)?
    var onDownloads: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onTabOverview: (() -> Void)?

    private var historyProvider: ((ToolbarButtonMenus.NavigationDirection) -> [NavigationHistoryStore.HistoryItem])?
    private var onHistorySelect: ((ToolbarButtonMenus.NavigationDirection, Int) -> Void)?
    private var recentlyClosedTabsAvailable: (() -> Bool)?
    private var recentlyClosedTabsProvider: (() -> [TabManagementStore.RecentlyClosedTabSnapshot])?
    private var onRecentlyClosedTabSelect: ((UUID) -> Void)?

    // Back, the tab overview and the library are what a browser cannot do without, so they are the last to go
    // into the overflow menu. Forward and downloads are the first: both are a long press or a menu away.
    // Only the system's three priorities are used: on iOS 27.1 a value made between two of them ranked below
    // all three.
    private lazy var backItem = makeItem(
        title: NSLocalizedString("Back", comment: ""),
        symbol: "reynard.chevron.backward",
        priority: .high
    ) { [weak self] in self?.onBack?() }

    private lazy var forwardItem = makeItem(
        title: NSLocalizedString("Forward", comment: ""),
        symbol: "reynard.chevron.forward",
        priority: .low
    ) { [weak self] in self?.onForward?() }

    private lazy var shareItem = makeItem(
        title: NSLocalizedString("Share", comment: ""),
        symbol: "reynard.square.and.arrow.up",
        priority: .standard
    ) { [weak self] in self?.onShare?() }

    // The library opens on its bookmarks, and says so. Not an ellipsis: in a system bar that symbol is the
    // overflow menu's.
    private lazy var libraryItem = makeItem(
        title: NSLocalizedString("Bookmarks", comment: ""),
        symbol: "reynard.book",
        priority: .high,
        keepsActionInMenus: true
    ) { [weak self] in self?.onLibrary?() }

    private lazy var downloadsItem = makeItem(
        title: NSLocalizedString("Downloads", comment: ""),
        symbol: "reynard.arrow.down.circle",
        priority: .low
    ) { [weak self] in self?.onDownloads?() }

    private lazy var newTabItem = makeItem(
        title: NSLocalizedString("New Tab", comment: ""),
        symbol: "reynard.plus",
        priority: .standard,
        keepsActionInMenus: true
    ) { [weak self] in self?.onNewTab?() }

    private lazy var tabOverviewItem = makeItem(
        title: NSLocalizedString("Tabs", comment: ""),
        symbol: "reynard.square.on.square",
        priority: .high,
        keepsActionInMenus: true
    ) { [weak self] in self?.onTabOverview?() }

    // MARK: - Items

    /// The navigation bar's leading items, which the system puts at the top of the column.
    private(set) lazy var leadingGroups: [UIBarButtonItemGroup] = [
        UIBarButtonItemGroup(barButtonItems: [backItem, forwardItem], representativeItem: nil),
    ]

    /// The navigation bar's trailing items, which follow the leading ones.
    private(set) lazy var trailingGroups: [UIBarButtonItemGroup] = [
        UIBarButtonItemGroup(barButtonItems: [shareItem, libraryItem, downloadsItem], representativeItem: nil),
    ]

    /// The toolbar's items, which the system puts at the bottom of the column.
    private(set) lazy var toolbarItems: [UIBarButtonItem] = [newTabItem, tabOverviewItem]

    init() {
        backItem.isEnabled = false
        forwardItem.isEnabled = false
        shareItem.isEnabled = false
        downloadsItem.isHidden = true
    }

    // MARK: - Updates

    func updateNavigation(canGoBack: Bool, canGoForward: Bool, canShare: Bool) {
        backItem.isEnabled = canGoBack
        forwardItem.isEnabled = canGoForward
        shareItem.isEnabled = canShare
        // A menu with nothing in it would still open, so an item with no history has none.
        backItem.menu = canGoBack ? historyMenu(for: .back) : nil
        forwardItem.menu = canGoForward ? historyMenu(for: .forward) : nil
    }

    func updateDownload(_ summary: DownloadStoreSummary) {
        downloadsItem.isHidden = !summary.showsToolbarButton
    }

    func setMenuButtonIndicatesUpdate(_ hasUpdate: Bool) {
        libraryItem.badge = hasUpdate ? .indicator() : nil
    }

    // MARK: - Menus

    func configureNavigationMenus(
        itemsProvider: @escaping (ToolbarButtonMenus.NavigationDirection) -> [NavigationHistoryStore.HistoryItem],
        onSelect: @escaping (ToolbarButtonMenus.NavigationDirection, Int) -> Void
    ) {
        historyProvider = itemsProvider
        onHistorySelect = onSelect
    }

    func configureRecentlyClosedTabsMenu(
        isAvailable: @escaping () -> Bool,
        itemsProvider: @escaping () -> [TabManagementStore.RecentlyClosedTabSnapshot],
        onSelect: @escaping (UUID) -> Void
    ) {
        recentlyClosedTabsAvailable = isAvailable
        recentlyClosedTabsProvider = itemsProvider
        onRecentlyClosedTabSelect = onSelect
        newTabItem.menu = UIMenu(
            title: NSLocalizedString("Recently Closed Tabs", comment: ""),
            children: [UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.recentlyClosedTabActions() ?? [])
            }]
        )
    }

    func configureLibraryMenus(onSelect: @escaping (LibrarySection) -> Void) {
        libraryItem.menu = UIMenu(title: "", children: LibrarySection.allCases.map { section in
            UIAction(title: section.title, image: section.tabBarItem.image) { _ in
                onSelect(section)
            }
        })
    }

    func configureTabOverviewMenus(
        tabCountProvider: @escaping () -> Int,
        onCloseAllTabs: @escaping () -> Void,
        onCloseTab: @escaping () -> Void,
        onNewPrivateTab: @escaping () -> Void,
        onNewTab: @escaping () -> Void
    ) {
        tabOverviewItem.menu = UIMenu(title: "", children: [UIDeferredMenuElement.uncached { completion in
            let tabCount = tabCountProvider()
            var actions = [
                UIAction(
                    title: NSLocalizedString("Close This Tab", comment: ""),
                    image: UIImage(named: "reynard.xmark"),
                    attributes: .destructive
                ) { _ in onCloseTab() },
                UIAction(
                    title: NSLocalizedString("New Private Tab", comment: ""),
                    image: UIImage(named: "reynard.plus.square.fill.on.square.fill")
                ) { _ in onNewPrivateTab() },
                UIAction(
                    title: NSLocalizedString("New Tab", comment: ""),
                    image: UIImage(named: "reynard.plus.square.on.square")
                ) { _ in onNewTab() },
            ]
            if tabCount > 1 {
                actions.insert(UIAction(
                    title: String.localizedStringWithFormat(
                        NSLocalizedString("Close %d Tabs", comment: "Tab count"),
                        tabCount
                    ),
                    image: UIImage(named: "reynard.xmark"),
                    attributes: .destructive
                ) { _ in onCloseAllTabs() }, at: 0)
            }
            completion(actions)
        }])
    }

    private func historyMenu(for direction: ToolbarButtonMenus.NavigationDirection) -> UIMenu {
        return UIMenu(title: "", children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.historyActions(for: direction) ?? [])
        }])
    }

    private func historyActions(for direction: ToolbarButtonMenus.NavigationDirection) -> [UIAction] {
        let items = historyProvider?(direction) ?? []
        return items.enumerated().map { index, item in
            let url = displayURL(for: item.url)
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasTitle = !title.isEmpty && title != item.url
            return UIAction(title: hasTitle ? title : url, subtitle: url) { [weak self] _ in
                self?.onHistorySelect?(direction, index)
            }
        }
    }

    private func recentlyClosedTabActions() -> [UIAction] {
        guard recentlyClosedTabsAvailable?() == true else {
            return []
        }

        return (recentlyClosedTabsProvider?() ?? []).map { item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = item.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return UIAction(
                title: title.isEmpty ? NSLocalizedString("Untitled", comment: "") : title,
                subtitle: url.isEmpty ? nil : displayURL(for: url)
            ) { [weak self] _ in
                self?.onRecentlyClosedTabSelect?(item.id)
            }
        }
    }

    private func displayURL(for value: String) -> String {
        guard let url = URL(string: value) else {
            return value
        }
        return URLUtils.displayString(for: url)
    }

    // MARK: - Item Setup

    /// - Parameter keepsActionInMenus: An item with a long-press menu goes into the overflow menu as that
    ///   menu, which leaves its own action out of reach. Set for the items whose action matters more there.
    private func makeItem(
        title: String,
        symbol: String,
        priority: UIBarButtonItemVisibilityPriority,
        keepsActionInMenus: Bool = false,
        action: @escaping () -> Void
    ) -> UIBarButtonItem {
        let image = UIImage(named: symbol)
        let item = UIBarButtonItem(
            title: title,
            image: image,
            primaryAction: UIAction(title: title, image: image) { _ in action() }
        )
        if keepsActionInMenus {
            item.menuRepresentation = UIAction(title: title, image: image) { _ in action() }
        }
        item.visibilityPriority = priority
        item.tintColor = .label
        return item
    }
}
