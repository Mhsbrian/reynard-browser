//
//  TabBar.swift
//  Reynard
//
//  Created by Minh Ton on 5/3/26.
//

import UIKit

protocol TabBarDataSource: AnyObject {
    var tabs: [Tab] { get }
    var selectedTabID: UUID? { get }
    var selectedMode: TabMode { get }
    
    func selectTab(at index: Int, mode: TabMode)
    func closeTab(at index: Int, mode: TabMode)
    func moveTab(from sourceIndex: Int, to destinationIndex: Int, mode: TabMode)
}

final class TabBar: UIView {
    private enum UX {
        static let tabBarBottomPadding: CGFloat = 2
    }
    
    enum Visibility: Equatable {
        case hidden
        case layoutReserved
        case visible
    }
    
    enum ReorderState: Equatable {
        case idle
        case pending
        case active
    }
    
    struct CellLayout {
        let width: CGFloat
        let mode: TabBarCell.LayoutMode
    }
    
    /// How the tabs divide at the fold of an iPhone Duo that is partly open: some before it, the rest
    /// after, each group filling its own side, so that no tab lies across the fold.
    struct FoldSplit: Equatable {
        /// How many tabs are before the fold. None, or all of them, when one side has no room for a tab.
        let leadingTabCount: Int
        let leadingWidth: CGFloat
        let trailingWidth: CGFloat
        /// Where the tabs after the fold begin, from the start of the strip.
        let trailingOrigin: CGFloat
    }
    
    weak var dataSource: TabBarDataSource?
    /// Links dropped on the strip, to be opened in new tabs.
    var onDropLinks: (([URL]) -> Void)?
    
    private(set) var visibility: Visibility = .hidden
    private(set) var reorderState: ReorderState = .idle
    private var pendingExpandedTabID: UUID?
    private var displayedTabIDs: [UUID]?
    
    var pendingExpandedTabIndex: Int? {
        guard let pendingExpandedTabID else {
            return nil
        }
        return dataSource?.tabs.firstIndex { $0.id == pendingExpandedTabID }
    }
    
    var standardHeight: CGFloat {
        return BarMetrics.tabBarHeight + UX.tabBarBottomPadding
    }
    
    private let tabCollection = TabBarCollection()
    private lazy var presentation = TabBarPresentation(tabBar: self)
    
    private var heightConstraint: NSLayoutConstraint!
    private var tabCollectionHeightConstraint: NSLayoutConstraint!
    private var edgeConstraints: [NSLayoutConstraint] = []
    private var safeAreaConstraints: [NSLayoutConstraint] = []
    private var foldSideConstraints: [NSLayoutConstraint] = []
    private var stripSide: ClosedRange<CGFloat>?
    private let stripPlacementTracker = DisplayFoldTracker<StripPlacement>()
    
    /// Keeps the tabs clear of what the system puts at the sides of the window, which is where the inner
    /// display of an iPhone Duo has its status items. The background still runs from edge to edge.
    var keepsTabsInsideSafeArea = false {
        didSet {
            guard keepsTabsInsideSafeArea != oldValue else {
                return
            }
            applyHorizontalConstraints()
            setNeedsLayout()
        }
    }
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureConstraints()
        configureTabCollection()
        accessibilityIdentifier = AccessibilityIdentifier.TabBar.bar
        LinkDropHandler(acceptsText: false) { [weak self] content in
            if case let .links(urls) = content {
                self?.onDropLinks?(urls)
            }
        }.install(on: self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self && tabCollection.transform.ty < 0 ? nil : hitView
    }
    
    // MARK: - Layout
    
    func setVisibility(_ visibility: Visibility, animated: Bool) {
        presentation.setVisibility(visibility, animated: animated)
    }
    
    func setCollapseOffset(_ offset: CGFloat) {
        alpha = 1 - offset / max(bounds.height, 1)
        tabCollection.transform = CGAffineTransform(translationX: 0, y: -offset)
    }
    
