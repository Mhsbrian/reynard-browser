//
//  FavoritesCollectionViewLayout.swift
//  Reynard
//
//  Created by Minh Ton on 21/6/26.
//

import UIKit

struct FavoritesLayoutMetrics: Equatable {
    private enum UX {
        static let maximumIconSize: CGFloat = 74
        static let minimumInteritemSpacing: CGFloat = 15
        static let shadowPadding: CGFloat = 10
    }
    
    static let shadowPadding: CGFloat = UX.shadowPadding
    
    let columnCount: Int
    let horizontalInset: CGFloat
    let itemSize: CGSize
    let interitemSpacing: CGFloat
    let lineSpacing: CGFloat
    /// The left edge of each column where the grid divides at the fold of an iPhone Duo that is partly open,
    /// and nil everywhere else: see `FoldedColumns`.
    let foldedColumnOrigins: [CGFloat]?
    
    /// - Parameter foldBand: The band the fold keeps clear, in the grid's coordinates, where there is one.
    init(
        width: CGFloat,
        columnCount: Int,
        horizontalInset: CGFloat,
        lineSpacing: CGFloat,
        foldBand: ClosedRange<CGFloat>? = nil
    ) {
        self.columnCount = max(columnCount, 1)
        self.horizontalInset = horizontalInset
        self.lineSpacing = lineSpacing
        if let foldBand, width - horizontalInset > horizontalInset {
            let columns = FoldedColumns(
                count: self.columnCount,
                span: horizontalInset...(width - horizontalInset),
                band: foldBand,
                spacing: UX.minimumInteritemSpacing,
                maximumItemWidth: UX.maximumIconSize
            )
            foldedColumnOrigins = columns.origins
            interitemSpacing = UX.minimumInteritemSpacing
            itemSize = CGSize(width: columns.itemWidth, height: columns.itemWidth + FavoriteSiteCollectionViewCell.titleHeight)
            return
        }
        
        foldedColumnOrigins = nil
        let contentWidth = max(width - (horizontalInset * 2), 1)
        let totalMinimumSpacing = CGFloat(max(self.columnCount - 1, 0)) * UX.minimumInteritemSpacing
        let availableIconWidth = (contentWidth - totalMinimumSpacing) / CGFloat(self.columnCount)
        let itemWidth = min(UX.maximumIconSize, availableIconWidth)
        let remainingWidth = contentWidth - (CGFloat(self.columnCount) * itemWidth)
        interitemSpacing = self.columnCount > 1
        ? max(remainingWidth / CGFloat(self.columnCount - 1), 0)
        : 0
        itemSize = CGSize(width: itemWidth, height: itemWidth + FavoriteSiteCollectionViewCell.titleHeight)
    }
    
    func contentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else {
            return 0
        }
        
        return Self.shadowPadding
        + (CGFloat(rowCount) * itemSize.height)
        + (CGFloat(max(rowCount - 1, 0)) * lineSpacing)
    }
}

final class FavoritesCollectionViewLayout: UICollectionViewLayout {
    var metrics: FavoritesLayoutMetrics? {
        didSet {
            invalidateLayout()
        }
    }
    
    private var cachedAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var contentSize: CGSize = .zero
    private var appearingIndexPaths = Set<IndexPath>()
    private var disappearingAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    
    override var collectionViewContentSize: CGSize {
        return contentSize
    }
    
    // MARK: - Lifecycle
    
    override func prepare() {
        super.prepare()
        guard let collectionView,
              let metrics else {
            cachedAttributes = [:]
            contentSize = .zero
            return
        }
        
        let itemCount = collectionView.numberOfItems(inSection: 0)
        let rowCount = Int(ceil(CGFloat(itemCount) / CGFloat(metrics.columnCount)))
        contentSize = CGSize(
            width: collectionView.bounds.width,
            height: metrics.contentHeight(rowCount: rowCount)
        )
        
        cachedAttributes = [:]
        for item in 0..<itemCount {
            let indexPath = IndexPath(item: item, section: 0)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = frame(forItemAt: item, metrics: metrics)
            cachedAttributes[indexPath] = attributes
        }
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return cachedAttributes.values.filter { attributes in
            return attributes.frame.intersects(rect)
        }
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return cachedAttributes[indexPath]
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else {
            return true
        }
        
        return abs(collectionView.bounds.width - newBounds.width) > 0.5
    }
    
    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        appearingIndexPaths = Set(updateItems.compactMap { updateItem in
            updateItem.updateAction == .insert ? updateItem.indexPathAfterUpdate : nil
        })
        disappearingAttributes = updateItems.reduce(into: [:]) { attributes, updateItem in
            guard updateItem.updateAction == .delete,
                  let indexPath = updateItem.indexPathBeforeUpdate,
                  let cachedAttribute = cachedAttributes[indexPath]?.copy() as? UICollectionViewLayoutAttributes else {
                return
            }
            
            attributes[indexPath] = cachedAttribute
        }
    }
    
    override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = layoutAttributesForItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes
        if appearingIndexPaths.contains(itemIndexPath) {
            attributes?.alpha = 0
        }
        return attributes
    }
    
    override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = disappearingAttributes[itemIndexPath]?.copy() as? UICollectionViewLayoutAttributes
        attributes?.alpha = 0
        return attributes
    }
    
    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        appearingIndexPaths.removeAll()
        disappearingAttributes.removeAll()
    }
    
    // MARK: - Helpers
    
    private func frame(forItemAt item: Int, metrics: FavoritesLayoutMetrics) -> CGRect {
        let row = item / metrics.columnCount
        let column = item % metrics.columnCount
        let x = metrics.foldedColumnOrigins?[safe: column]
        ?? metrics.horizontalInset + CGFloat(column) * (metrics.itemSize.width + metrics.interitemSpacing)
        let y = FavoritesLayoutMetrics.shadowPadding + CGFloat(row) * (metrics.itemSize.height + metrics.lineSpacing)
        return CGRect(origin: CGPoint(x: x, y: y), size: metrics.itemSize)
    }
}
