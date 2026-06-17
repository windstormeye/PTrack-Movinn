//
//  WorkoutRouteGridView.swift
//  PTrack
//
//  Created by Codex on 2026/6/17.
//

import UIKit

struct WorkoutRouteGridItem {
    enum Content {
        case route(TrackedWorkout, showsMap: Bool, showsNewBadge: Bool)
        case loading(id: UUID, title: String)
    }

    let content: Content

    static func route(
        _ workout: TrackedWorkout,
        showsMap: Bool,
        showsNewBadge: Bool = false
    ) -> WorkoutRouteGridItem {
        WorkoutRouteGridItem(content: .route(workout, showsMap: showsMap, showsNewBadge: showsNewBadge))
    }

    static func loading(id: UUID, title: String) -> WorkoutRouteGridItem {
        WorkoutRouteGridItem(content: .loading(id: id, title: title))
    }
}

final class WorkoutRouteGridView: UIView {
    let collectionView: UICollectionView

    var numberOfItemsProvider: () -> Int = { 0 }
    var itemProvider: (Int) -> WorkoutRouteGridItem? = { _ in nil }
    var onSelectRoute: ((TrackedWorkout, IndexPath, WorkoutRouteCell?) -> Void)?
    var onScroll: ((UIScrollView) -> Void)?
    var onEndDragging: ((UIScrollView, Bool) -> Void)?
    var onEndDecelerating: ((UIScrollView) -> Void)?
    var onColumnSnapFinished: (() -> Void)?
    var contextMenuConfigurationProvider: ((TrackedWorkout, IndexPath) -> UIContextMenuConfiguration?)?

    var columnCount: CGFloat {
        gridLayout.columns
    }

    private let gridLayout = WorkoutGridLayout()
    private var pinchStartColumnCount: CGFloat = 3
    private var pinchAnchorIndexPath: IndexPath?
    private var pinchAnchorUnitPoint = CGPoint(x: 0.5, y: 0.5)
    private var columnSnapDisplayLink: CADisplayLink?
    private var columnSnapStartTime: CFTimeInterval = 0
    private var columnSnapStartCount: CGFloat = 3
    private var columnSnapTargetCount: CGFloat = 3
    private var columnSnapVisibleAnchorPoint = CGPoint.zero
    private var minimumColumnCount: CGFloat = 2
    private var maximumColumnCount: CGFloat = 6

    private let pinchResponse: CGFloat = 0.86
    private let pinchUpdateThreshold: CGFloat = 0.006
    private let columnSnapDuration: CFTimeInterval = 0.28

    override init(frame: CGRect) {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)
        super.init(coder: coder)
        configureView()
    }

    deinit {
        columnSnapDisplayLink?.invalidate()
    }

    func configureLayout(
        columns: CGFloat,
        itemSpacing: CGFloat,
        lineSpacing: CGFloat,
        sectionInset: UIEdgeInsets,
        itemAspectRatio: CGFloat = 0.74,
        minimumItemHeight: CGFloat = 72,
        minimumColumns: CGFloat = 2,
        maximumColumns: CGFloat = 6
    ) {
        minimumColumnCount = minimumColumns
        maximumColumnCount = max(minimumColumns, maximumColumns)
        let columns = clampedColumnCount(columns)

        gridLayout.columns = columns
        gridLayout.itemSpacing = itemSpacing
        gridLayout.lineSpacing = lineSpacing
        gridLayout.sectionInset = sectionInset
        gridLayout.itemAspectRatio = itemAspectRatio
        gridLayout.minimumItemHeight = minimumItemHeight
        pinchStartColumnCount = columns
        columnSnapStartCount = columns
        columnSnapTargetCount = columns
    }

    func reloadData() {
        collectionView.reloadData()
    }

    private func configureView() {
        backgroundColor = .clear

        collectionView.backgroundColor = .systemBackground
        collectionView.clipsToBounds = false
        collectionView.layer.masksToBounds = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(WorkoutRouteCell.self, forCellWithReuseIdentifier: WorkoutRouteCell.reuseIdentifier)
        collectionView.register(
            WorkoutRouteGridLoadingCell.self,
            forCellWithReuseIdentifier: WorkoutRouteGridLoadingCell.reuseIdentifier
        )
        collectionView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))

        addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func item(at indexPath: IndexPath) -> WorkoutRouteGridItem? {
        guard indexPath.item >= 0, indexPath.item < numberOfItemsProvider() else {
            return nil
        }

        return itemProvider(indexPath.item)
    }
}

