//
//  WorkoutRouteHeatmapViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/13.
//

import CoreLocation
import MapKit
import SnapKit
import UIKit

final class WorkoutRouteHeatmapViewController: UIViewController {
    private static let careerCollapsedDetentIdentifier = UISheetPresentationController.Detent.Identifier(
        "routeHeatmapCareerCollapsed"
    )

    private var workouts: [TrackedWorkout]
    private let isDemoMode: Bool
    private var knownWorkoutIDs: Set<String>
    private var statisticWorkouts: [TrackedWorkout]
    private var knownStatisticWorkoutIDs: Set<String>
    private let cacheStore = WorkoutCacheStore()
    private let heatmapRouteCacheStore = HeatmapRouteCacheStore.shared
    private let cacheLoadQueue = DispatchQueue(label: "studio.pj.PTrack.heatmap-cache-load", qos: .userInitiated)
    private let routeRenderQueue = DispatchQueue(label: "studio.pj.PTrack.heatmap-render", qos: .userInitiated)
    private let mapContainerView = AppMapContainerView()
    private var mapView: MKMapView { mapContainerView.mapView }
    private let mapToneOverlay = AppMapStyle.makeToneOverlay()
    private let routesOverlay = HeatmapRoutesOverlay()
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let cacheLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private let navigationTitleLabel = UILabel()
    private lazy var moreMenuButton = makeMoreMenuButton()
    private lazy var moreBarButtonItem = UIBarButtonItem(customView: moreMenuButton)
    private lazy var navigationTitleView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [navigationTitleLabel, cacheLoadingIndicator])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 7
        return stackView
    }()
    private lazy var sportsCareerSheetViewController: SportsCareerViewController = {
        let viewController = SportsCareerViewController(
            workouts: filteredStatisticWorkouts,
            presentationStyle: .heatmapSheet,
            referenceDate: filteredStatisticReferenceDate
        )
        viewController.modalPresentationStyle = .pageSheet
        viewController.isModalInPresentation = true
        viewController.onSelectWorkout = { [weak self] workout in
            self?.showWorkoutDetailFromSportsCareer(workout)
        }
        return viewController
    }()

    private var preparedRoutes: [HeatmapRoute] = []
    private var visibleRoutes: [HeatmapRoute] = []
    private var focusRoutes: [HeatmapRoute] = []
    private var loadGeneration = 0
    private var hasFittedRoutes = false
    private var hasUserAdjustedMapRegion = false
    private var hasPresentedSportsCareerSheet = false
    private var suppressSportsCareerSheetPresentation = false
    private var shouldRestoreSportsCareerSheetOnNextAppearance = false
    private var hasPreparedForPermanentDismissal = false
    private var selectedFilters = HeatmapFilterStore.shared.selectedFilters()
    private var selectedYear: Int?
    private var selectedMapStyle = AppMapDisplayStyleStore.shared.heatmapStyle()
    private var filterMenuActions: [HeatmapFilter: UIAction] = [:]
    var routesOverlayRenderer: HeatmapRoutesOverlayRenderer?
    private var overlayUpdateWorkItem: DispatchWorkItem?
    private var heatmapDataRefreshWorkItem: DispatchWorkItem?
    private var regionCacheReloadWorkItem: DispatchWorkItem?
    private var careerStatisticsUpdateWorkItem: DispatchWorkItem?
    private var availableRouteYearValues: Set<Int> = []
    private var knownFocusRouteIDs = Set<String>()
    private var overlayUpdateGeneration = 0
    private var cacheLoadGeneration = 0
    private var isLoadingCachedWorkouts = false
    private var hasCompletedCachedWorkoutLoad = false
    private var hasRestoredCachedRoutes = false
    private var hasRestoredCompleteCachedRoutes = false
    private var hasStartedHeatmapLoading = false

    private let routeSamplingRatio = 1.0
    private let maximumRoutePointCount = 320
    private let navigationBackgroundHeight: CGFloat = 124
    private let routeLoadingPaddingRatio = 0.08
    private let cacheLoadBatchSize = 8
    private let maximumPreparedRoutePoolCount = 1_800
    private let regionCacheReloadDelay: TimeInterval = 0.45

    init(workouts: [TrackedWorkout], isDemoMode: Bool = false) {
        self.workouts = workouts
        self.isDemoMode = isDemoMode
        knownWorkoutIDs = []
        statisticWorkouts = Self.statisticsWorkouts(from: workouts)
        knownStatisticWorkoutIDs = Set(statisticWorkouts.map(\.id))
        availableRouteYearValues = Set(statisticWorkouts.map { Calendar.current.component(.year, from: $0.startDate) })
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        registerLanguageObserver()
        configureMapView()
        configureNavigationBackgroundView()
        configureLoadingIndicator()
        registerTraitChangeHandler()
    }

    deinit {
        prepareForPermanentDismissal()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        configureNavigationBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if shouldRestoreSportsCareerSheetOnNextAppearance {
            shouldRestoreSportsCareerSheetOnNextAppearance = false
            suppressSportsCareerSheetPresentation = false
            presentSportsCareerSheetIfNeeded()
            return
        }

        if suppressSportsCareerSheetPresentation {
            suppressSportsCareerSheetPresentation = false
        } else {
            presentSportsCareerSheetIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if hasPresentedSportsCareerSheet,
           isPermanentlyLeaving {
            hasPresentedSportsCareerSheet = false
            cancelRouteRenderingWork()
            sportsCareerSheetViewController.dismiss(animated: false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isPermanentlyLeaving {
            prepareForPermanentDismissal()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        startHeatmapLoadingIfNeeded()
        fitRoutesIfNeeded()
        scheduleVisibleRouteOverlayUpdate()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        cancelRouteRenderingWork()
        routesOverlay.renderedRoutes = []
        invalidateRoutesOverlayRenderer()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppAppearanceStore.shared.preferredStatusBarStyle(for: traitCollection)
    }

    private var isPermanentlyLeaving: Bool {
        isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true
    }

    private var filteredStatisticWorkouts: [TrackedWorkout] {
        statisticWorkouts.filter(isWorkoutIncludedBySelectedFilters)
    }

    private var filteredStatisticReferenceDate: Date? {
        filteredStatisticWorkouts.map(\.startDate).max()
    }

    private var cameraFocusRoutes: [HeatmapRoute] {
        let filteredFocusRoutes = focusRoutes.filter(isRouteIncludedBySelectedFilters)
        return filteredFocusRoutes.isEmpty ? visibleRoutes : filteredFocusRoutes
    }

    private func configureNavigationItem() {
        configureNavigationTitleView()
        navigationItem.largeTitleDisplayMode = .never
        updateNavigationRightBarButtonItems()
        edgesForExtendedLayout = [.top, .bottom]
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
        configureNavigationTitleView()
        updateNavigationRightBarButtonItems()
    }

    private func configureNavigationTitleView() {
        let titleText = AppLocalization.text(.routeHeatmap)
        title = titleText
        navigationTitleLabel.text = titleText
        navigationTitleLabel.textColor = .label
        navigationTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        navigationTitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        cacheLoadingIndicator.color = .secondaryLabel
        cacheLoadingIndicator.hidesWhenStopped = true
        navigationItem.titleView = navigationTitleView
    }

    private func makeMoreMenuButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = AppLocalization.text(.more)
        button.showsMenuAsPrimaryAction = true
        button.menu = makeMoreMenu()
        button.frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    private func updateNavigationRightBarButtonItems() {
        updateMoreMenuButtonMenu()
        navigationItem.rightBarButtonItem = moreBarButtonItem
    }

    private func updateMoreMenuButtonMenu() {
        moreMenuButton.accessibilityLabel = AppLocalization.text(.more)
        moreMenuButton.menu = makeMoreMenu()
    }

    private func setCachedWorkoutLoading(_ isLoading: Bool, showsIndicator: Bool = true) {
        let shouldAnimateIndicator = isLoading && showsIndicator
        guard isLoadingCachedWorkouts != isLoading
                || cacheLoadingIndicator.isAnimating != shouldAnimateIndicator else {
            return
        }

        isLoadingCachedWorkouts = isLoading
        if shouldAnimateIndicator {
            cacheLoadingIndicator.startAnimating()
        } else {
            cacheLoadingIndicator.stopAnimating()
        }
    }

    private func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.isTranslucent = true
        navigationController?.navigationBar.barStyle = .default
        navigationController?.navigationBar.tintColor = .label
    }

    private func configureNavigationBackgroundView() {
        navigationBackgroundView.isUserInteractionEnabled = false
        updateNavigationBackgroundColors()

        view.addSubview(navigationBackgroundView)

        navigationBackgroundView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(navigationBackgroundHeight)
        }
    }

    private func updateNavigationBackgroundColors() {
        navigationBackgroundView.effect = nil
        navigationBackgroundView.contentView.backgroundColor = .clear
        navigationBackgroundView.layer.mask = nil
    }

    private func registerTraitChangeHandler() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (viewController: Self, _) in
            viewController.updateNavigationBackgroundColors()
            viewController.setNeedsStatusBarAppearanceUpdate()
        }
    }

    private func configureMapView() {
        mapView.delegate = self
        AppMapStyle.apply(selectedMapStyle, to: mapView)
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false

        view.addSubview(mapContainerView)

        mapContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        AppMapStyle.setToneOverlay(
            mapToneOverlay,
            visible: selectedMapStyle == .appDefault,
            on: mapView
        )
        mapView.addOverlay(routesOverlay, level: .aboveLabels)
    }

    private func configureLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true
        cacheLoadingIndicator.hidesWhenStopped = true
        loadingIndicator.startAnimating()

        view.addSubview(loadingIndicator)

        loadingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func prepareForPermanentDismissal() {
        guard !hasPreparedForPermanentDismissal else {
            return
        }

        hasPreparedForPermanentDismissal = true
        cacheLoadGeneration += 1
        loadGeneration += 1
        setCachedWorkoutLoading(false)
        loadingIndicator.stopAnimating()
        heatmapDataRefreshWorkItem?.cancel()
        regionCacheReloadWorkItem?.cancel()
        careerStatisticsUpdateWorkItem?.cancel()
        heatmapDataRefreshWorkItem = nil
        regionCacheReloadWorkItem = nil
        careerStatisticsUpdateWorkItem = nil
        cancelRouteRenderingWork()
        preparedRoutes.removeAll(keepingCapacity: false)
        visibleRoutes.removeAll(keepingCapacity: false)
        focusRoutes.removeAll(keepingCapacity: false)
        statisticWorkouts.removeAll(keepingCapacity: false)
        knownStatisticWorkoutIDs.removeAll(keepingCapacity: false)
        knownFocusRouteIDs.removeAll(keepingCapacity: false)
        routesOverlay.renderedRoutes = []
        routesOverlayRenderer = nil
        mapView.delegate = nil
        if !mapView.overlays.isEmpty {
            mapView.removeOverlays(mapView.overlays)
        }
        if !mapView.annotations.isEmpty {
            mapView.removeAnnotations(mapView.annotations)
        }
        mapView.layer.removeAllAnimations()
        mapContainerView.layer.removeAllAnimations()
        AppMapContainerView.retainForMetalDrain(mapContainerView)
    }

    private func startHeatmapLoadingIfNeeded() {
        guard !hasStartedHeatmapLoading,
              mapView.bounds.width > 1,
              mapView.bounds.height > 1 else {
            return
        }

        hasStartedHeatmapLoading = true
        if isDemoMode {
            prepareHeatmapRoutes()
            hasCompletedCachedWorkoutLoad = true
            setCachedWorkoutLoading(false)
            return
        }

        let cachedRouteRestoreState = restoreCachedHeatmapRoutesIfAvailable()
        hasRestoredCachedRoutes = cachedRouteRestoreState.didRestore
        hasRestoredCompleteCachedRoutes = cachedRouteRestoreState.isComplete
        if !hasRestoredCachedRoutes {
            prepareHeatmapRoutes()
        }
        loadCachedWorkoutsProgressively(
            showsLoadingIndicator: !hasRestoredCachedRoutes || !hasRestoredCompleteCachedRoutes
        )
    }

    private func loadCachedWorkoutsProgressively(showsLoadingIndicator: Bool = true) {
        guard !hasCompletedCachedWorkoutLoad, !isLoadingCachedWorkouts else {
            return
        }

        cacheLoadGeneration += 1
        let generation = cacheLoadGeneration
        setCachedWorkoutLoading(true, showsIndicator: showsLoadingIndicator)
        let cacheStore = cacheStore
        let cacheLoadBatchSize = cacheLoadBatchSize
        let samplingRatio = routeSamplingRatio
        let maximumRoutePointCount = maximumRoutePointCount
        let heatmapRouteCacheStore = heatmapRouteCacheStore
        let initialWorkoutIDs = Set(workouts.map(\.id))
        let initialStatisticWorkouts = Self.statisticsWorkouts(from: workouts)

        cacheLoadQueue.async { [weak self, cacheStore, cacheLoadBatchSize] in
            var loadedWorkoutIDs = Set<String>()
            heatmapRouteCacheStore.storeStatisticWorkouts(
                initialStatisticWorkouts,
                processedWorkoutIDs: initialWorkoutIDs,
                isComplete: false
            )
            cacheStore.loadProgressively(
                batchSize: cacheLoadBatchSize,
                shouldContinue: { [weak self] in
                    var shouldContinue = false
                    DispatchQueue.main.sync {
                        shouldContinue = self?.cacheLoadGeneration == generation
                            && self?.hasPreparedForPermanentDismissal == false
                    }
                    return shouldContinue
                },
                onBatch: { [weak self] cachedWorkoutBatch in
                    guard self != nil else {
                        return
                    }

                    loadedWorkoutIDs.formUnion(cachedWorkoutBatch.map(\.id))
                    let statisticWorkouts = Self.statisticsWorkouts(from: cachedWorkoutBatch)
                    heatmapRouteCacheStore.storeStatisticWorkouts(
                        statisticWorkouts,
                        processedWorkoutIDs: initialWorkoutIDs.union(loadedWorkoutIDs),
                        isComplete: false
                    )
                    let focusRoutes = cachedWorkoutBatch.compactMap { workout in
                        Self.cachedOrMakeHeatmapRoute(
                            for: workout,
                            samplingRatio: samplingRatio,
                            maximumPointCount: maximumRoutePointCount,
                            routeCacheStore: heatmapRouteCacheStore
                        )
                    }
                    heatmapRouteCacheStore.markRouteSetProgress(
                        workoutIDs: initialWorkoutIDs.union(loadedWorkoutIDs)
                    )

                    DispatchQueue.main.async { [weak self] in
                        self?.mergeCachedHeatmapBatch(
                            focusRoutes: focusRoutes,
                            statisticWorkouts: statisticWorkouts,
                            generation: generation
                        )
                    }
                }
            )

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.cacheLoadGeneration == generation else {
                    return
                }

                heatmapRouteCacheStore.pruneRoutes(
                    keeping: initialWorkoutIDs.union(loadedWorkoutIDs)
                )
                heatmapRouteCacheStore.markRouteSetComplete(
                    workoutIDs: initialWorkoutIDs.union(loadedWorkoutIDs)
                )
                heatmapRouteCacheStore.markStatisticWorkoutsComplete(
                    workoutIDs: initialWorkoutIDs.union(loadedWorkoutIDs)
                )
                self.setCachedWorkoutLoading(false)
                self.hasCompletedCachedWorkoutLoad = true
                if !self.hasFittedRoutes, !self.hasUserAdjustedMapRegion {
                    self.fitMap(to: self.cameraFocusRoutes, animated: true)
                }
                self.scheduleSportsCareerStatisticsUpdate(immediate: true, animated: true)
            }
        }
    }

    private func restoreCachedHeatmapRoutesIfAvailable() -> (didRestore: Bool, isComplete: Bool) {
        let currentWorkoutIDs = cacheStore.loadCachedWorkoutIDs().map(Set.init)
        let snapshot = heatmapRouteCacheStore.cachedRouteSnapshot(currentWorkoutIDs: currentWorkoutIDs)
        let cachedRoutes = snapshot.routes
        let cachedStatisticWorkouts = snapshot.statisticWorkouts
        guard !cachedRoutes.isEmpty || !cachedStatisticWorkouts.isEmpty else {
            return (false, false)
        }

        mergeStatisticWorkouts(cachedStatisticWorkouts)
        mergeFocusRoutes(cachedRoutes)
        availableRouteYearValues.formUnion(cachedRoutes.map(\.startYear))

        if !cachedRoutes.isEmpty,
           let fittedMapRect = fitMap(to: cameraFocusRoutes, animated: false) {
            rebuildPreparedRoutePoolFromFocusRoutes(
                in: Self.expandedMapRect(fittedMapRect, paddingRatio: 1.2)
            )
        } else if !cachedRoutes.isEmpty {
            let routePoolMapRect = Self.boundingMapRect(for: cachedRoutes) ?? MKMapRect.world
            preparedRoutes = Self.spatiallyDistributedRoutes(
                cachedRoutes,
                in: routePoolMapRect,
                maximumCount: maximumPreparedRoutePoolCount
            )
            knownWorkoutIDs = Set(preparedRoutes.map(\.id))
            visibleRoutes = preparedRoutes.filter(isRouteIncludedBySelectedFilters)
        }

        if !visibleRoutes.isEmpty {
            scheduleVisibleRouteOverlayUpdate(immediate: true)
        }
        scheduleSportsCareerStatisticsUpdate(immediate: true, animated: false)
        loadingIndicator.stopAnimating()
        return (!cachedRoutes.isEmpty, snapshot.isComplete)
    }

    private func mergeCachedHeatmapBatch(
        focusRoutes: [HeatmapRoute],
        statisticWorkouts: [TrackedWorkout],
        generation: Int
    ) {
        guard cacheLoadGeneration == generation else {
            return
        }

        mergeStatisticWorkouts(statisticWorkouts)
        mergeFocusRoutes(focusRoutes)
        availableRouteYearValues.formUnion(focusRoutes.map(\.startYear))
        guard !focusRoutes.isEmpty else {
            return
        }

        let loadingMapRect = routeLoadingMapRect()
        var didAppendRoute = false
        var didAppendVisibleRoute = false

        preparedRoutes.reserveCapacity(preparedRoutes.count + focusRoutes.count)
        for route in focusRoutes where route.boundingMapRect.intersects(loadingMapRect) && knownWorkoutIDs.insert(route.id).inserted {
            preparedRoutes.append(route)
            didAppendRoute = true

            guard isRouteIncludedBySelectedFilters(route) else {
                continue
            }

            visibleRoutes.append(route)
            if route.boundingMapRect.intersects(loadingMapRect) {
                didAppendVisibleRoute = true
            }
        }

        trimPreparedRoutePool(to: loadingMapRect)
        guard didAppendRoute, didAppendVisibleRoute else {
            return
        }

        scheduleVisibleRouteOverlayUpdate(preservesRenderedRoutes: true)
    }

    private func mergeStatisticWorkouts(_ workouts: [TrackedWorkout]) {
        guard !workouts.isEmpty else {
            return
        }

        var didAppendWorkout = false
        statisticWorkouts.reserveCapacity(statisticWorkouts.count + workouts.count)
        for workout in workouts where knownStatisticWorkoutIDs.insert(workout.id).inserted {
            statisticWorkouts.append(workout)
            availableRouteYearValues.insert(Calendar.current.component(.year, from: workout.startDate))
            didAppendWorkout = true
        }

        guard didAppendWorkout else {
            return
        }

        statisticWorkouts.sort { $0.startDate > $1.startDate }
        scheduleSportsCareerStatisticsUpdate(animated: true)
    }

    private func mergeFocusRoutes(_ routes: [HeatmapRoute]) {
        guard !routes.isEmpty else {
            return
        }

        focusRoutes.reserveCapacity(focusRoutes.count + routes.count)
        for route in routes where knownFocusRouteIDs.insert(route.id).inserted {
            focusRoutes.append(route)
        }
    }

    private func scheduleSportsCareerStatisticsUpdate(
        immediate: Bool = false,
        animated: Bool
    ) {
        guard hasPresentedSportsCareerSheet else {
            return
        }

        if immediate {
            careerStatisticsUpdateWorkItem?.cancel()
            careerStatisticsUpdateWorkItem = nil
            sportsCareerSheetViewController.updateWorkouts(
                filteredStatisticWorkouts,
                animated: animated,
                referenceDate: filteredStatisticReferenceDate
            )
            return
        }

        guard careerStatisticsUpdateWorkItem == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.careerStatisticsUpdateWorkItem = nil
            self.sportsCareerSheetViewController.updateWorkouts(
                self.filteredStatisticWorkouts,
                animated: animated,
                referenceDate: self.filteredStatisticReferenceDate
            )
        }
        careerStatisticsUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func trimPreparedRoutePool(to mapRect: MKMapRect) {
        let retainedRoutes = preparedRoutes.filter { route in
            route.boundingMapRect.intersects(mapRect)
        }
        preparedRoutes = Self.spatiallyDistributedRoutes(
            retainedRoutes,
            in: mapRect,
            maximumCount: maximumPreparedRoutePoolCount
        )
        knownWorkoutIDs = Set(preparedRoutes.map(\.id))
        visibleRoutes = preparedRoutes.filter(isRouteIncludedBySelectedFilters)
    }

    private func scheduleHeatmapDataRefresh(
        resetCamera: Bool,
        preservesRenderedRoutes: Bool,
        delay: TimeInterval = 0.16
    ) {
        guard !hasPreparedForPermanentDismissal else {
            return
        }

        heatmapDataRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.prepareHeatmapRoutes(
                resetCamera: resetCamera,
                preservesRenderedRoutes: preservesRenderedRoutes
            )
        }
        heatmapDataRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func makeMoreMenu() -> UIMenu {
        let filterActions = HeatmapFilter.allCases.map(makeFilterMenuAction)
        let shareAction = UIAction(
            title: AppLocalization.text(.share),
            image: UIImage(systemName: "square.and.arrow.up.on.square")
        ) { [weak self] _ in
            self?.showHeatmapShare()
        }

        let mapStyleActions = AppMapDisplayStyle.menuCases.map { style in
            UIAction(
                title: style.title,
                state: style == selectedMapStyle ? .on : .off
            ) { [weak self] _ in
                self?.applyMapStyleFromMenu(style)
            }
        }

        return UIMenu(
            title: "",
            identifier: UIMenu.Identifier("studio.pj.PTrack.heatmap.more"),
            children: [
                shareAction,
                UIMenu(
                    title: AppLocalization.text(.sportType),
                    image: UIImage(systemName: "figure.walk"),
                    identifier: UIMenu.Identifier("studio.pj.PTrack.heatmap.sportType"),
                    children: filterActions
                ),
                UIMenu(
                    title: AppLocalization.text(.time),
                    image: UIImage(systemName: "calendar"),
                    identifier: UIMenu.Identifier("studio.pj.PTrack.heatmap.time"),
                    children: [
                        UIDeferredMenuElement.uncached { [weak self] completion in
                            completion(self?.makeTimeMenuActions() ?? [])
                        }
                    ]
                ),
                UIMenu(
                    title: AppLocalization.text(.mapStyle),
                    image: UIImage(systemName: "map"),
                    identifier: UIMenu.Identifier("studio.pj.PTrack.heatmap.mapStyle"),
                    children: mapStyleActions
                )
            ]
        )
    }

    private func showHeatmapShare() {
        dismissSportsCareerSheetForNavigation { [weak self] in
            guard let self else {
                return
            }

            let shareViewController = WorkoutRouteHeatmapShareViewController(
                workouts: self.workouts.filter(self.isWorkoutIncludedBySelectedFilters),
                referenceDate: self.filteredStatisticReferenceDate,
                timelineWorkouts: self.filteredStatisticWorkouts,
                selectedFilters: self.selectedFilters,
                selectedYear: self.selectedYear,
                allowsCacheAugmentation: !self.isDemoMode,
                allowsPhotoBackground: !self.isDemoMode,
                allowsPhotoLibrarySaving: !self.isDemoMode
            )
            self.shouldRestoreSportsCareerSheetOnNextAppearance = true
            self.navigationController?.pushViewController(shareViewController, animated: true)
        }
    }

    private func makeTimeMenuActions() -> [UIMenuElement] {
        var actions: [UIMenuElement] = [
            UIAction(
                title: AppLocalization.text(.all),
                state: selectedYear == nil ? .on : .off
            ) { [weak self] _ in
                self?.applyYearFilterFromMenu(nil)
            }
        ]

        actions.append(contentsOf: availableRouteYears().map { year in
            UIAction(
                title: "\(year)",
                state: selectedYear == year ? .on : .off
            ) { [weak self] _ in
                self?.applyYearFilterFromMenu(year)
            }
        })

        return actions
    }

    private func availableRouteYears() -> [Int] {
        var years = availableRouteYearValues
        if let selectedYear {
            years.insert(selectedYear)
        }
        return years.sorted(by: >)
    }

    private func makeFilterMenuAction(for filter: HeatmapFilter) -> UIAction {
        if let action = filterMenuActions[filter] {
            configureFilterMenuAction(action, for: filter)
            return action
        }

        let action = UIAction(
            title: filter.title,
            image: nil,
            identifier: filterMenuActionIdentifier(for: filter),
            state: selectedFilters.contains(filter) ? .on : .off
        ) { [weak self] _ in
            self?.toggleFilterFromMenu(filter)
        }
        filterMenuActions[filter] = action
        return action
    }

    private func configureFilterMenuAction(_ action: UIAction, for filter: HeatmapFilter) {
        action.title = filter.title
        action.image = nil
        action.state = selectedFilters.contains(filter) ? .on : .off
    }

    private func filterMenuActionIdentifier(for filter: HeatmapFilter) -> UIAction.Identifier {
        UIAction.Identifier("studio.pj.PTrack.heatmap.filter.\(filter.rawValue)")
    }

    private func updateFilterMenuActionStates() {
        for filter in HeatmapFilter.allCases {
            if let action = filterMenuActions[filter] {
                configureFilterMenuAction(action, for: filter)
            }
        }
    }

    private func reopenMoreMenuAfterSubmenuSelection() {
        updateMoreMenuButtonMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self,
                  !self.hasPreparedForPermanentDismissal,
                  self.view.window != nil,
                  self.moreMenuButton.window != nil else {
                return
            }

            self.moreMenuButton.performPrimaryAction()
        }
    }

    private func presentSportsCareerSheetIfNeeded() {
        guard !hasPresentedSportsCareerSheet,
              presentedViewController == nil,
              view.window != nil else {
            return
        }

        sportsCareerSheetViewController.setHeatmapSheetContentVisible(false, animated: false)
        sportsCareerSheetViewController.resetHeatmapSheetContentOffset()
        if let sheetPresentationController = sportsCareerSheetViewController.sheetPresentationController {
            sheetPresentationController.detents = [
                .custom(identifier: Self.careerCollapsedDetentIdentifier) { _ in
                    SportsCareerViewController.heatmapSheetCollapsedHeight
                },
                .medium(),
                .large()
            ]
            sheetPresentationController.selectedDetentIdentifier = Self.careerCollapsedDetentIdentifier
            sheetPresentationController.largestUndimmedDetentIdentifier = .large
            sheetPresentationController.prefersGrabberVisible = true
            sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = true
            sheetPresentationController.preferredCornerRadius = 28
            sheetPresentationController.delegate = self
        }

        hasPresentedSportsCareerSheet = true
        present(sportsCareerSheetViewController, animated: false) { [weak self] in
            self?.sportsCareerSheetViewController.setHeatmapSheetContentVisible(false, animated: false)
            self?.sportsCareerSheetViewController.resetHeatmapSheetContentOffset()
        }
    }

    private func dismissSportsCareerSheetForNavigation(_ completion: @escaping () -> Void) {
        guard presentedViewController === sportsCareerSheetViewController else {
            completion()
            return
        }

        suppressSportsCareerSheetPresentation = true
        hasPresentedSportsCareerSheet = false
        sportsCareerSheetViewController.dismiss(animated: true, completion: completion)
    }

    private func showWorkoutDetailFromSportsCareer(_ workout: TrackedWorkout) {
        dismissSportsCareerSheetForNavigation { [weak self] in
            guard let self else {
                return
            }

            let resolvedWorkout = self.isDemoMode
                ? workout
                : (self.cacheStore.loadWorkout(id: workout.id) ?? workout)
            let detailViewController = WorkoutRouteDetailViewController(
                workout: resolvedWorkout,
                isDemoMode: self.isDemoMode
            )
            self.shouldRestoreSportsCareerSheetOnNextAppearance = true
            self.navigationController?.pushViewController(detailViewController, animated: true)
        }
    }

    private func prepareHeatmapRoutes(resetCamera: Bool = true, preservesRenderedRoutes: Bool = false) {
        loadGeneration += 1
        let generation = loadGeneration
        let workouts = workouts
        let samplingRatio = routeSamplingRatio
        let maximumRoutePointCount = maximumRoutePointCount
        let routePoolMapRect = resetCamera ? MKMapRect.world : routeLoadingMapRect()
        let maximumPreparedRoutePoolCount = maximumPreparedRoutePoolCount
        let heatmapRouteCacheStore = heatmapRouteCacheStore
        let usesPersistentRouteCache = !isDemoMode

        DispatchQueue.global(qos: .userInitiated).async {
            var routes: [HeatmapRoute] = []
            var focusRoutes: [HeatmapRoute] = []
            routes.reserveCapacity(min(workouts.count, maximumPreparedRoutePoolCount))
            focusRoutes.reserveCapacity(min(workouts.count, maximumPreparedRoutePoolCount))

            for workout in workouts {
                let route = usesPersistentRouteCache
                    ? Self.cachedOrMakeHeatmapRoute(
                        for: workout,
                        samplingRatio: samplingRatio,
                        maximumPointCount: maximumRoutePointCount,
                        routeCacheStore: heatmapRouteCacheStore
                    )
                    : Self.makeHeatmapRoute(
                        for: workout,
                        samplingRatio: samplingRatio,
                        maximumPointCount: maximumRoutePointCount
                    )
                guard let route else {
                    continue
                }

                focusRoutes.append(route)
                guard route.boundingMapRect.intersects(routePoolMapRect) else {
                    continue
                }

                routes.append(route)
                if routes.count > maximumPreparedRoutePoolCount * 2 {
                    routes = Self.spatiallyDistributedRoutes(
                        routes,
                        in: routePoolMapRect,
                        maximumCount: maximumPreparedRoutePoolCount
                    )
                }
            }

            routes = Self.spatiallyDistributedRoutes(
                routes,
                in: routePoolMapRect,
                maximumCount: maximumPreparedRoutePoolCount
            )

            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadGeneration == generation else {
                    return
                }

                self.mergeFocusRoutes(focusRoutes)
                self.preparedRoutes = routes
                self.knownWorkoutIDs = Set(routes.map(\.id))
                self.applySelectedFilters(
                    resetCamera: resetCamera,
                    preservesRenderedRoutes: preservesRenderedRoutes
                )
            }
        }
    }

    private func fitRoutesIfNeeded() {
        guard !hasFittedRoutes, !cameraFocusRoutes.isEmpty else {
            return
        }

        fitMap(to: cameraFocusRoutes, animated: false)
    }

    private func toggleFilter(_ filter: HeatmapFilter) {
        if selectedFilters.contains(filter) {
            selectedFilters.remove(filter)
        } else {
            selectedFilters.insert(filter)
        }

        updateFilterMenuActionStates()
        HeatmapFilterStore.shared.setSelectedFilters(selectedFilters)
        applySelectedFilters(resetCamera: false, preservesRenderedRoutes: false)
        scheduleCurrentRegionCacheReload()
    }

    private func toggleFilterFromMenu(_ filter: HeatmapFilter) {
        toggleFilter(filter)
        reopenMoreMenuAfterSubmenuSelection()
    }

    private func applyYearFilter(_ year: Int?) {
        guard selectedYear != year else {
            return
        }

        selectedYear = year
        applySelectedFilters(resetCamera: false, preservesRenderedRoutes: false)
        scheduleCurrentRegionCacheReload()
    }

    private func applyYearFilterFromMenu(_ year: Int?) {
        applyYearFilter(year)
        reopenMoreMenuAfterSubmenuSelection()
    }

    private func applySelectedFilters(resetCamera: Bool, preservesRenderedRoutes: Bool) {
        if !preservesRenderedRoutes {
            resetRenderedRouteState(removesCache: true)
        }

        let fittedMapRect: MKMapRect?
        if resetCamera, !hasFittedRoutes {
            fittedMapRect = fitMap(to: cameraFocusRoutes, animated: true)
        } else {
            fittedMapRect = nil
        }

        if let fittedMapRect, !focusRoutes.isEmpty {
            rebuildPreparedRoutePoolFromFocusRoutes(
                in: Self.expandedMapRect(fittedMapRect, paddingRatio: 1.2)
            )
        } else {
            visibleRoutes = preparedRoutes.filter(isRouteIncludedBySelectedFilters)
        }

        if !visibleRoutes.isEmpty {
            scheduleVisibleRouteOverlayUpdate(
                immediate: true,
                preservesRenderedRoutes: preservesRenderedRoutes
            )
        }

        scheduleSportsCareerStatisticsUpdate(immediate: true, animated: true)
        loadingIndicator.stopAnimating()
    }

    private func rebuildPreparedRoutePoolFromFocusRoutes(in mapRect: MKMapRect) {
        guard !focusRoutes.isEmpty, !mapRect.isNull else {
            return
        }

        let candidateRoutes = focusRoutes.filter { route in
            route.boundingMapRect.intersects(mapRect)
        }
        let routes = Self.spatiallyDistributedRoutes(
            candidateRoutes,
            in: mapRect,
            maximumCount: maximumPreparedRoutePoolCount
        )
        preparedRoutes = routes
        knownWorkoutIDs = Set(routes.map(\.id))
        visibleRoutes = routes.filter(isRouteIncludedBySelectedFilters)
    }

    private func isRouteIncludedBySelectedFilters(_ route: HeatmapRoute) -> Bool {
        let isIncludedBySport = selectedFilters.contains { filter in
            filter.includes(route.sportKind)
        }
        let isIncludedByYear = selectedYear.map { route.startYear == $0 } ?? true
        return isIncludedBySport && isIncludedByYear
    }

    private func isWorkoutIncludedBySelectedFilters(_ workout: TrackedWorkout) -> Bool {
        let isIncludedBySport = selectedFilters.contains { filter in
            filter.includes(workout.sportKind)
        }
        let isIncludedByYear = selectedYear.map {
            Calendar.current.component(.year, from: workout.startDate) == $0
        } ?? true
        return isIncludedBySport && isIncludedByYear
    }

    private func applyMapStyle(_ style: AppMapDisplayStyle) {
        guard style != selectedMapStyle else {
            return
        }

        selectedMapStyle = style
        AppMapDisplayStyleStore.shared.setHeatmapStyle(style)
        AppMapStyle.apply(style, to: mapView)
        AppMapStyle.setToneOverlay(mapToneOverlay, visible: style == .appDefault, on: mapView)
        updateNavigationRightBarButtonItems()
    }

    private func applyMapStyleFromMenu(_ style: AppMapDisplayStyle) {
        applyMapStyle(style)
        reopenMoreMenuAfterSubmenuSelection()
    }

    @discardableResult
    private func fitMap(to routes: [HeatmapRoute], animated: Bool) -> MKMapRect? {
        guard let targetMapRect = Self.densestRoutePointMapRect(for: routes) ?? Self.boundingMapRect(for: routes),
              !targetMapRect.isNull,
              mapView.bounds.width > 1,
              mapView.bounds.height > 1 else {
            return nil
        }

        hasFittedRoutes = true
        mapView.setVisibleMapRect(
            targetMapRect,
            edgePadding: UIEdgeInsets(
                top: 96,
                left: 32,
                bottom: SportsCareerViewController.heatmapSheetCollapsedHeight + 28,
                right: 32
            ),
            animated: animated
        )
        return targetMapRect
    }

    private static func densestRoutePointMapRect(for routes: [HeatmapRoute]) -> MKMapRect? {
        var points: [MKMapPoint] = []
        var boundingMapRect = MKMapRect.null

        for route in routes {
            points.reserveCapacity(points.count + route.coordinates.count)
            for coordinate in route.coordinates where CLLocationCoordinate2DIsValid(coordinate) {
                let point = MKMapPoint(coordinate)
                points.append(point)
                boundingMapRect = boundingMapRect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
            }
        }

        guard points.count > 1, !boundingMapRect.isNull else {
            return boundingMapRect.isNull ? nil : paddedHeatmapFocusMapRect(for: boundingMapRect)
        }

        let gridSide = 4
        var searchRect = usableHeatmapSearchRect(boundingMapRect)
        var candidateIndexes = Array(points.indices)

        for _ in 0..<4 {
            guard candidateIndexes.count > 8 else {
                break
            }

            let cellWidth = max(searchRect.size.width / Double(gridSide), 1)
            let cellHeight = max(searchRect.size.height / Double(gridSide), 1)
            var buckets = Array(repeating: [Int](), count: gridSide * gridSide)

            for pointIndex in candidateIndexes {
                let point = points[pointIndex]
                guard point.x >= searchRect.minX,
                      point.x <= searchRect.maxX,
                      point.y >= searchRect.minY,
                      point.y <= searchRect.maxY else {
                    continue
                }

                let column = min(max(Int((point.x - searchRect.minX) / cellWidth), 0), gridSide - 1)
                let row = min(max(Int((point.y - searchRect.minY) / cellHeight), 0), gridSide - 1)
                buckets[row * gridSide + column].append(pointIndex)
            }

            guard let bestBucketIndex = buckets.indices.max(by: { buckets[$0].count < buckets[$1].count }),
                  !buckets[bestBucketIndex].isEmpty else {
                break
            }

            candidateIndexes = buckets[bestBucketIndex]
            let column = bestBucketIndex % gridSide
            let row = bestBucketIndex / gridSide
            searchRect = MKMapRect(
                x: searchRect.minX + Double(column) * cellWidth,
                y: searchRect.minY + Double(row) * cellHeight,
                width: cellWidth,
                height: cellHeight
            )
        }

        var clusterMapRect = MKMapRect.null
        for pointIndex in candidateIndexes {
            let point = points[pointIndex]
            clusterMapRect = clusterMapRect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

        guard !clusterMapRect.isNull else {
            return paddedHeatmapFocusMapRect(for: boundingMapRect)
        }

        return paddedHeatmapFocusMapRect(for: clusterMapRect)
    }

    private static func usableHeatmapSearchRect(_ rect: MKMapRect) -> MKMapRect {
        guard !rect.isNull else {
            return rect
        }

        let width = max(rect.size.width, 1)
        let height = max(rect.size.height, 1)
        return MKMapRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func paddedHeatmapFocusMapRect(for rect: MKMapRect) -> MKMapRect {
        guard !rect.isNull else {
            return rect
        }

        let centerPoint = MKMapPoint(x: rect.midX, y: rect.midY)
        let minimumSpan = max(4_000 * MKMapPointsPerMeterAtLatitude(centerPoint.coordinate.latitude), 1)
        let width = max(rect.size.width * 2.4, minimumSpan)
        let height = max(rect.size.height * 2.4, minimumSpan)
        return MKMapRect(
            x: centerPoint.x - width / 2,
            y: centerPoint.y - height / 2,
            width: width,
            height: height
        )
    }

    private static func expandedMapRect(_ rect: MKMapRect, paddingRatio: Double) -> MKMapRect {
        guard !rect.isNull else {
            return rect
        }

        let dx = rect.size.width * paddingRatio
        let dy = rect.size.height * paddingRatio
        return rect.insetBy(dx: -dx, dy: -dy).intersection(MKMapRect.world)
    }

    private static func boundingMapRect(for routes: [HeatmapRoute]) -> MKMapRect? {
        let boundingMapRect = routes.reduce(MKMapRect.null) { rect, route in
            rect.union(route.boundingMapRect)
        }

        return boundingMapRect.isNull ? nil : boundingMapRect
    }

    func handleMapRegionWillChange(_ mapView: MKMapView) {
        if Self.hasActiveUserGesture(in: mapView) {
            hasUserAdjustedMapRegion = true
        }

        suspendProgressiveRouteLoading()
    }

    func handleMapRegionDidChange(_ mapView: MKMapView) {
        guard mapView.bounds.width > 1, mapView.bounds.height > 1 else {
            return
        }

        scheduleVisibleRouteOverlayUpdate()
        scheduleCurrentRegionCacheReload()
    }

    private static func hasActiveUserGesture(in view: UIView) -> Bool {
        if view.gestureRecognizers?.contains(where: { gestureRecognizer in
            switch gestureRecognizer.state {
            case .began, .changed, .ended:
                return true
            default:
                return false
            }
        }) == true {
            return true
        }

        return view.subviews.contains { hasActiveUserGesture(in: $0) }
    }

    private func resetRenderedRouteState(removesCache _: Bool) {
        overlayUpdateGeneration += 1
        overlayUpdateWorkItem?.cancel()
        overlayUpdateWorkItem = nil
        routesOverlay.renderedRoutes = []
        invalidateRoutesOverlayRenderer()
    }

    private func cancelRouteRenderingWork() {
        overlayUpdateGeneration += 1
        overlayUpdateWorkItem?.cancel()
        overlayUpdateWorkItem = nil
    }

    func suspendProgressiveRouteLoading() {
        cancelRouteRenderingWork()
    }

    private func scheduleCurrentRegionCacheReload() {
        guard hasStartedHeatmapLoading, !hasPreparedForPermanentDismissal else {
            return
        }

        regionCacheReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reloadCurrentRegionRoutePool()
        }
        regionCacheReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + regionCacheReloadDelay, execute: workItem)
    }

    private func reloadCurrentRegionRoutePool() {
        guard !hasPreparedForPermanentDismissal,
              mapView.bounds.width > 1,
              mapView.bounds.height > 1 else {
            return
        }

        let loadingMapRect = routeLoadingMapRect()
        if focusRoutes.isEmpty {
            trimPreparedRoutePool(to: loadingMapRect)
            prepareHeatmapRoutes(resetCamera: false, preservesRenderedRoutes: true)
        } else {
            rebuildPreparedRoutePoolFromFocusRoutes(in: loadingMapRect)
            if !visibleRoutes.isEmpty {
                scheduleVisibleRouteOverlayUpdate(preservesRenderedRoutes: true)
            }
        }
        loadCachedWorkoutsProgressively()
    }

    func scheduleVisibleRouteOverlayUpdate(immediate: Bool = false, preservesRenderedRoutes: Bool = false) {
        guard !hasPreparedForPermanentDismissal else {
            return
        }

        guard !visibleRoutes.isEmpty, mapView.bounds.width > 1, mapView.bounds.height > 1 else {
            return
        }

        overlayUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateVisibleRouteOverlays(preservesRenderedRoutes: preservesRenderedRoutes)
        }
        overlayUpdateWorkItem = workItem

        let delay: TimeInterval = immediate ? 0 : 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func updateVisibleRouteOverlays(preservesRenderedRoutes _: Bool = false) {
        guard !visibleRoutes.isEmpty, mapView.bounds.width > 1, mapView.bounds.height > 1 else {
            return
        }

        let loadingMapRect = routeLoadingMapRect()
        let candidateRoutes = visibleRoutes.filter { route in
            route.boundingMapRect.intersects(loadingMapRect)
        }
        let pointLimit = routePointLimitForCurrentZoom()
        let targetRoutes = Self.spatiallyDistributedRoutes(
            candidateRoutes,
            in: loadingMapRect,
            maximumCount: renderedRouteLimitForCurrentZoom()
        )

        overlayUpdateGeneration += 1
        let generation = overlayUpdateGeneration

        routeRenderQueue.async { [targetRoutes, pointLimit, loadingMapRect] in
            let renderedRoutes = Self.renderedRoutes(
                for: targetRoutes,
                pointLimit: pointLimit,
                mapRect: loadingMapRect
            )

            DispatchQueue.main.async { [weak self] in
                self?.replaceRenderedRoutes(
                    renderedRoutes,
                    generation: generation
                )
            }
        }
    }

    private func replaceRenderedRoutes(_ renderedRoutes: [HeatmapRenderedRoute], generation: Int) {
        guard generation == overlayUpdateGeneration else {
            return
        }

        routesOverlay.renderedRoutes = renderedRoutes
        invalidateRoutesOverlayRenderer()
    }

    private func invalidateRoutesOverlayRenderer() {
        routesOverlayRenderer?.setNeedsDisplay()
    }

    private func routeLoadingMapRect() -> MKMapRect {
        let visibleMapRect = mapView.visibleMapRect
        let dx = visibleMapRect.size.width * routeLoadingPaddingRatio
        let dy = visibleMapRect.size.height * routeLoadingPaddingRatio
        return visibleMapRect.insetBy(dx: -dx, dy: -dy)
    }

    private func routePointLimitForCurrentZoom() -> Int {
        let longitudeDelta = abs(mapView.region.span.longitudeDelta)

        switch longitudeDelta {
        case 8...:
            return min(maximumRoutePointCount, 56)
        case 3..<8:
            return min(maximumRoutePointCount, 80)
        case 1..<3:
            return min(maximumRoutePointCount, 120)
        case 0.35..<1:
            return min(maximumRoutePointCount, 180)
        default:
            return maximumRoutePointCount
        }
    }

    private func renderedRouteLimitForCurrentZoom() -> Int {
        let longitudeDelta = abs(mapView.region.span.longitudeDelta)

        switch longitudeDelta {
        case 3...:
            return 1_800
        case 1..<3:
            return 1_600
        case 0.35..<1:
            return 1_200
        default:
            return 760
        }
    }

    private static func spatiallyDistributedRoutes(
        _ routes: [HeatmapRoute],
        in mapRect: MKMapRect,
        maximumCount: Int
    ) -> [HeatmapRoute] {
        guard routes.count > maximumCount, maximumCount > 0 else {
            return routes
        }

        let gridSide = max(2, Int(sqrt(Double(maximumCount) / 2)))
        let rectWidth = max(mapRect.size.width, 1)
        let rectHeight = max(mapRect.size.height, 1)
        var buckets: [[HeatmapRoute]] = Array(repeating: [], count: gridSide * gridSide)

        for route in routes {
            let centerX = route.boundingMapRect.origin.x + route.boundingMapRect.size.width / 2
            let centerY = route.boundingMapRect.origin.y + route.boundingMapRect.size.height / 2
            let normalizedX = (centerX - mapRect.origin.x) / rectWidth
            let normalizedY = (centerY - mapRect.origin.y) / rectHeight
            let column = min(max(Int(normalizedX * Double(gridSide)), 0), gridSide - 1)
            let row = min(max(Int(normalizedY * Double(gridSide)), 0), gridSide - 1)
            buckets[row * gridSide + column].append(route)
        }

        var result: [HeatmapRoute] = []
        result.reserveCapacity(maximumCount)

        while result.count < maximumCount {
            var appendedRoute = false

            for index in buckets.indices where !buckets[index].isEmpty {
                result.append(buckets[index].removeFirst())
                appendedRoute = true

                if result.count == maximumCount {
                    break
                }
            }

            if !appendedRoute {
                break
            }
        }

        return result
    }

    private static func coordinates(
        for route: HeatmapRoute,
        maximumCount: Int
    ) -> [CLLocationCoordinate2D] {
        guard route.coordinates.count > maximumCount, maximumCount > 2 else {
            return route.coordinates
        }

        let indexes = sampledIndexes(sourceCount: route.coordinates.count, targetCount: maximumCount)
        return indexes.map { route.coordinates[$0] }
    }

    private static func statisticsWorkouts(from workouts: [TrackedWorkout]) -> [TrackedWorkout] {
        workouts.map { workout in
            workout.statisticsPreview()
        }
    }

    private static func cachedOrMakeHeatmapRoute(
        for workout: TrackedWorkout,
        samplingRatio: Double,
        maximumPointCount: Int,
        routeCacheStore: HeatmapRouteCacheStore
    ) -> HeatmapRoute? {
        if let cachedRoute = routeCacheStore.cachedRoute(
            for: workout,
            samplingRatio: samplingRatio,
            maximumPointCount: maximumPointCount
        ) {
            return cachedRoute
        }

        guard let route = makeHeatmapRoute(
            for: workout,
            samplingRatio: samplingRatio,
            maximumPointCount: maximumPointCount
        ) else {
            routeCacheStore.removeRoute(id: workout.id)
            return nil
        }

        routeCacheStore.store(
            route,
            for: workout,
            samplingRatio: samplingRatio,
            maximumPointCount: maximumPointCount
        )
        return route
    }

    private static func renderedRoutes(
        for routes: [HeatmapRoute],
        pointLimit: Int,
        mapRect: MKMapRect
    ) -> [HeatmapRenderedRoute] {
        guard !routes.isEmpty, pointLimit > 1 else {
            return []
        }

        var renderedRoutes: [HeatmapRenderedRoute] = []
        renderedRoutes.reserveCapacity(routes.count)

        for route in routes where route.boundingMapRect.intersects(mapRect) {
            if let renderedRoute = renderedRoute(
                for: route,
                pointLimit: pointLimit,
                mapRect: mapRect
            ) {
                renderedRoutes.append(renderedRoute)
            }
        }

        return renderedRoutes
    }

    private static func renderedRoute(
        for route: HeatmapRoute,
        pointLimit: Int,
        mapRect: MKMapRect
    ) -> HeatmapRenderedRoute? {
        let coordinates = coordinates(for: route, maximumCount: pointLimit)
        guard coordinates.count > 1 else {
            return nil
        }

        var mapPoints: [MKMapPoint] = []
        mapPoints.reserveCapacity(coordinates.count)
        var boundingMapRect = MKMapRect.null

        for coordinate in coordinates {
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                continue
            }

            let mapPoint = MKMapPoint(coordinate)
            mapPoints.append(mapPoint)
            boundingMapRect = boundingMapRect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 1, height: 1))
        }

        guard mapPoints.count > 1, boundingMapRect.intersects(mapRect) else {
            return nil
        }

        return HeatmapRenderedRoute(
            id: route.id,
            mapPoints: mapPoints,
            boundingMapRect: boundingMapRect,
            pointLimit: pointLimit
        )
    }

    private static func makeHeatmapRoute(
        for workout: TrackedWorkout,
        samplingRatio: Double,
        maximumPointCount: Int
    ) -> HeatmapRoute? {
        let sourceCoordinates = workout.coordinates
        guard sourceCoordinates.count > 1 else {
            return nil
        }

        let targetCount = min(
            max(Int(Double(sourceCoordinates.count) * samplingRatio), 2),
            maximumPointCount
        )
        let coordinateIndexes = sampledIndexes(sourceCount: sourceCoordinates.count, targetCount: targetCount)
        let sampledCoordinates = coordinateIndexes.map { sourceCoordinates[$0].coordinate }
        let preparedRoute = validDisplayCoordinates(for: sampledCoordinates)

        guard preparedRoute.coordinates.count > 1,
              !preparedRoute.boundingMapRect.isNull else {
            return nil
        }

        return HeatmapRoute(
            id: workout.id,
            coordinates: preparedRoute.coordinates,
            boundingMapRect: preparedRoute.boundingMapRect,
            sportKind: workout.sportKind,
            startYear: Calendar.current.component(.year, from: workout.startDate)
        )
    }

    private static func validDisplayCoordinates(
        for sourceCoordinates: [CLLocationCoordinate2D]
    ) -> (coordinates: [CLLocationCoordinate2D], boundingMapRect: MKMapRect) {
        let displayCoordinates = CoordinateTransformer.displayCoordinates(for: sourceCoordinates)
        var validDisplayCoordinates: [CLLocationCoordinate2D] = []
        validDisplayCoordinates.reserveCapacity(displayCoordinates.count)
        var boundingMapRect = MKMapRect.null

        for coordinate in displayCoordinates {
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                continue
            }

            let point = MKMapPoint(coordinate)
            validDisplayCoordinates.append(coordinate)
            boundingMapRect = boundingMapRect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

        return (validDisplayCoordinates, boundingMapRect)
    }

    private static func boundingMapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect? {
        var boundingMapRect = MKMapRect.null

        for coordinate in coordinates {
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                continue
            }

            let point = MKMapPoint(coordinate)
            boundingMapRect = boundingMapRect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

        return boundingMapRect.isNull ? nil : boundingMapRect
    }

    private static func sampledIndexes(sourceCount: Int, targetCount: Int) -> [Int] {
        guard sourceCount > targetCount, targetCount > 2 else {
            return Array(0..<sourceCount)
        }

        let step = Double(sourceCount - 1) / Double(targetCount - 1)
        return (0..<targetCount).map { index in
            min(Int(round(Double(index) * step)), sourceCount - 1)
        }
    }
}

extension WorkoutRouteHeatmapViewController: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === sportsCareerSheetViewController else {
            return
        }

        hasPresentedSportsCareerSheet = false
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ sheetPresentationController: UISheetPresentationController
    ) {
        guard sheetPresentationController.presentedViewController === sportsCareerSheetViewController else {
            return
        }

        let isCollapsed = sheetPresentationController.selectedDetentIdentifier == Self.careerCollapsedDetentIdentifier
        sportsCareerSheetViewController.setHeatmapSheetContentVisible(!isCollapsed, animated: true)
    }
}
