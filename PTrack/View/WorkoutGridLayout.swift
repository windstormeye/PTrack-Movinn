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

    private var cachedAttributes: [UICollectionViewLayoutAttributes] = []
    private var cachedContentSize = CGSize.zero

    override var collectionViewContentSize: CGSize {
        cachedContentSize
    }

    override func prepare() {
        super.prepare()
        guard let collectionView else {
            cachedAttributes = []
            cachedContentSize = .zero
            return
        }

        let itemCount = collectionView.numberOfItems(inSection: 0)
        guard itemCount > 0 else {
            cachedAttributes = []
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
        attributes.reserveCapacity(itemCount)

        for item in 0..<itemCount {
            let indexPath = IndexPath(item: item, section: 0)
            let itemAttributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            let lowerFrame = frame(forItemAt: item, metrics: lowerMetrics)
            let upperFrame = frame(forItemAt: item, metrics: upperMetrics)
            itemAttributes.frame = interpolate(from: lowerFrame, to: upperFrame, progress: progress)
            attributes.append(itemAttributes)
        }

        cachedAttributes = attributes
        let contentHeight = attributes.last.map { $0.frame.maxY + sectionInset.bottom } ?? 0
        cachedContentSize = CGSize(width: collectionView.bounds.width, height: contentHeight)
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
        guard indexPath.item >= 0, indexPath.item < cachedAttributes.count else {
            return nil
        }
        return cachedAttributes[indexPath.item]
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

    private func frame(forItemAt item: Int, metrics: Metrics) -> CGRect {
        let row = item / metrics.columns
        let column = item % metrics.columns
        let x = sectionInset.left + CGFloat(column) * (metrics.itemSize.width + itemSpacing)
        let y = sectionInset.top + CGFloat(row) * (metrics.itemSize.height + lineSpacing)
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