extension WorkoutRouteGridView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        numberOfItemsProvider()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let item = item(at: indexPath) else {
            return collectionView.dequeueReusableCell(
                withReuseIdentifier: WorkoutRouteGridLoadingCell.reuseIdentifier,
                for: indexPath
            )
        }

        switch item.content {
        case .route(let workout, let showsMap, let showsNewBadge):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: WorkoutRouteCell.reuseIdentifier,
                for: indexPath
            )
            if let cell = cell as? WorkoutRouteCell {
                cell.configure(
                    with: workout,
                    columnCount: columnCount,
                    showsMap: showsMap,
                    showsNewBadge: showsNewBadge
                )
            }
            return cell

        case .loading(_, let title):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: WorkoutRouteGridLoadingCell.reuseIdentifier,
                for: indexPath
            )
            if let cell = cell as? WorkoutRouteGridLoadingCell {
                cell.configure(title: title)
            }
            return cell
        }
    }
}

extension WorkoutRouteGridView: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onScroll?(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        onEndDragging?(scrollView, decelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        onEndDecelerating?(scrollView)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = item(at: indexPath),
              case .route(let workout, _, _) = item.content else {
            return
        }

        onSelectRoute?(workout, indexPath, collectionView.cellForItem(at: indexPath) as? WorkoutRouteCell)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let item = item(at: indexPath),
              case .route(let workout, _, _) = item.content else {
            return nil
        }

        return contextMenuConfigurationProvider?(workout, indexPath)
    }
}

extension WorkoutRouteGridView: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let item = item(at: indexPath),
                  case .route(let workout, let showsMap, _) = item.content else {
                continue
            }

            if showsMap,
               let size = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)?.size,
               size.width > 1,
               size.height > 1 {
                WorkoutRouteSnapshotRenderer.cachedSnapshot(
                    for: workout,
                    size: size,
                    showsMap: true,
                    mapStyle: .appDefault,
                    traitCollection: traitCollection
                ) { _ in }
            } else {
                WorkoutRoutePathView.prewarmSource(for: workout)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard let item = item(at: indexPath),
                  case .route(let workout, let showsMap, _) = item.content,
                  !showsMap else {
                continue
            }

            WorkoutRoutePathView.cancelPrewarmSource(for: workout)
        }
    }
}

