//
//  WorkoutGridLayout.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import UIKit

final class WorkoutGridLayout: UICollectionViewLayout {
    var columns: CGFloat = 3 {
        didSet {
            guard abs(columns - oldValue) > 0.001 else { return }
            invalidateLayout()
        }
    }

    var itemSpacing: CGFloat = 12
    var lineSpacing: CGFloat = 2
    var sectionInset = UIEdgeInsets(top: 0, left: 12, bottom: 16, right: 12)
    var itemAspectRatio: CGFloat = 0.74
    var minimumItemHeight: CGFloat = 72
    var sectionHeaderHeight: CGFloat = 0

    private var cachedAttributes: [UICollectionViewLayoutAttributes] = []
    private var cachedItemAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var cachedHeaderAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var cachedContentSize = CGSize.zero

    override var collectionViewContentSize: CGSize {
        cachedContentSize
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else {
            cachedAttributes = []
            cachedItemAttributes = [:]
            cachedHeaderAttributes = [:]
            cachedContentSize = .zero
            return
        }

        let totalItemCount = (0..<collectionView.numberOfSections).reduce(0) { total, section in
            total + collectionView.numberOfItems(inSection: section)
        }
        guard totalItemCount > 0 else {
            cachedAttributes = []
            cachedItemAttributes = [:]
            cachedHeaderAttributes = [:]
            cachedContentSize = CGSize(width: collectionView.bounds.width, height: 0)
            return
        }

        let clampedColumns = min(max(columns, 2), 6)
        let lowerColumns = max(Int(floor(clampedColumns)), 2)
        let upperColumns = min(max(Int(ceil(clampedColumns)), lowerColumns), 6)
        let rawProgress = upperColumns == lowerColumns ? 0 : clampedColumns - CGFloat(lowerColumns)
        let progress = smoothstep(rawProgress)
        let lowerMetrics = metrics(for: lowerColumns, collectionWidth: collectionView.bounds.width)
        let upperMetrics = metrics(for: upperColumns, collectionWidth: collectionView.bounds.width)

        var attributes: [UICollectionViewLayoutAttributes] = []
        var itemAttributesByIndexPath: [IndexPath: UICollectionViewLayoutAttributes] = [:]
        var headerAttributesByIndexPath: [IndexPath: UICollectionViewLayoutAttributes] = [:]
        attributes.reserveCapacity(totalItemCount + collectionView.numberOfSections)

        var sectionOriginY: CGFloat = 0
        for section in 0..<collectionView.numberOfSections {
            let itemCount = collectionView.numberOfItems(inSection: section)
            guard itemCount > 0 else {
                continue
            }

            if sectionHeaderHeight > 0 {
                let indexPath = IndexPath(item: 0, section: section)
                let headerAttributes = UICollectionViewLayoutAttributes(
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    with: indexPath
                )
                headerAttributes.frame = CGRect(
                    x: 0,
                    y: sectionOriginY,
                    width: collectionView.bounds.width,
                    height: sectionHeaderHeight
                )
                headerAttributes.zIndex = 1
                headerAttributesByIndexPath[indexPath] = headerAttributes
                attributes.append(headerAttributes)
                sectionOriginY += sectionHeaderHeight
            }

            var lastFrame = CGRect.zero
            for item in 0..<itemCount {
                let indexPath = IndexPath(item: item, section: section)
                let itemAttributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                let lowerFrame = frame(forItemAt: item, metrics: lowerMetrics, sectionOriginY: sectionOriginY)
                let upperFrame = frame(forItemAt: item, metrics: upperMetrics, sectionOriginY: sectionOriginY)
                itemAttributes.frame = interpolate(from: lowerFrame, to: upperFrame, progress: progress)
                itemAttributesByIndexPath[indexPath] = itemAttributes
                attributes.append(itemAttributes)
                lastFrame = itemAttributes.frame
            }

            sectionOriginY = lastFrame.maxY + sectionInset.bottom
        }

        cachedAttributes = attributes.sorted {
            if $0.frame.minY != $1.frame.minY {
                return $0.frame.minY < $1.frame.minY
            }

            return $0.frame.minX < $1.frame.minX
        }
        cachedItemAttributes = itemAttributesByIndexPath
        cachedHeaderAttributes = headerAttributesByIndexPath
        cachedContentSize = CGSize(width: collectionView.bounds.width, height: sectionOriginY)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard !cachedAttributes.isEmpty else {
            return []
        }

        let lookupRect = rect.insetBy(dx: 0, dy: -minimumItemHeight)
        var visibleAttributes: [UICollectionViewLayoutAttributes] = []
        var index = firstAttributeIndex(withMaxYAtLeast: lookupRect.minY)

        while index < cachedAttributes.count {
            let attributes = cachedAttributes[index]
            guard attributes.frame.minY <= lookupRect.maxY else {
                break
            }

            if attributes.frame.intersects(lookupRect) {
                visibleAttributes.append(attributes)
            }
            index += 1
        }

        return visibleAttributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        cachedItemAttributes[indexPath]
    }

    override func layoutAttributesForSupplementaryView(
        ofKind elementKind: String,
        at indexPath: IndexPath
    ) -> UICollectionViewLayoutAttributes? {
        guard elementKind == UICollectionView.elementKindSectionHeader else {
            return nil
        }

        return cachedHeaderAttributes[indexPath]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        collectionView?.bounds.size != newBounds.size
    }

    private struct Metrics {
        let columns: Int
        let itemSize: CGSize
    }

    private func metrics(for columns: Int, collectionWidth: CGFloat) -> Metrics {
        let availableWidth = collectionWidth - sectionInset.left - sectionInset.right
        let totalSpacing = itemSpacing * CGFloat(max(columns - 1, 0))
        let width = max((availableWidth - totalSpacing) / CGFloat(columns), 1)
        let height = max(minimumItemHeight, width * itemAspectRatio)
        return Metrics(columns: columns, itemSize: CGSize(width: width, height: height))
    }

    private func frame(forItemAt item: Int, metrics: Metrics, sectionOriginY: CGFloat) -> CGRect {
        let row = item / metrics.columns
        let column = item % metrics.columns
        let x = sectionInset.left + CGFloat(column) * (metrics.itemSize.width + itemSpacing)
        let y = sectionOriginY + sectionInset.top + CGFloat(row) * (metrics.itemSize.height + lineSpacing)
        return CGRect(origin: CGPoint(x: x, y: y), size: metrics.itemSize)
    }

    private func interpolate(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: start.minX + (end.minX - start.minX) * progress,
            y: start.minY + (end.minY - start.minY) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        )
    }

    private func smoothstep(_ progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func firstAttributeIndex(withMaxYAtLeast minY: CGFloat) -> Int {
        var lowerBound = 0
        var upperBound = cachedAttributes.count

        while lowerBound < upperBound {
            let middleIndex = (lowerBound + upperBound) / 2
            if cachedAttributes[middleIndex].frame.maxY < minY {
                lowerBound = middleIndex + 1
            } else {
                upperBound = middleIndex
            }
        }

        return lowerBound
    }

}