    func invalidateLayout() {
        setNeedsLayout()
        tabCollection.invalidateLayout()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateStripPlacement()
    }
    
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        guard keepsTabsInsideSafeArea else {
            return
        }
        
        // The room for tabs changed without the bar changing size: a sidebar came or went beside the page.
        layoutIfNeeded()
        invalidateLayout()
    }
    
    /// The strip is as high as a tab's title needs at the text size in use.
    func textSizeDidChange() {
        tabCollectionHeightConstraint.constant = BarMetrics.tabBarHeight
        applyVisibility(visibility)
        invalidateLayout()
    }
    
    func updateLayout() {
        clearInvalidPendingExpansion()
        setNeedsLayout()
        tabCollection.updateLayout()
    }
    
    func cellLayout(at index: Int) -> CellLayout {
        let tabs = dataSource?.tabs ?? []
        let horizontalInset = tabCollection.adjustedContentInset.left + tabCollection.adjustedContentInset.right
        let containerWidth = tabCollection.bounds.width > 1 ? tabCollection.bounds.width : bounds.width
        guard let split = foldSplit else {
            return cellLayout(
                at: index,
                among: tabs.indices,
                in: tabs,
                availableWidth: max(0, containerWidth - horizontalInset),
                minimumExpandedTabCount: 1
            )
        }
        
        // Either side of a fold the same rules apply to the tabs of that side alone.
        let isBeforeFold = index < split.leadingTabCount
        return cellLayout(
            at: index,
            among: isBeforeFold ? 0..<split.leadingTabCount : split.leadingTabCount..<tabs.count,
            in: tabs,
            availableWidth: isBeforeFold ? split.leadingWidth : split.trailingWidth,
            minimumExpandedTabCount: 0
        )
    }
    
    private func cellLayout(
        at index: Int,
        among indices: Range<Int>,
        in tabs: [Tab],
        availableWidth: CGFloat,
        minimumExpandedTabCount: Int
    ) -> CellLayout {
        let layoutTabCount = max(1, indices.count)
        let equalTabWidth = floor(availableWidth / CGFloat(layoutTabCount))
        
        if equalTabWidth >= TabBarCell.expandedMinimumWidth {
            return CellLayout(width: equalTabWidth, mode: .expanded)
        }
        
        let usesExpandedLayout = isExpandedTab(at: index, in: tabs)
        let expandedTabCount = max(minimumExpandedTabCount, indices.reduce(0) { count, tabIndex in
            count + (isExpandedTab(at: tabIndex, in: tabs) ? 1 : 0)
        })
        let unselectedTabCount = max(0, layoutTabCount - expandedTabCount)
        
        let unselectedTabWidth: CGFloat
        let usesFaviconOnlyLayout: Bool
        if unselectedTabCount == 0 {
            unselectedTabWidth = availableWidth
            usesFaviconOnlyLayout = false
        } else {
            let availableUnselectedWidth = availableWidth - (TabBarCell.expandedMinimumWidth * CGFloat(expandedTabCount))
            unselectedTabWidth = floor(availableUnselectedWidth / CGFloat(unselectedTabCount))
            usesFaviconOnlyLayout = unselectedTabWidth <= TabBarCell.collapsedMinimumWidth
        }
        
        if usesExpandedLayout {
            return CellLayout(width: TabBarCell.expandedMinimumWidth, mode: .expanded)
        }
        
        if usesFaviconOnlyLayout {
            return CellLayout(width: TabBarCell.collapsedMinimumWidth, mode: .faviconOnly)
        }
        
        return CellLayout(width: max(0, unselectedTabWidth), mode: .expanded)
    }
    
    // MARK: - Fold
    
    /// How the tabs divide at the fold, or nil where there is none: every device but an iPhone Duo that is
    /// partly open. Also nil when the tabs do not fit either side of it however they are divided.
    var foldSplit: FoldSplit? {
        guard let band = tabCollection.foldBand else {
            return nil
        }
        
        let insets = tabCollection.adjustedContentInset
        return foldSplit(
            band: (band.lowerBound - insets.left)...(band.upperBound - insets.left),
            stripWidth: tabCollection.bounds.width - insets.left - insets.right
        )
    }
    
    /// - Parameters:
    ///   - band: The band the fold keeps clear, measured from the leading edge of the room for tabs.
    ///   - stripWidth: The room for tabs, fold included.
    private func foldSplit(band: ClosedRange<CGFloat>, stripWidth: CGFloat) -> FoldSplit? {
        guard let tabs = dataSource?.tabs, !tabs.isEmpty else {
            return nil
        }
        
        let leadingWidth = max(0, band.lowerBound)
        let trailingWidth = max(0, stripWidth - band.upperBound)
        
        // Each side takes its share of the tabs, or the nearest division to that which fits. A side with no
        // room for a tab holds none.
        let evenCount = Int((CGFloat(tabs.count) * leadingWidth / max(leadingWidth + trailingWidth, 1)).rounded())
        let counts = (0...tabs.count).sorted {
            (abs($0 - evenCount), $0) < (abs($1 - evenCount), $1)
        }
        guard let leadingTabCount = counts.first(where: {
            fits(0..<$0, in: tabs, width: leadingWidth) && fits($0..<tabs.count, in: tabs, width: trailingWidth)
        }) else {
            return nil
        }
        
        return FoldSplit(
            leadingTabCount: leadingTabCount,
            leadingWidth: leadingWidth,
            trailingWidth: trailingWidth,
            trailingOrigin: band.upperBound
        )
    }
    
    /// Where the strip goes when the fold of an iPhone Duo that is partly open runs through its room and
    /// the tabs are too many to divide there: the wider side, the leading one where both are alike. The
    /// strip scrolls within that side, and no tab lies across the fold.
    private struct StripPlacement: Equatable {
        /// The left and right edges of the side the strip keeps to, in this view's coordinates. Nil where
        /// it has all its room, which is everywhere else.
        let side: ClosedRange<CGFloat>?
        let band: ClosedRange<CGFloat>?
        let width: CGFloat
    }
    
    private func updateStripPlacement() {
        let placement = resolvedStripPlacement()
        let isFoldChange = stripPlacementTracker.applied.map {
            $0.width == placement.width && $0.band != placement.band
        } ?? false
        stripPlacementTracker.update(
            in: self,
            value: placement,
            animated: isFoldChange,
            current: { [weak self] in self?.resolvedStripPlacement() ?? placement },
            apply: { [weak self] in self?.applyStripPlacement($0) }
        )
    }
    
    private func resolvedStripPlacement() -> StripPlacement {
        let width = bounds.width
        let left = keepsTabsInsideSafeArea ? safeAreaInsets.left : 0
        let right = width - (keepsTabsInsideSafeArea ? safeAreaInsets.right : 0)
        guard right > left,
              let band = activeFoldBand(crossing: CGRect(x: left, y: 0, width: right - left, height: bounds.height)) else {
            return StripPlacement(side: nil, band: nil, width: width)
        }
        
        // The layout counts from the leading edge, and the system mirrors it for a right-to-left language.
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let leadingBand = isRightToLeft
        ? (right - band.upperBound)...(right - band.lowerBound)
        : (band.lowerBound - left)...(band.upperBound - left)
        guard foldSplit(band: leadingBand, stripWidth: right - left) == nil else {
            return StripPlacement(side: nil, band: band, width: width)
        }
        
        let leftWidth = band.lowerBound - left
        let rightWidth = right - band.upperBound
        let usesLeft = abs(leftWidth - rightWidth) <= 1 ? !isRightToLeft : leftWidth > rightWidth
        return StripPlacement(
            side: usesLeft ? left...band.lowerBound : band.upperBound...right,
            band: band,
            width: width
        )
    }
    
    private func applyStripPlacement(_ placement: StripPlacement) {
        stripSide = placement.side
        applyHorizontalConstraints()
    }
    
    private func applyHorizontalConstraints() {
        NSLayoutConstraint.deactivate(edgeConstraints + safeAreaConstraints + foldSideConstraints)
        if let stripSide, foldSideConstraints.count == 2 {
            foldSideConstraints[0].constant = stripSide.lowerBound
            foldSideConstraints[1].constant = stripSide.upperBound
            NSLayoutConstraint.activate(foldSideConstraints)
        } else {
            NSLayoutConstraint.activate(keepsTabsInsideSafeArea ? safeAreaConstraints : edgeConstraints)
        }
    }
    
    /// Whether these tabs can be shown in this width without scrolling: the rule of `cellLayout(at:)`.
    private func fits(_ indices: Range<Int>, in tabs: [Tab], width: CGFloat) -> Bool {
        guard !indices.isEmpty else {
            return true
        }
        
        if floor(width / CGFloat(indices.count)) >= TabBarCell.expandedMinimumWidth {
            return true
        }
        
        let expandedTabCount = indices.reduce(0) { count, tabIndex in
            count + (isExpandedTab(at: tabIndex, in: tabs) ? 1 : 0)
        }
        let otherTabCount = indices.count - expandedTabCount
        guard otherTabCount > 0 else {
            return CGFloat(expandedTabCount) * TabBarCell.expandedMinimumWidth <= width
        }
        
        let otherWidth = floor((width - (TabBarCell.expandedMinimumWidth * CGFloat(expandedTabCount))) / CGFloat(otherTabCount))
        return otherWidth > TabBarCell.collapsedMinimumWidth
    }
    
    // MARK: - Updates
    
    func reloadTabs() {
        clearInvalidPendingExpansion()
        setNeedsLayout()
        let tabs = dataSource?.tabs ?? []
        let (insertedIndices, deletedIndices) = changedTabIndices(in: tabs)
        if !insertedIndices.isEmpty && deletedIndices.isEmpty {
            tabCollection.updateTabs(inserting: insertedIndices)
        } else if insertedIndices.isEmpty && !deletedIndices.isEmpty {
            tabCollection.updateTabs(deleting: deletedIndices)
        } else {
            tabCollection.reloadTabs()
        }
        displayedTabIDs = tabs.map { $0.id }
    }
    
    func reloadTab(at index: Int) {
        setNeedsLayout()
        tabCollection.reloadTab(at: index)
    }
    
    func setPendingExpansion(at index: Int?) {
        pendingExpandedTabID = index.flatMap { dataSource?.tabs[safe: $0]?.id }
        setNeedsLayout()
        if index != nil {
            tabCollection.reloadTabs()
        }
    }
    
    func isTabSelected(at index: Int) -> Bool {
        guard let tabs = dataSource?.tabs,
              tabs.indices.contains(index) else {
            return false
        }
        
        return isTabSelected(id: tabs[index].id)
    }
    
    func isTabSelected(id: UUID) -> Bool {
        guard let tabs = dataSource?.tabs else {
            return false
        }
        
        let selectedTabID = pendingExpandedTabID.flatMap { pendingTabID in
            tabs.first { $0.id == pendingTabID }?.id
        }
        ?? dataSource?.selectedTabID
        return id == selectedTabID
    }
    
    func setPresentationAlpha(_ alpha: CGFloat) {
        presentation.setAlpha(alpha)
    }
    
    private func changedTabIndices(in tabs: [Tab]) -> (inserted: [Int], deleted: [Int]) {
        guard let displayedTabIDs,
              !displayedTabIDs.isEmpty,
              displayedTabIDs.count != tabs.count else {
            return ([], [])
        }
        
        let currentTabIDs = tabs.map { $0.id }
        let displayedTabIDSet = Set(displayedTabIDs)
        let currentTabIDSet = Set(currentTabIDs)
        if displayedTabIDs.count < currentTabIDs.count {
            guard displayedTabIDSet.isSubset(of: currentTabIDSet) else {
                return ([], [])
            }
            return (currentTabIDs.indices.filter { !displayedTabIDSet.contains(currentTabIDs[$0]) }, [])
        }
        
        guard currentTabIDSet.isSubset(of: displayedTabIDSet) else {
            return ([], [])
        }
        return ([], displayedTabIDs.indices.filter { !currentTabIDSet.contains(displayedTabIDs[$0]) })
    }
    
    // MARK: - Collection Coordination
    
    func updateReorderState(_ state: ReorderState) {
        reorderState = state
    }
    
    func requestSelectTab(at index: Int) {
        guard let dataSource else {
            return
        }
        dataSource.selectTab(at: index, mode: dataSource.selectedMode)
    }
    
    func requestCloseTab(at index: Int) {
        pendingExpandedTabID = nil
        guard let dataSource else {
            return
        }
        dataSource.closeTab(at: index, mode: dataSource.selectedMode)
    }
    
    func requestMoveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard let dataSource else {
            return
        }
        dataSource.moveTab(from: sourceIndex, to: destinationIndex, mode: dataSource.selectedMode)
        displayedTabIDs = dataSource.tabs.map { $0.id }
    }
    
    // MARK: - View Setup
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        clipsToBounds = true
        isHidden = true
    }
    
    private func configureHierarchy() {
        addSubview(tabCollection)
    }
    
    private func configureConstraints() {
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        tabCollectionHeightConstraint = tabCollection.heightAnchor.constraint(equalToConstant: BarMetrics.tabBarHeight)
        edgeConstraints = [
            tabCollection.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabCollection.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        safeAreaConstraints = [
            tabCollection.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            tabCollection.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
        ]
        // Left and right: the fold is a place on the hardware, whatever the language.
        foldSideConstraints = [
            tabCollection.leftAnchor.constraint(equalTo: leftAnchor),
            tabCollection.rightAnchor.constraint(equalTo: leftAnchor),
        ]
        NSLayoutConstraint.activate(edgeConstraints + [
            tabCollection.topAnchor.constraint(equalTo: topAnchor),
            tabCollectionHeightConstraint,
            heightConstraint,
        ])
    }
    
    private func configureTabCollection() {
        tabCollection.attach(to: self)
    }
    
    // MARK: - Layout State
    
    private func clearInvalidPendingExpansion() {
        guard pendingExpandedTabID != nil else {
            return
        }
        
        if pendingExpandedTabIndex == nil {
            pendingExpandedTabID = nil
        }
    }
    
    private func isExpandedTab(at index: Int, in tabs: [Tab]) -> Bool {
        guard let tab = displayedTab(at: index, in: tabs) else {
            return false
        }
        return isTabSelected(id: tab.id)
    }
    
    private func displayedTab(at index: Int, in tabs: [Tab]) -> Tab? {
        guard tabs.indices.contains(index) else {
            return nil
        }
        
        guard let sourceIndex = tabCollection.dragSourceIndex,
              let targetIndex = tabCollection.dragDestinationIndex,
              tabs.indices.contains(sourceIndex),
              tabs.indices.contains(targetIndex),
              sourceIndex != targetIndex else {
            return tabs[index]
        }
        
        var reorderedTabs = tabs
        let movedTab = reorderedTabs.remove(at: sourceIndex)
        reorderedTabs.insert(movedTab, at: targetIndex)
        return reorderedTabs[index]
    }
    
    // MARK: - Presentation Coordination
    
    func applyVisibility(_ visibility: Visibility) {
        self.visibility = visibility
        let isHidden = visibility == .hidden
        heightConstraint.constant = isHidden ? 0 : standardHeight
    }
}