private extension WorkoutRouteGridView {
    @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopColumnSnap()
            pinchStartColumnCount = columnCount
            collectionView.isScrollEnabled = false
            capturePinchAnchor(at: recognizer.location(in: collectionView))
        case .changed:
            let scaledColumns = pinchStartColumnCount / pow(recognizer.scale, pinchResponse)
            let newColumnCount = clampedColumnCount(scaledColumns)
            guard abs(newColumnCount - columnCount) > pinchUpdateThreshold else { return }
            updateColumnCount(newColumnCount, anchoredAt: recognizer.location(in: collectionView))
        case .ended, .cancelled, .failed:
            let snappedColumnCount = clampedColumnCount(round(columnCount))
            guard abs(snappedColumnCount - columnCount) > pinchUpdateThreshold else {
                syncColumnCountWithoutAnchor(snappedColumnCount)
                finishColumnSnap()
                return
            }
            animateColumnSnap(to: snappedColumnCount, anchoredAt: recognizer.location(in: collectionView))
        default:
            break
        }
    }

    func clampedColumnCount(_ columnCount: CGFloat) -> CGFloat {
        min(max(columnCount, minimumColumnCount), maximumColumnCount)
    }

    func capturePinchAnchor(at location: CGPoint) {
        collectionView.layoutIfNeeded()
        guard let indexPath = collectionView.indexPathForItem(at: location) ?? nearestVisibleIndexPath(to: location),
              let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
            pinchAnchorIndexPath = nil
            pinchAnchorUnitPoint = CGPoint(x: 0.5, y: 0.5)
            return
        }

        let frame = attributes.frame
        pinchAnchorIndexPath = indexPath
        pinchAnchorUnitPoint = CGPoint(
            x: min(max((location.x - frame.minX) / frame.width, 0), 1),
            y: min(max((location.y - frame.minY) / frame.height, 0), 1)
        )
    }

    func nearestVisibleIndexPath(to location: CGPoint) -> IndexPath? {
        collectionView.indexPathsForVisibleItems.min { lhs, rhs in
            let lhsDistance = distance(from: location, toCenterOfItemAt: lhs)
            let rhsDistance = distance(from: location, toCenterOfItemAt: rhs)
            return lhsDistance < rhsDistance
        }
    }

    func distance(from location: CGPoint, toCenterOfItemAt indexPath: IndexPath) -> CGFloat {
        guard let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
            return .greatestFiniteMagnitude
        }

        let dx = location.x - attributes.center.x
        let dy = location.y - attributes.center.y
        return dx * dx + dy * dy
    }

    func updateColumnCount(_ newColumnCount: CGFloat, anchoredAt location: CGPoint) {
        let visibleAnchorPoint = CGPoint(
            x: location.x - collectionView.contentOffset.x,
            y: location.y - collectionView.contentOffset.y
        )
        updateColumnCount(newColumnCount, preservingVisibleAnchor: visibleAnchorPoint)
    }

    func updateColumnCount(_ newColumnCount: CGFloat, preservingVisibleAnchor visibleAnchorPoint: CGPoint) {
        UIView.performWithoutAnimation {
            self.gridLayout.columns = newColumnCount
            self.collectionView.layoutIfNeeded()
            self.restorePinchAnchor(toVisiblePoint: visibleAnchorPoint)
        }
    }

    func animateColumnSnap(to targetColumnCount: CGFloat, anchoredAt location: CGPoint) {
        let visibleAnchorPoint = CGPoint(
            x: location.x - collectionView.contentOffset.x,
            y: location.y - collectionView.contentOffset.y
        )

        guard abs(targetColumnCount - columnCount) > 0.001 else {
            syncColumnCountWithoutAnchor(targetColumnCount)
            finishColumnSnap()
            return
        }

        stopColumnSnap()
        columnSnapStartTime = CACurrentMediaTime()
        columnSnapStartCount = columnCount
        columnSnapTargetCount = targetColumnCount
        columnSnapVisibleAnchorPoint = visibleAnchorPoint

        let displayLink = CADisplayLink(target: self, selector: #selector(handleColumnSnapFrame(_:)))
        displayLink.add(to: .main, forMode: .common)
        columnSnapDisplayLink = displayLink
    }

    func syncColumnCountWithoutAnchor(_ newColumnCount: CGFloat) {
        UIView.performWithoutAnimation {
            self.gridLayout.columns = newColumnCount
            self.collectionView.layoutIfNeeded()
        }
    }

    @objc func handleColumnSnapFrame(_ displayLink: CADisplayLink) {
        let elapsed = displayLink.timestamp - columnSnapStartTime
        let progress = min(max(elapsed / columnSnapDuration, 0), 1)
        let easedProgress = easeOutCubic(CGFloat(progress))
        let currentColumnCount = columnSnapStartCount + (columnSnapTargetCount - columnSnapStartCount) * easedProgress

        updateColumnCount(currentColumnCount, preservingVisibleAnchor: columnSnapVisibleAnchorPoint)

        if progress >= 1 {
            updateColumnCount(columnSnapTargetCount, preservingVisibleAnchor: columnSnapVisibleAnchorPoint)
            finishColumnSnap()
        }
    }

    func finishColumnSnap() {
        stopColumnSnap()
        pinchAnchorIndexPath = nil
        collectionView.isScrollEnabled = true
        onColumnSnapFinished?()
    }

    func stopColumnSnap() {
        columnSnapDisplayLink?.invalidate()
        columnSnapDisplayLink = nil
    }

    func easeOutCubic(_ progress: CGFloat) -> CGFloat {
        let inverse = 1 - min(max(progress, 0), 1)
        return 1 - inverse * inverse * inverse
    }

    func restorePinchAnchor(toVisiblePoint visiblePoint: CGPoint) {
        guard let pinchAnchorIndexPath,
              pinchAnchorIndexPath.item < numberOfItemsProvider(),
              let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: pinchAnchorIndexPath) else {
            return
        }

        let frame = attributes.frame
        let anchorContentPoint = CGPoint(
            x: frame.minX + frame.width * pinchAnchorUnitPoint.x,
            y: frame.minY + frame.height * pinchAnchorUnitPoint.y
        )
        let proposedOffset = CGPoint(
            x: anchorContentPoint.x - visiblePoint.x,
            y: anchorContentPoint.y - visiblePoint.y
        )
        collectionView.contentOffset = clampedContentOffset(proposedOffset)
    }

    func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        let minimumX = -collectionView.contentInset.left
        let minimumY = -collectionView.contentInset.top
        let maximumX = max(minimumX, collectionView.contentSize.width - collectionView.bounds.width + collectionView.contentInset.right)
        let maximumY = max(minimumY, collectionView.contentSize.height - collectionView.bounds.height + collectionView.contentInset.bottom)

        return CGPoint(
            x: min(max(offset.x, minimumX), maximumX),
            y: min(max(offset.y, minimumY), maximumY)
        )
    }
}

private final class WorkoutRouteGridLoadingCell: UICollectionViewCell {
    static let reuseIdentifier = "WorkoutRouteGridLoadingCell"

    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
    }

    func configure(title: String) {
        titleLabel.text = title
        activityIndicator.startAnimating()
    }

    private func configureViews() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        titleLabel.textColor = .secondaryLabel
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textAlignment = .center

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(activityIndicator)
        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -12),

            titleLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10)
        ])
    }
}
