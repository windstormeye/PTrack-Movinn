//
//  ViewController.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import AuthenticationServices
import SnapKit
import HealthKit
import UIKit

class ViewController: UIViewController {
    private let store = HealthWorkoutStore()
    private let cacheStore = WorkoutCacheStore()
    let newWorkoutBadgeStore = NewWorkoutBadgeStore()
    private let cacheLoadQueue = DispatchQueue(label: "studio.pj.PTrack.cache-load", qos: .userInitiated)
    private let cacheSaveQueue = DispatchQueue(label: "studio.pj.PTrack.cache-save", qos: .utility)
    private let routeSourcePrewarmQueue = DispatchQueue(label: "studio.pj.PTrack.route-source-prewarm", qos: .utility)
    var workouts: [TrackedWorkout] = []
    private var knownWorkoutIDs = Set<String>()
    private var pendingWorkouts: [TrackedWorkout] = []
    private var pendingFlushWorkItem: DispatchWorkItem?
    private var pendingCacheSaveWorkItem: DispatchWorkItem?
    private var dirtyCacheWorkoutIDs = Set<String>()
    private var deletedCacheWorkoutIDs = Set<String>()
    private var isCacheSaveInProgress = false
    private var needsCacheSaveAfterCurrentSave = false
    private var totalDistanceMeters: Double = 0
    private var activeLoadingOperationCount = 0
    private var isCacheLoadInProgress = false
    private var isHealthSyncInProgress = false
    private var isStravaSyncInProgress = false
    private var isPullRefreshArmedInCurrentDrag = false
    private var collectionView: UICollectionView!
    private let gridLayout = WorkoutGridLayout()
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let titleAccentLabel = UILabel()
    private let totalDistanceLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let moreButton = UIButton(type: .system)
    private let emptyDataSourceView = HomeDataSourceEmptyView()
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
    private let cacheLoadPreviewBatchSize = 32
    private let stravaIncrementalLookback: TimeInterval = 7 * 24 * 60 * 60
    private let pullRefreshTriggerDistance: CGFloat = 86
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
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureCollectionView()
        configureHeaderView()
        configureEmptyDataSourceView()
        configureLoadingIndicator()
        registerLanguageObserver()
        registerStravaImportObserver()
        store.progressHandler = { message in
            print("PTrack HealthKit: \(message)")
        }
        loadCachedWorkoutsThenSynchronize()
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
            systemName: "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
        moreButton.configuration = buttonConfiguration
        moreButton.tintColor = .label
        moreButton.addTarget(self, action: #selector(handleHeaderMoreButtonTap), for: .touchUpInside)
        updateHeaderMoreButtonMode()

        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(titleAccentLabel)
        headerView.addSubview(totalDistanceLabel)
        headerView.addSubview(loadingIndicator)
        headerView.addSubview(moreButton)

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
            make.trailing.lessThanOrEqualTo(moreButton.snp.leading).offset(-10)
        }

        moreButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalTo(titleLabel)
            make.size.equalTo(36)
        }

        updateTotalDistanceText()
    }

    private func makeHeaderMoreMenu() -> UIMenu {
        let sportsCareerAction = UIAction(
            title: AppLocalization.text(.sportsCareer),
            image: UIImage(systemName: "chart.bar")
        ) { [weak self] _ in
            self?.showSportsCareer()
        }

        let heatmapAction = UIAction(
            title: AppLocalization.text(.routeHeatmap),
            image: UIImage(systemName: "map")
        ) { [weak self] _ in
            self?.showHeatmap()
        }

        let moreAction = UIAction(
            title: AppLocalization.text(.more),
            image: UIImage(systemName: "ellipsis")
        ) { [weak self] _ in
            self?.showMoreSettings()
        }

        return UIMenu(children: [sportsCareerAction, heatmapAction, moreAction])
    }

    private func updateHeaderMoreButtonMode() {
        if hasReadableDataSourceAuthorization {
            moreButton.menu = makeHeaderMoreMenu()
            moreButton.showsMenuAsPrimaryAction = true
        } else {
            moreButton.menu = nil
            moreButton.showsMenuAsPrimaryAction = false
        }
    }

    @objc private func handleHeaderMoreButtonTap() {
        guard !hasReadableDataSourceAuthorization else {
            return
        }

        showMoreSettings()
    }

    private func configureLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true
        updateHeaderReadAuthorizationState()
    }

    private func configureEmptyDataSourceView() {
        emptyDataSourceView.onAppleHealthTap = { [weak self] in
            self?.handleEmptyAppleHealthSelection()
        }
        emptyDataSourceView.onStravaTap = { [weak self] in
            self?.handleEmptyStravaSelection()
        }
        emptyDataSourceView.isHidden = true

        view.addSubview(emptyDataSourceView)

        emptyDataSourceView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.equalToSuperview().offset(-48).priority(.high)
            make.width.lessThanOrEqualTo(360)
            make.centerY.equalTo(view.safeAreaLayoutGuide.snp.centerY).offset(42)
            make.top.greaterThanOrEqualTo(headerView.snp.bottom).offset(36)
        }

        updateEmptyDataSourceVisibility()
    }

    private func beginLoadingOperation() {
        activeLoadingOperationCount += 1
        updateHeaderReadAuthorizationState()
        updateEmptyDataSourceVisibility()
    }

    private func endLoadingOperation() {
        activeLoadingOperationCount = max(activeLoadingOperationCount - 1, 0)
        updateHeaderReadAuthorizationState()
        updateEmptyDataSourceVisibility()
    }

    private var hasReadableDataSourceAuthorization: Bool {
        store.authorizationState == .authorized || StravaManager.shared.hasStoredAuthorization
    }

    private func updateHeaderReadAuthorizationState() {
        totalDistanceLabel.isHidden = !hasReadableDataSourceAuthorization
        updateLoadingIndicatorVisibility()
        updateHeaderMoreButtonMode()
    }

    private func updateLoadingIndicatorVisibility() {
        if activeLoadingOperationCount > 0, hasReadableDataSourceAuthorization {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
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

    func synchronizeDataSourcesForAppOpen() {
        updateHeaderReadAuthorizationState()

        if store.authorizationState == .authorized {
            loadAuthorizedHealthWorkouts()
        } else {
            print("PTrack HealthKit: skipped import, no stored authorization")
        }
        loadAuthorizedStravaWorkouts()
    }

    func updatePullRefreshTracking(for scrollView: UIScrollView) {
        guard scrollView.isDragging,
              !isDataSourceSyncInProgress else {
            isPullRefreshArmedInCurrentDrag = false
            return
        }

        let pullDistance = max(-(scrollView.contentOffset.y + scrollView.contentInset.top), 0)
        isPullRefreshArmedInCurrentDrag = pullDistance >= pullRefreshTriggerDistance
    }

    func performPullRefreshIfNeeded() {
        guard isPullRefreshArmedInCurrentDrag,
              !isDataSourceSyncInProgress else {
            isPullRefreshArmedInCurrentDrag = false
            return
        }

        isPullRefreshArmedInCurrentDrag = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        synchronizeDataSourcesForAppOpen()
    }

    func finishPullRefreshTracking() {
        isPullRefreshArmedInCurrentDrag = false
    }

    private var isDataSourceSyncInProgress: Bool {
        isCacheLoadInProgress || isHealthSyncInProgress || isStravaSyncInProgress
    }

    private func updateTotalDistanceText() {
        let totalKilometers = totalDistanceMeters / 1000
        let prefixText = AppLocalization.text(.activitySummaryPrefix)
        let distanceText = AppLocalization.format(.totalDistanceFormat, Int(totalKilometers.rounded()))
        let activityCountText = AppLocalization.format(.totalActivityCountFormat, workouts.count)
        totalDistanceLabel.text = "\(prefixText) \(distanceText)/\(activityCountText)"
        updateHeaderReadAuthorizationState()
        updateEmptyDataSourceVisibility()
    }

    private func updateEmptyDataSourceVisibility() {
        emptyDataSourceView.isHidden = !workouts.isEmpty || hasReadableDataSourceAuthorization
    }

    private func registerLanguageObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageDidChange),
            name: AppLanguageStore.languageDidChangeNotification,
            object: nil
        )
    }

    @objc private func handleLanguageDidChange() {
        updateTotalDistanceText()
        emptyDataSourceView.updateLocalizedText()
        updateHeaderMoreButtonMode()
        collectionView.reloadData()
    }

    private func registerStravaImportObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStravaTrackedWorkoutsDidImport(_:)),
            name: StravaManager.trackedWorkoutsDidImportNotification,
            object: nil
        )
    }

    @objc private func handleStravaTrackedWorkoutsDidImport(_ notification: Notification) {
        guard let importedWorkouts = notification.object as? [TrackedWorkout],
              !importedWorkouts.isEmpty else {
            return
        }

        for workout in importedWorkouts {
            upsertTrackedWorkout(workout)
        }
        flushPendingWorkouts(force: true)
        scheduleCacheSave(delay: 0)
    }

    private func loadCachedWorkoutsThenSynchronize() {
        isCacheLoadInProgress = true
        beginLoadingOperation()
        cacheLoadQueue.async { [weak self] in
            guard let self else {
                return
            }

            let cachedWorkouts = self.cacheStore.load(
                batchSize: self.cacheLoadPreviewBatchSize,
                onBatch: { [weak self] cachedWorkoutBatch in
                    DispatchQueue.main.async { [weak self] in
                        self?.appendCachedWorkoutBatch(cachedWorkoutBatch)
                    }
                }
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.applyCachedWorkouts(cachedWorkouts)
                self.isCacheLoadInProgress = false
                self.endLoadingOperation()
                self.synchronizeDataSourcesForAppOpen()
            }
        }
    }

    private func appendCachedWorkoutBatch(_ cachedWorkoutBatch: [TrackedWorkout]) {
        guard isCacheLoadInProgress, !cachedWorkoutBatch.isEmpty else {
            return
        }

        var didAppendWorkout = false
        for workout in cachedWorkoutBatch where knownWorkoutIDs.insert(workout.id).inserted {
            workouts.append(workout)
            totalDistanceMeters += workout.distanceMeters
            didAppendWorkout = true
        }

        guard didAppendWorkout else {
            return
        }

        workouts.sort { $0.startDate > $1.startDate }
        updateTotalDistanceText()
        UIView.performWithoutAnimation {
            collectionView.reloadData()
        }
    }

    private func applyCachedWorkouts(_ cachedWorkouts: [TrackedWorkout]) {
        workouts = cachedWorkouts
        removeCachedAppleHealthWorkoutsConflictingWithStrava()
        knownWorkoutIDs = Set(workouts.map(\.id))
        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        updateTotalDistanceText()
        collectionView.reloadData()
        prewarmInitialRouteSources()
    }

    private func loadAuthorizedHealthWorkouts() {
        guard !isHealthSyncInProgress else {
            return
        }

        isHealthSyncInProgress = true
        beginLoadingOperation()
        loadIncrementalHealthWorkouts()
    }

    private func requestHealthAuthorizationAndLoadWorkouts() {
        guard !isHealthSyncInProgress else {
            return
        }

        isHealthSyncInProgress = true
        store.requestAuthorization { [weak self] authorizationResult in
            guard let self else { return }
            switch authorizationResult {
            case .success:
                Task { @MainActor in
                    self.beginLoadingOperation()
                    self.loadIncrementalHealthWorkouts()
                }
            case .failure(let error):
                print("PTrack HealthKit: authorization failed: \(error)")
                Task { @MainActor in
                    self.isHealthSyncInProgress = false
                    self.updateHeaderReadAuthorizationState()
                }
            }
        }
    }

    private func loadAuthorizedStravaWorkouts() {
        guard StravaManager.shared.hasStoredAuthorization else {
            print("PTrack Strava: skipped import, no stored authorization")
            updateHeaderReadAuthorizationState()
            return
        }

        let latestStartDate = latestStravaStartDateForIncrementalSync()
        print(
            "PTrack Strava: authorized import requested, latest incremental start: \(Self.debugDateString(latestStartDate)), cached Strava activities: \(workouts.compactMap(\.stravaActivityID).count)"
        )
        loadStravaWorkouts(
            excludingStravaActivityIDs: Set(workouts.compactMap(\.stravaActivityID)),
            after: latestStartDate,
            presentsErrors: false
        )
    }

    private func loadStravaWorkouts(
        excludingStravaActivityIDs: Set<Int64>,
        after startDate: Date? = nil,
        presentsErrors: Bool
    ) {
        guard !isStravaSyncInProgress else {
            return
        }

        isStravaSyncInProgress = true
        beginLoadingOperation()
        print(
            "PTrack Strava: starting import, after: \(Self.debugDateString(startDate)), excluding cached activities: \(excludingStravaActivityIDs.count)"
        )

        Task { [weak self] in
            do {
                let importedWorkouts = try await StravaManager.shared.loadTrackedWorkouts(
                    after: startDate,
                    excludingStravaActivityIDs: excludingStravaActivityIDs,
                    onTrackedWorkout: { [weak self] workout in
                        await MainActor.run {
                            guard let self else {
                                return
                            }

                            self.upsertTrackedWorkout(workout)
                            if self.flushPendingWorkouts() {
                                print("PTrack Strava: streamed workout to home list: \(workout.id)")
                            }
                        }
                    }
                )

                guard let self else {
                    return
                }

                let didFlushPendingWorkouts = self.flushPendingWorkouts(force: true)
                if !importedWorkouts.isEmpty {
                    self.scheduleCacheSave(delay: 0)
                    print("PTrack Strava: scheduled cache save for imported routes: \(importedWorkouts.count)")
                }

                print(
                    "PTrack Strava: import completed, loaded routes: \(importedWorkouts.count), flushed: \(didFlushPendingWorkouts)"
                )
                self.isStravaSyncInProgress = false
                self.endLoadingOperation()
            } catch {
                guard let self else {
                    return
                }

                print("PTrack Strava: import failed: \(error)")
                self.isStravaSyncInProgress = false
                self.endLoadingOperation()
                self.updateHeaderReadAuthorizationState()
                if StravaManager.requiresReauthorization(error) {
                    self.presentSimpleAlert(
                        title: AppLocalization.text(.strava),
                        message: AppLocalization.text(.stravaReauthorizationRequired)
                    )
                } else if presentsErrors {
                    self.presentSimpleAlert(title: AppLocalization.text(.strava), message: error.localizedDescription)
                }
            }
        }
    }

    private func latestStravaStartDateForIncrementalSync() -> Date? {
        let latestStartDate = workouts
            .filter { $0.stravaActivityID != nil }
            .map(\.startDate)
            .max()

        return latestStartDate?.addingTimeInterval(-stravaIncrementalLookback)
    }

    private static func debugDateString(_ date: Date?) -> String {
        guard let date else {
            return "nil"
        }

        return ISO8601DateFormatter().string(from: date)
    }

    private func loadIncrementalHealthWorkouts() {
        let cachedIDs = knownWorkoutIDs
        let staleWorkouts = workouts.filter(\.needsHealthDataRefresh)
        let staleWorkoutIDs = Set(staleWorkouts.map(\.id))
        let queryStartDate = staleWorkouts.map(\.startDate).min() ?? workouts.map(\.startDate).max()
        let excludedIDs = cachedIDs.subtracting(staleWorkoutIDs)

        if !staleWorkouts.isEmpty {
            print("PTrack HealthKit: refreshing \(staleWorkouts.count) cached workouts for expanded health data")
        }

        store.loadTrackedWorkouts(
            after: queryStartDate,
            excludingIDs: excludedIDs,
            onTrackedWorkout: { [weak self] trackedWorkout in
                Task { @MainActor in
                    self?.upsertTrackedWorkout(trackedWorkout)
                }
            },
            completion: { [weak self] loadResult in
                Task { @MainActor in
                    self?.handleLoadResult(loadResult)
                }
            }
        )
    }

    private func upsertTrackedWorkout(_ workout: TrackedWorkout) {
        if shouldSkipForStravaPrecedence(workout) {
            return
        }

        removeAppleHealthConflictsIfNeeded(for: workout)

        if let existingIndex = workouts.firstIndex(where: { $0.id == workout.id }) {
            workouts[existingIndex] = workout
            knownWorkoutIDs.insert(workout.id)
            totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
            updateTotalDistanceText()
            prewarmRouteSource(for: workout)
            markCacheDirty(workout.id)
            scheduleCacheSave()
            return
        }

        appendTrackedWorkout(workout)
    }

    private func shouldSkipForStravaPrecedence(_ workout: TrackedWorkout) -> Bool {
        guard !workout.isStravaSource,
              let stravaWorkout = firstStravaConflict(for: workout) else {
            return false
        }

        print(
            "PTrack Sync: skipped Apple Health workout \(workout.id) because Strava workout \(stravaWorkout.id) has precedence"
        )
        return true
    }

    private func firstStravaConflict(for workout: TrackedWorkout) -> TrackedWorkout? {
        (workouts + pendingWorkouts).first { candidate in
            candidate.isStravaSource && candidate.isSamePhysicalWorkout(as: workout)
        }
    }

    private func removeAppleHealthConflictsIfNeeded(for workout: TrackedWorkout) {
        guard workout.isStravaSource else {
            return
        }

        var removedWorkouts: [TrackedWorkout] = []
        workouts.removeAll { candidate in
            guard !candidate.isStravaSource,
                  candidate.isSamePhysicalWorkout(as: workout) else {
                return false
            }

            removedWorkouts.append(candidate)
            return true
        }

        pendingWorkouts.removeAll { candidate in
            guard !candidate.isStravaSource,
                  candidate.isSamePhysicalWorkout(as: workout) else {
                return false
            }

            removedWorkouts.append(candidate)
            return true
        }

        guard !removedWorkouts.isEmpty else {
            return
        }

        for removedWorkout in removedWorkouts {
            knownWorkoutIDs.remove(removedWorkout.id)
            newWorkoutBadgeStore.markSeen(removedWorkout)
            markCacheDeleted(removedWorkout.id)
        }

        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        updateTotalDistanceText()
        UIView.performWithoutAnimation {
            collectionView.reloadData()
        }
        scheduleCacheSave(delay: 0)

        print(
            "PTrack Sync: removed \(removedWorkouts.count) Apple Health duplicate(s) because Strava workout \(workout.id) has precedence"
        )
    }

    private func removeCachedAppleHealthWorkoutsConflictingWithStrava() {
        let stravaWorkouts = workouts.filter(\.isStravaSource)
        guard !stravaWorkouts.isEmpty else {
            return
        }

        var removedCount = 0
        workouts.removeAll { workout in
            guard !workout.isStravaSource else {
                return false
            }

            let hasStravaConflict = stravaWorkouts.contains { $0.isSamePhysicalWorkout(as: workout) }
            if hasStravaConflict {
                removedCount += 1
                newWorkoutBadgeStore.markSeen(workout)
                markCacheDeleted(workout.id)
            }
            return hasStravaConflict
        }

        guard removedCount > 0 else {
            return
        }

        print("PTrack Sync: removed \(removedCount) cached Apple Health duplicate(s) because Strava has precedence")
        scheduleCacheSave(delay: 0)
    }

    private func appendTrackedWorkout(_ workout: TrackedWorkout) {
        guard knownWorkoutIDs.insert(workout.id).inserted else {
            return
        }

        pendingWorkouts.append(workout)
        newWorkoutBadgeStore.markIfNeeded(workout)
        prewarmRouteSource(for: workout)
        markCacheDirty(workout.id)
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

    private func markCacheDirty(_ workoutID: String) {
        guard !workoutID.isEmpty else {
            return
        }

        dirtyCacheWorkoutIDs.insert(workoutID)
        deletedCacheWorkoutIDs.remove(workoutID)
    }

    private func markCacheDeleted(_ workoutID: String) {
        guard !workoutID.isEmpty else {
            return
        }

        dirtyCacheWorkoutIDs.remove(workoutID)
        deletedCacheWorkoutIDs.insert(workoutID)
    }

    private func scheduleCacheSave(delay: TimeInterval? = nil) {
        pendingCacheSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.performCacheSave()
        }
        pendingCacheSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay ?? cacheSaveDebounceDelay), execute: workItem)
    }

    private func performCacheSave() {
        if isCacheSaveInProgress {
            needsCacheSaveAfterCurrentSave = true
            return
        }

        let dirtyWorkoutIDs = dirtyCacheWorkoutIDs
        let deletedWorkoutIDs = deletedCacheWorkoutIDs
        guard !dirtyWorkoutIDs.isEmpty || !deletedWorkoutIDs.isEmpty else {
            return
        }

        dirtyCacheWorkoutIDs.subtract(dirtyWorkoutIDs)
        deletedCacheWorkoutIDs.subtract(deletedWorkoutIDs)
        isCacheSaveInProgress = true

        let cachedWorkouts = workouts
        cacheSaveQueue.async { [cacheStore = self.cacheStore] in
            let didSave = cacheStore.saveIncremental(
                cachedWorkouts,
                dirtyWorkoutIDs: dirtyWorkoutIDs,
                deletedWorkoutIDs: deletedWorkoutIDs
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.isCacheSaveInProgress = false
                if !didSave {
                    self.restoreUncommittedCacheChanges(
                        dirtyWorkoutIDs: dirtyWorkoutIDs,
                        deletedWorkoutIDs: deletedWorkoutIDs
                    )
                }

                let shouldScheduleNextSave = self.needsCacheSaveAfterCurrentSave
                    || !self.dirtyCacheWorkoutIDs.isEmpty
                    || !self.deletedCacheWorkoutIDs.isEmpty
                self.needsCacheSaveAfterCurrentSave = false

                if shouldScheduleNextSave {
                    self.scheduleCacheSave(delay: 0)
                }
            }
        }
    }

    private func restoreUncommittedCacheChanges(
        dirtyWorkoutIDs: Set<String>,
        deletedWorkoutIDs: Set<String>
    ) {
        for workoutID in dirtyWorkoutIDs where !deletedCacheWorkoutIDs.contains(workoutID) {
            dirtyCacheWorkoutIDs.insert(workoutID)
        }

        for workoutID in deletedWorkoutIDs {
            dirtyCacheWorkoutIDs.remove(workoutID)
            deletedCacheWorkoutIDs.insert(workoutID)
        }
    }

    private func prewarmRouteSource(for workout: TrackedWorkout) {
        routeSourcePrewarmQueue.async {
            WorkoutRoutePathView.prewarmSource(for: workout)
        }
    }

    private func prewarmInitialRouteSources() {
        let initialPrewarmCount = min(workouts.count, 72)
        guard initialPrewarmCount > 0 else {
            return
        }

        let initialWorkouts = Array(workouts.prefix(initialPrewarmCount))
        routeSourcePrewarmQueue.async {
            for workout in initialWorkouts {
                WorkoutRoutePathView.prewarmSource(for: workout)
            }
        }
    }

    private func handleLoadResult(_ result: Result<Int, Error>) {
        isHealthSyncInProgress = false
        endLoadingOperation()
        updateHeaderReadAuthorizationState()
        let didFlushPendingWorkouts = flushPendingWorkouts()
        switch result {
        case .success(let count):
            print("PTrack HealthKit: route query completed, loaded routes: \(count)")
            newWorkoutBadgeStore.markInitialSyncCompleted()
        case .failure(let error):
            print("PTrack HealthKit: route query failed: \(error)")
        }
        if didFlushPendingWorkouts {
            scheduleCacheSave(delay: 0)
        }
    }

    private func showHeatmap() {
        flushPendingWorkouts(force: true)
        let heatmapViewController = WorkoutRouteHeatmapViewController(workouts: workouts)
        navigationController?.pushViewController(heatmapViewController, animated: true)
    }

    private func showSportsCareer() {
        flushPendingWorkouts(force: true)
        let sportsCareerViewController = SportsCareerViewController(workouts: workouts)
        navigationController?.pushViewController(sportsCareerViewController, animated: true)
    }

    private func showMoreSettings() {
        let moreSettingsViewController = MoreSettingsViewController()
        moreSettingsViewController.existingStravaActivityIDsProvider = { [weak self] in
            Set(self?.workouts.compactMap(\.stravaActivityID) ?? [])
        }
        moreSettingsViewController.stravaAuthorizationCompletion = { [weak self] excludedActivityIDs in
            self?.loadStravaWorkouts(
                excludingStravaActivityIDs: excludedActivityIDs,
                presentsErrors: true
            )
        }
        navigationController?.pushViewController(moreSettingsViewController, animated: true)
    }

    private func handleEmptyAppleHealthSelection() {
        requestHealthAuthorizationAndLoadWorkouts()
    }

    private func handleEmptyStravaSelection() {
        guard !isStravaSyncInProgress else {
            return
        }

        let excludedActivityIDs = Set(workouts.compactMap(\.stravaActivityID))
        if StravaManager.shared.hasStoredAuthorization {
            loadStravaWorkouts(
                excludingStravaActivityIDs: excludedActivityIDs,
                presentsErrors: true
            )
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                _ = try await StravaManager.shared.authorize(presentationContextProvider: self)
                self.loadStravaWorkouts(
                    excludingStravaActivityIDs: excludedActivityIDs,
                    presentsErrors: true
                )
            } catch {
                guard (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin else {
                    return
                }
                self.presentSimpleAlert(title: AppLocalization.text(.strava), message: error.localizedDescription)
            }
        }
    }

    private func presentSimpleAlert(title: String, message: String?) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .default))
        present(alertController, animated: true)
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

