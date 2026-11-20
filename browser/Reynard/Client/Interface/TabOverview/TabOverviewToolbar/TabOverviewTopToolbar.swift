//
//  TabOverviewTopToolbar.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TabOverviewTopToolbar: UIView {
    private enum UX {
        static let toolbarContentHorizontalInset: CGFloat = 32
        static let statusRowContentHorizontalInset: CGFloat = 12
        static let actionButtonSpacing: CGFloat = 10
        static let actionControlsTopOffset: CGFloat = 38
        static let tabModeControlHeight: CGFloat = 32
        static let tabModeControlMaximumWidth: CGFloat = 375
        static let modeControlToActionControlsSpacing: CGFloat = 16
    }
    
    var onClearTabs: (() -> Void)?
    var onClearTabsOlderThan: ((TabOverviewClearTabsMenu.Age) -> Void)?
    var onAddTab: (() -> Void)?
    var onDone: (() -> Void)?
    var onTabModeChange: ((TabOverview.Mode) -> Void)?
    
    private let clearTabsButton = TabOverviewToolbarButton(action: .clear)
    private let addTabButton = TabOverviewToolbarButton(action: .add)
    private let doneButton = TabOverviewToolbarButton(action: .done)
    private lazy var actionButtonStackView = UIStackView(arrangedSubviews: [clearTabsButton, addTabButton, doneButton])
    private var standardConstraints: [NSLayoutConstraint] = []
    private var statusRowConstraints: [NSLayoutConstraint] = []
    private var sharesStatusRow = false
    private let tabModeControl = UISegmentedControl(items: [NSLocalizedString("Private", comment: ""), NSLocalizedString("0 Tabs", comment: "")])
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureActions()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setMode(_ mode: TabOverview.Mode) {
        tabModeControl.selectedSegmentIndex = mode.rawValue
    }
    
    func apply(tabCount: Int, visibleTabCount: Int, hasVisibleTab: Bool) {
        tabModeControl.setTitle(
            String.localizedStringWithFormat(NSLocalizedString("%d Tabs", comment: "Tab count"), tabCount),
            forSegmentAt: TabOverview.Mode.regularTabs.rawValue
        )
        let clearTabsMenu = TabOverviewClearTabsMenu.make(
            tabCount: visibleTabCount,
            onClearTabs: { [weak self] in self?.onClearTabs?() },
            onClearTabsOlderThan: { [weak self] age in self?.onClearTabsOlderThan?(age) }
        )
        clearTabsButton.installMenu(clearTabsMenu)
        doneButton.setActionEnabled(hasVisibleTab)
    }
    
    /// In the status items' row the toolbar is exactly the system's region for a top bar: its controls are
    /// centred in the row and go to its ends, which already stop short of the display's edge and of the
    /// status items.
    func setSharesStatusRow(_ sharesStatusRow: Bool) {
        guard self.sharesStatusRow != sharesStatusRow else {
            return
        }
        
        self.sharesStatusRow = sharesStatusRow
        NSLayoutConstraint.deactivate(sharesStatusRow ? standardConstraints : statusRowConstraints)
        NSLayoutConstraint.activate(sharesStatusRow ? statusRowConstraints : standardConstraints)
    }
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        actionButtonStackView.translatesAutoresizingMaskIntoConstraints = false
        actionButtonStackView.axis = .horizontal
        actionButtonStackView.alignment = .center
        actionButtonStackView.distribution = .fill
        actionButtonStackView.spacing = UX.actionButtonSpacing
        tabModeControl.translatesAutoresizingMaskIntoConstraints = false
        tabModeControl.selectedSegmentIndex = TabOverview.Mode.regularTabs.rawValue
        tabModeControl.accessibilityIdentifier = AccessibilityIdentifier.TabOverview.mode
    }
    
    private func configureHierarchy() {
        addSubview(actionButtonStackView)
        addSubview(tabModeControl)
    }
    
    private func configureConstraints() {
        let actionControlsView = actionButtonStackView
        let tabModeMaximumWidthConstraint = tabModeControl.widthAnchor.constraint(equalToConstant: UX.tabModeControlMaximumWidth)
        tabModeMaximumWidthConstraint.priority = .defaultHigh
        standardConstraints = [
            actionControlsView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -UX.toolbarContentHorizontalInset),
            actionControlsView.centerYAnchor.constraint(equalTo: topAnchor, constant: UX.actionControlsTopOffset),
            tabModeControl.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: UX.toolbarContentHorizontalInset),
        ]
        statusRowConstraints = [
            actionControlsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UX.statusRowContentHorizontalInset),
            actionControlsView.centerYAnchor.constraint(equalTo: centerYAnchor),
            tabModeControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UX.statusRowContentHorizontalInset),
        ]
        NSLayoutConstraint.activate(standardConstraints)
        NSLayoutConstraint.activate([
            tabModeControl.trailingAnchor.constraint(lessThanOrEqualTo: actionControlsView.leadingAnchor, constant: -UX.modeControlToActionControlsSpacing),
            tabModeControl.centerYAnchor.constraint(equalTo: actionControlsView.centerYAnchor),
            tabModeControl.heightAnchor.constraint(greaterThanOrEqualToConstant: UX.tabModeControlHeight),
            tabModeMaximumWidthConstraint,
        ])
    }
    
    private func configureActions() {
        addTabButton.addTarget(self, action: #selector(addTabButtonTapped), for: .touchUpInside)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        tabModeControl.addTarget(self, action: #selector(tabModeControlChanged), for: .valueChanged)
    }
    
    @objc private func addTabButtonTapped() { onAddTab?() }
    @objc private func doneTapped() { onDone?() }
    @objc private func tabModeControlChanged() {
        onTabModeChange?(TabOverview.Mode(rawValue: tabModeControl.selectedSegmentIndex) ?? .regularTabs)
    }
}
