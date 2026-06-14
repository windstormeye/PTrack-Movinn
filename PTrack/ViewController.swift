//
//  ViewController.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import SnapKit
import UIKit

class ViewController: UIViewController {
    private let store = HealthWorkoutStore()
    private let cacheStore = WorkoutCacheStore()
    let newWorkoutBadgeStore = NewWorkoutBadgeStore()
    private let cacheSaveQueue = DispatchQueue(label: "studio.pj.PTrack.cache-save", qos: .utility)
    private let routeSourcePrewarmQueue = DispatchQueue(label: "studio.pj.PTrack.route-source-prewarm", qos: .utility)
    var workouts: [TrackedWorkout] = []
    private var knownWorkoutIDs = Set<String>()
    private var pendingWorkouts: [TrackedWorkout] = []
    private var pendingFlushWorkItem: DispatchWorkItem?
    private var pendingCacheSaveWorkItem: DispatchWorkItem?
    private var totalDistanceMeters: Double = 0
    private var collectionView: UICollectionView!
    private let gridLayout = WorkoutGridLayout()
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let titleAccentLabel = UILabel()
    private let totalDistanceLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let heatmapButton = UIButton(type: .system)
    var columnCount: CGFloat = 3
    private var pinchStartColumnCount: CGFloat = 3
    private let itemSpacing: CGFloat = 12
    private let lineSpacing: CGFloat = 2
    private let headerBottomPadding: CGFloat = 8
    private let sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 16, right: 12)
    private var pinchAnchorIndexPath: IndexPath?
    private var pinchAnchorUnitPoint = CGPoint(x: 0.5, y: 0.5)
    private let pinchResponse: CGFloat = 0.86
    private let pinchUpdateThreshold: CGFloat = 0.006
    private let pendingWorkoutFlushDelay: TimeInterval = 0.35
    private let activeScrollFlushDelay: TimeInterval = 0.45
    private let cacheSaveDebounceDelay: TimeInterval = 1.0
    private var columnSnapDisplayLink: CADisplayLink?
    private var columnSnapStartTime: CFTimeInterval = 0
    private var columnSnapStartCount: CGFloat = 3
    private var columnSnapTargetCount: CGFloat = 3
    private var columnSnapVisibleAnchorPoint = CGPoint.zero
    private let columnSnapDuration: CFTimeInterval = 0.28

    deinit {
        columnSnapDisplayLink?.invalidate()
        pendingFlushWorkItem?.cancel()
        pendingCacheSaveWorkItem?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureCollectionView()
        configureHeaderView()
        configureLoadingIndicator()
        store.progressHandler = { message in
            print("PTrack HealthKit: \(message)")
        }
        loadCachedWorkouts()
        loadHealthWorkouts()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFullScreenInsets()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        updateFullScreenInsets(force: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateFullScreenInsets(force: true)
        DispatchQueue.main.async { [weak self] in
            self?.updateFullScreenInsets(force: true)
        }
    }

    private func configureNavigationItem() {
        title = "Movinn"
        navigationItem.largeTitleDisplayMode = .never
    }

    private func configureCollectionView() {
        view.backgroundColor = .systemBackground

        gridLayout.columns = columnCount
        gridLayout.itemSpacing = itemSpacing
        gridLayout.lineSpacing = lineSpacing
        gridLayout.sectionInset = sectionInset

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: gridLayout)
        collectionView.backgroundColor = .systemBackground
        collectionView.clipsToBounds = false
        collectionView.layer.masksToBounds = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(WorkoutRouteCell.self, forCellWithReuseIdentifier: WorkoutRouteCell.reuseIdentifier)
        collectionView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))

        view.addSubview(collectionView)

        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func configureHeaderView() {
        headerView.isUserInteractionEnabled = true
        headerView.backgroundColor = .white

        let titleFont = UIFont.systemFont(ofSize: 40, weight: .bold)
        titleLabel.text = "Movin"
        titleLabel.font = titleFont
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true

        titleAccentLabel.text = "n"
        titleAccentLabel.font = titleFont
        titleAccentLabel.textColor = AppColors.movinnGreen
        titleAccentLabel.adjustsFontForContentSizeCategory = true

        totalDistanceLabel.textColor = .secondaryLabel
        totalDistanceLabel.font = .systemFont(ofSize: 11, weight: .medium)
        totalDistanceLabel.adjustsFontForContentSizeCategory = true
        totalDistanceLabel.setContentHuggingPriority(.required, for: .horizontal)
        totalDistanceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        totalDistanceLabel.lineBreakMode = .byTruncatingTail

        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.image = UIImage(
            systemName: "map",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
        heatmapButton.configuration = buttonConfiguration
        heatmapButton.tintColor = .label
        heatmapButton.addTarget(self, action: #selector(showHeatmap), for: .touchUpInside)

        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(titleAccentLabel)
        headerView.addSubview(totalDistanceLabel)
        headerView.addSubview(loadingIndicator)
        headerView.addSubview(heatmapButton)

        headerView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(122)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(10)
        }

        titleAccentLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel.snp.trailing).offset(-1)
            make.lastBaseline.equalTo(titleLabel.snp.lastBaseline)
        }

        totalDistanceLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleAccentLabel.snp.trailing).offset(10)
            make.trailing.lessThanOrEqualTo(loadingIndicator.snp.leading).offset(-8)
            make.lastBaseline.equalTo(titleLabel.snp.lastBaseline).offset(-3)
        }

        loadingIndicator.snp.makeConstraints { make in
            make.leading.equalTo(totalDistanceLabel.snp.trailing).offset(8)
            make.centerY.equalTo(totalDistanceLabel)
            make.trailing.lessThanOrEqualTo(heatmapButton.snp.leading).offset(-10)
        }

        heatmapButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalTo(titleLabel)
            make.size.equalTo(36)
        }

        updateTotalDistanceText()
    }

    private func configureLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true
    }

    private func updateFullScreenInsets(force: Bool = false) {
        guard let collectionView else {
            return
        }

        view.layoutIfNeeded()
        let headerMaxY = headerView.convert(headerView.bounds, to: view).maxY

        let contentInset = UIEdgeInsets(top: headerMaxY + headerBottomPadding, left: 0, bottom: 0, right: 0)
        guard force || collectionView.contentInset != contentInset else {
            return
        }

        let oldTopInset = collectionView.contentInset.top
        let oldContentOffsetY = collectionView.contentOffset.y
        let wasAtTop = oldContentOffsetY <= -oldTopInset + 2

        collectionView.contentInset = contentInset
        collectionView.scrollIndicatorInsets = contentInset
        if wasAtTop {
            collectionView.contentOffset.y = -contentInset.top
        }
    }

    private func updateTotalDistanceText() {
        let totalKilometers = totalDistanceMeters / 1000
        totalDistanceLabel.text = "总距离：\(Int(totalKilometers.rounded()))KM"
    }

    private func loadCachedWorkouts() {
        workouts = cacheStore.load()
        knownWorkoutIDs = Set(workouts.map(\.id))
        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        updateTotalDistanceText()
        collectionView.reloadData()
    }

    private func loadHealthWorkouts() {
        loadingIndicator.startAnimating()
        store.requestAuthorization { [weak self] authorizationResult in
            guard let self else { return }
            switch authorizationResult {
            case .success:
                Task { @MainActor in
                    self.loadIncrementalHealthWorkouts()
                }
            case .failure(let error):
                print("PTrack HealthKit: authorization failed: \(error)")
                Task { @MainActor in
                    self.loadingIndicator.stopAnimating()
                }
            }
        }
    }

    private func loadIncrementalHealthWorkouts() {
        let newestCachedDate = workouts.map(\.startDate).max()
        let cachedIDs = knownWorkoutIDs

        store.loadTrackedWorkouts(
            after: newestCachedDate,
            excludingIDs: cachedIDs,
            onTrackedWorkout: { [weak self] trackedWorkout in
                Task { @MainActor in
                    self?.appendTrackedWorkout(trackedWorkout)
                }
            },
            completion: { [weak self] loadResult in
                Task { @MainActor in
                    self?.handleLoadResult(loadResult)
                }
            }
        )
    }

    private func appendTrackedWorkout(_ workout: TrackedWorkout) {
        guard knownWorkoutIDs.insert(workout.id).inserted else {
            return
        }

        pendingWorkouts.append(workout)
        newWorkoutBadgeStore.markIfNeeded(workout)
        prewarmRouteSource(for: workout)
        schedulePendingWorkoutFlush()
    }

    private func schedulePendingWorkoutFlush(delay: TimeInterval? = nil) {
        guard pendingFlushWorkItem == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingWorkouts()
        }
        pendingFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (delay ?? pendingWorkoutFlushDelay),
            execute: workItem
        )
    }

    @discardableResult
    func flushPendingWorkouts(force: Bool = false) -> Bool {
        pendingFlushWorkItem?.cancel()
        pendingFlushWorkItem = nil

        guard !pendingWorkouts.isEmpty else {
            return false
        }

        if !force, isCollectionViewBusy {
            schedulePendingWorkoutFlush(delay: activeScrollFlushDelay)
            return false
        }

        let incomingWorkouts = pendingWorkouts
        pendingWorkouts.removeAll()

        workouts.append(contentsOf: incomingWorkouts)
        workouts.sort { $0.startDate > $1.startDate }
        totalDistanceMeters += incomingWorkouts.reduce(0) { $0 + $1.distanceMeters }
        updateTotalDistanceText()

        UIView.performWithoutAnimation {
            collectionView.reloadData()
        }
        scheduleCacheSave()
        return true
    }

    private var isCollectionViewBusy: Bool {
        collectionView.isTracking
            || collectionView.isDragging
            || collectionView.isDecelerating
            || !collectionView.isScrollEnabled
            || columnSnapDisplayLink != nil
    }

    private func scheduleCacheSave(delay: TimeInterval? = nil) {
        pendingCacheSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let cachedWorkouts = self.workouts
            self.cacheSaveQueue.async { [cacheStore = self.cacheStore] in
                cacheStore.save(cachedWorkouts)
            }
        }
        pendingCacheSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay ?? cacheSaveDebounceDelay), execute: workItem)
    }

    private func prewarmRouteSource(for workout: TrackedWorkout) {
        routeSourcePrewarmQueue.async {
            WorkoutRoutePathView.prewarmSource(for: workout)
        }
    }

    private func handleLoadResult(_ result: Result<Int, Error>) {
        loadingIndicator.stopAnimating()
        let didFlushPendingWorkouts = flushPendingWorkouts()
        switch result {
        case .success(let count):
            print("PTrack HealthKit: incremental route query completed, new routes: \(count)")
            newWorkoutBadgeStore.markInitialSyncCompleted()
        case .failure(let error):
            print("PTrack HealthKit: route query failed: \(error)")
        }
        if didFlushPendingWorkouts {
            scheduleCacheSave(delay: 0)
        }
    }

    @objc private func showHeatmap() {
        flushPendingWorkouts(force: true)
        let heatmapViewController = WorkoutRouteHeatmapViewController(workouts: workouts)
        navigationController?.pushViewController(heatmapViewController, animated: true)
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopColumnSnap()
            pinchStartColumnCount = columnCount
            collectionView.isScrollEnabled = false
            capturePinchAnchor(at: recognizer.location(in: collectionView))
        case .changed:
            let scaledColumns = pinchStartColumnCount / pow(recognizer.scale, pinchResponse)
            let newColumnCount = min(max(scaledColumns, 2), 6)
            guard abs(newColumnCount - columnCount) > pinchUpdateThreshold else { return }
            updateColumnCount(newColumnCount, anchoredAt: recognizer.location(in: collectionView))
        case .ended, .cancelled, .failed:
            let snappedColumnCount = min(max(round(columnCount), 2), 6)
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

    private func capturePinchAnchor(at location: CGPoint) {
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

    private func nearestVisibleIndexPath(to location: CGPoint) -> IndexPath? {
        collectionView.indexPathsForVisibleItems.min { lhs, rhs in
            let lhsDistance = distance(from: location, toCenterOfItemAt: lhs)
            let rhsDistance = distance(from: location, toCenterOfItemAt: rhs)
            return lhsDistance < rhsDistance
        }
    }

    private func distance(from location: CGPoint, toCenterOfItemAt indexPath: IndexPath) -> CGFloat {
        guard let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath) else {
            return .greatestFiniteMagnitude
        }

        let dx = location.x - attributes.center.x
        let dy = location.y - attributes.center.y
        return dx * dx + dy * dy
    }

    private func updateColumnCount(_ newColumnCount: CGFloat, anchoredAt location: CGPoint) {
        let visibleAnchorPoint = CGPoint(
            x: location.x - collectionView.contentOffset.x,
            y: location.y - collectionView.contentOffset.y
        )
        updateColumnCount(newColumnCount, preservingVisibleAnchor: visibleAnchorPoint)
    }

    private func updateColumnCount(_ newColumnCount: CGFloat, preservingVisibleAnchor visibleAnchorPoint: CGPoint) {
        columnCount = newColumnCount

        UIView.performWithoutAnimation {
            self.gridLayout.columns = newColumnCount
            self.collectionView.layoutIfNeeded()
            self.restorePinchAnchor(toVisiblePoint: visibleAnchorPoint)
        }
    }

    private func animateColumnSnap(to targetColumnCount: CGFloat, anchoredAt location: CGPoint) {
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

    private func syncColumnCountWithoutAnchor(_ newColumnCount: CGFloat) {
        columnCount = newColumnCount
        UIView.performWithoutAnimation {
            self.gridLayout.columns = newColumnCount
            self.collectionView.layoutIfNeeded()
        }
    }

    @objc private func handleColumnSnapFrame(_ displayLink: CADisplayLink) {
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

    private func finishColumnSnap() {
        stopColumnSnap()
        pinchAnchorIndexPath = nil
        collectionView.isScrollEnabled = true
        flushPendingWorkouts()
    }

    private func stopColumnSnap() {
        columnSnapDisplayLink?.invalidate()
        columnSnapDisplayLink = nil
    }

    private func easeOutCubic(_ progress: CGFloat) -> CGFloat {
        let inverse = 1 - min(max(progress, 0), 1)
        return 1 - inverse * inverse * inverse
    }

    private func restorePinchAnchor(toVisiblePoint visiblePoint: CGPoint) {
        guard let pinchAnchorIndexPath,
              pinchAnchorIndexPath.item < workouts.count,
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

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
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