extension ViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = view.window {
            return window
        }

        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first

        return ASPresentationAnchor(windowScene: windowScene!)
    }
}

private final class HomeDataSourceEmptyView: UIView {
    var onAppleHealthTap: (() -> Void)?
    var onStravaTap: (() -> Void)?

    private let stackView = UIStackView()
    private let appleHealthCard = HomeDataSourceCardView(style: .appleHealth)
    private let stravaCard = HomeDataSourceCardView(style: .strava)
    private let privacyLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        updateLocalizedText()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
        updateLocalizedText()
    }

    func updateLocalizedText() {
        appleHealthCard.configure(
            title: AppLocalization.text(.appleHealth),
            subtitle: AppLocalization.text(.appleHealthDataSourceSubtitle)
        )
        stravaCard.configure(
            title: AppLocalization.text(.strava),
            subtitle: AppLocalization.text(.stravaDataSourceSubtitle)
        )
        privacyLabel.text = AppLocalization.text(.movinnLocalDataPrivacyStatement)
    }

    private func configureViews() {
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12

        privacyLabel.textColor = .secondaryLabel
        privacyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        privacyLabel.numberOfLines = 0
        privacyLabel.textAlignment = .center

        appleHealthCard.addAction(UIAction { [weak self] _ in
            self?.onAppleHealthTap?()
        }, for: .touchUpInside)
        stravaCard.addAction(UIAction { [weak self] _ in
            self?.onStravaTap?()
        }, for: .touchUpInside)

        addSubview(stackView)
        stackView.addArrangedSubview(appleHealthCard)
        stackView.addArrangedSubview(stravaCard)
        stackView.setCustomSpacing(16, after: stravaCard)
        stackView.addArrangedSubview(privacyLabel)

        stackView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview()
        }

        appleHealthCard.snp.makeConstraints { make in
            make.height.equalTo(76)
        }
        stravaCard.snp.makeConstraints { make in
            make.height.equalTo(76)
        }
    }
}

