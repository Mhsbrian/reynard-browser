//
//  TabOverviewCollectionLayout.swift
//  Reynard
//
//  Created by Minh Ton on 10/6/26.
//

import UIKit

final class TabOverviewCollectionLayout: UICollectionViewFlowLayout {
    private enum UX {
        static let insertedTabCardInitialScale: CGFloat = 0.85
    }
    
    private var insertedCardIndexPaths = Set<IndexPath>()
    
    /// The columns either side of the fold of an iPhone Duo that is partly open, where the grid divides.
    /// Nil everywhere else, and then the cards are where a flow layout puts them.
    var foldedColumns: (() -> FoldedColumns?)?
    
    private func dividedAtFold(_ attributes: UICollectionViewLayoutAttributes?) -> UICollectionViewLayoutAttributes? {
        guard let attributes,
              attributes.representedElementCategory == .cell,
              let columns = foldedColumns?(),
              !columns.origins.isEmpty,
              let moved = attributes.copy() as? UICollectionViewLayoutAttributes else {
            return attributes
        }
        
        moved.frame.origin.x = columns.origins[attributes.indexPath.item % columns.origins.count]
        return moved
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        return dividedAtFold(super.layoutAttributesForItem(at: indexPath))
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard foldedColumns?() != nil else {
            return super.layoutAttributesForElements(in: rect)
        }
        
        // A card may move sideways out of or into `rect`: ask for the whole width of its rows.
        let rows = CGRect(x: 0, y: rect.minY, width: collectionViewContentSize.width, height: rect.height)
        return super.layoutAttributesForElements(in: rows)?.compactMap { dividedAtFold($0) }
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else {
            return super.shouldInvalidateLayout(forBoundsChange: newBounds)
        }
        
        return collectionView.bounds.size != newBounds.size
        || super.shouldInvalidateLayout(forBoundsChange: newBounds)
    }
    
    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        guard let flowContext = context as? UICollectionViewFlowLayoutInvalidationContext,
              let collectionView else {
            return context
        }
        
        flowContext.invalidateFlowLayoutDelegateMetrics = collectionView.bounds.size != newBounds.size
        return flowContext
    }
    
    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        insertedCardIndexPaths = Set(updateItems.compactMap { updateItem in
            updateItem.updateAction == .insert ? updateItem.indexPathAfterUpdate : nil
        })
    }
    
    override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes
        ?? layoutAttributesForItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes
        if insertedCardIndexPaths.contains(itemIndexPath) {
            attributes?.alpha = 0
            attributes?.transform = CGAffineTransform(
                scaleX: UX.insertedTabCardInitialScale,
                y: UX.insertedTabCardInitialScale
            )
        }
        return attributes
    }
    
    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        insertedCardIndexPaths.removeAll()
    }
}
