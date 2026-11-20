//
//  TabOverviewVerticalBarItems.swift
//  Reynard
//

import UIKit

/// The tab overview's actions as bar button items, for the bar the system stands on its side.
///
/// They take the place of the browser's own items in that bar while the overview is open: see
/// `VerticalBarItems`. The switch between private and regular tabs is not among them, because a segmented
/// control has no vertical form; it stays at the bottom of the overview.
@available(iOS 27.1, *)
final class TabOverviewVerticalBarItems {
    var onClearTabs: (() -> Void)?
    var onClearTabsOlderThan: ((TabOverviewClearTabsMenu.Age) -> Void)?
    var onAddTab: (() -> Void)?
    var onDone: (() -> Void)?
    
    // Closing tabs only ever opens a menu, so it is the first to go into the overflow menu.
    private lazy var clearTabsItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            title: NSLocalizedString("Close All Tabs", comment: ""),
            image: UIImage(systemName: "trash"),
            primaryAction: nil,
            menu: nil
        )
        item.visibilityPriority = .low
        item.tintColor = .label
        return item
    }()
    
    private lazy var addTabItem: UIBarButtonItem = {
        let title = NSLocalizedString("New Tab", comment: "")
        let image = UIImage(named: "reynard.plus")
        let item = UIBarButtonItem(
            title: title,
            image: image,
            primaryAction: UIAction(title: title, image: image) { [weak self] _ in self?.onAddTab?() }
        )
        item.visibilityPriority = .standard
        item.tintColor = .label
        return item
    }()
    
    private lazy var doneItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak self] _ in self?.onDone?() }
        )
        item.visibilityPriority = .high
        return item
    }()
    
    /// The navigation bar's items, at the top of the column.
    private(set) lazy var trailingGroups: [UIBarButtonItemGroup] = [
        UIBarButtonItemGroup(barButtonItems: [clearTabsItem], representativeItem: nil),
    ]
    
    /// The toolbar's items, at the bottom of the column.
    private(set) lazy var toolbarItems: [UIBarButtonItem] = [addTabItem, doneItem]
    
    func apply(visibleTabCount: Int, hasVisibleTab: Bool) {
        clearTabsItem.menu = TabOverviewClearTabsMenu.make(
            tabCount: visibleTabCount,
            onClearTabs: { [weak self] in self?.onClearTabs?() },
            onClearTabsOlderThan: { [weak self] age in self?.onClearTabsOlderThan?(age) }
        )
        doneItem.isEnabled = hasVisibleTab
    }
}