private final class HomeDataSourceCardView: UIControl {
    enum Style {
        case appleHealth
        case strava
    }

    private let style: Style
    private let iconView = UIImageView()
    private let brandImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textStackView = UIStackView()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        configureViews()
    }

    required init?(coder: NSCoder) {
        style = .appleHealth
        super.init(coder: coder)
        configureViews()
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14) {
                self.alpha = self.isHighlighted ? 0.72 : 1
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
            }
        }
    }

    func configure(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }

    private func configureViews() {
        layer.cornerRadius = 12
        layer.masksToBounds = true
        backgroundColor = style == .strava ? AppColors.stravaOrange : UIColor(white: 0.945, alpha: 1)

        iconView.contentMode = .scaleAspectFit
        iconView.image = UIImage(named: "apple_health")?.withRenderingMode(.alwaysOriginal)
        iconView.isHidden = style != .appleHealth

        brandImageView.contentMode = .scaleAspectFit
        brandImageView.image = UIImage(named: "strava")?.withRenderingMode(.alwaysTemplate)
        brandImageView.tintColor = .white
        brandImageView.isHidden = style != .strava

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = style == .strava ? .white : .black
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.78
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isHidden = style == .strava

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = style == .strava ? UIColor.white.withAlphaComponent(0.88) : .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.lineBreakMode = .byTruncatingTail

        textStackView.axis = .vertical
        textStackView.alignment = .leading
        textStackView.spacing = 4
        textStackView.isUserInteractionEnabled = false

        addSubview(iconView)
        addSubview(brandImageView)
        addSubview(textStackView)
        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(subtitleLabel)

        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            make.centerY.equalToSuperview()
            make.size.equalTo(34)
        }

        brandImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            make.centerY.equalToSuperview().offset(-8)
            make.width.equalTo(104)
            make.height.equalTo(22)
        }

        textStackView.snp.makeConstraints { make in
            switch style {
            case .appleHealth:
                make.leading.equalTo(iconView.snp.trailing).offset(14)
                make.centerY.equalToSuperview()
                make.trailing.equalToSuperview().inset(18)
            case .strava:
                make.leading.equalTo(brandImageView)
                make.trailing.equalToSuperview().inset(18)
                make.top.equalTo(brandImageView.snp.bottom).offset(8)
            }
        }
    }
}

private extension TrackedWorkout {
    func isSamePhysicalWorkout(as other: TrackedWorkout) -> Bool {
        guard isStravaSource != other.isStravaSource,
              activityType.isCompatibleForSourceConflict(with: other.activityType) else {
            return false
        }

        guard startDate == other.startDate,
              hasStrictRouteMatch(with: other) else {
            return false
        }

        return true
    }

    private func hasStrictRouteMatch(with other: TrackedWorkout) -> Bool {
        guard let durationSeconds,
              let otherDurationSeconds = other.durationSeconds,
              durationSeconds > 0,
              otherDurationSeconds > 0,
              durationSeconds == otherDurationSeconds,
              !coordinates.isEmpty,
              !other.coordinates.isEmpty else {
            return false
        }

        let routeStartDate = startDate
        let routeEndDate = routeStartDate.addingTimeInterval(durationSeconds)
        let middleDate = routeStartDate.addingTimeInterval(durationSeconds / 2)
        let windows = [
            DateInterval(start: routeStartDate, end: routeStartDate.addingTimeInterval(5 * 60)),
            DateInterval(start: middleDate.addingTimeInterval(-(5 * 60 / 2)), end: middleDate.addingTimeInterval(5 * 60 / 2)),
            DateInterval(start: routeEndDate.addingTimeInterval(-(5 * 60)), end: routeEndDate)
        ]

        return windows.allSatisfy { window in
            let routePoints = strictRoutePoints(in: window)
            guard !routePoints.isEmpty else {
                return false
            }

            return routePoints == other.strictRoutePoints(in: window)
        }
    }

    private func strictRoutePoints(in window: DateInterval) -> [StrictRoutePoint] {
        coordinates.compactMap { coordinate in
            guard coordinate.timestamp >= window.start,
                  coordinate.timestamp <= window.end else {
                return nil
            }

            return StrictRoutePoint(coordinate: coordinate)
        }
    }
}

private struct StrictRoutePoint: Equatable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double

    init(coordinate: RouteCoordinate) {
        timestamp = coordinate.timestamp
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }
}

private extension HKWorkoutActivityType {
    func isCompatibleForSourceConflict(with other: HKWorkoutActivityType) -> Bool {
        self == other
    }
}
