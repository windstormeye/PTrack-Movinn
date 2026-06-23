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
    private var knownWorkoutIDs: Set<String>
    private var statisticWorkouts: [TrackedWorkout]
    private var knownStatisticWorkoutIDs: Set<String>
    private let cacheStore = WorkoutCacheStore()
    private let cacheLoadQueue = DispatchQueue(label: "studio.pj.PTrack.heatmap-cache-load", qos: .userInitiated)
    private let routeRenderQueue = DispatchQueue(label: "studio.pj.PTrack.heatmap-render", qos: .userInitiated)
    private let mapContainerView = AppMapContainerView()
    private var mapView: MKMapView { mapContainerView.mapView }
    private let mapToneOverlay = AppMapStyle.makeToneOverlay()
    private let routesOverlay = HeatmapRoutesOverlay()
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let navigationBackgroundMask = CAGradientLayer()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let cacheLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private let navigationTitleLabel = UILabel()
    private lazy var moreBarButtonItem = makeMoreBarButtonItem()
    private lazy var navigationTitleView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [navigationTitleLabel, cacheLoadingIndicator])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 7
        return stackView
    }()
    private lazy var sportsCareerSheetViewController: SportsCareerViewController = {
        let viewController = SportsCareerViewController(
            workouts: statisticWorkouts,
            presentationStyle: .heatmapSheet
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
    private var loadGeneration = 0
    private var hasFittedRoutes = false
    private var hasUserAdjustedMapRegion = false
    private var hasPresentedSportsCareerSheet = false
    private var suppressSportsCareerSheetPresentation = false
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
    private var overlayUpdateGeneration = 0
    private var cacheLoadGeneration = 0
    private var isLoadingCachedWorkouts = false
    private var hasStartedHeatmapLoading = false

    private let routeSamplingRatio = 1.0
    private let maximumRoutePointCount = 320
    private let navigationBackgroundHeight: CGFloat = 124
    private let routeLoadingPaddingRatio = 0.08
    private let cacheLoadBatchSize = 8
    private let maximumPreparedRoutePoolCount = 1_800
    private let regionCacheReloadDelay: TimeInterval = 0.45

    init(workouts: [TrackedWorkout]) {
        self.workouts = workouts
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
        updateNavigationBackgroundMask()
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
        .darkContent
    }

    private var isPermanentlyLeaving: Bool {
        isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true
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

    private func makeMoreBarButtonItem() -> UIBarButtonItem {
        let barButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: makeMoreMenu()
        )
        return barButtonItem
    }

    private func updateNavigationRightBarButtonItems() {
        moreBarButtonItem.menu = makeMoreMenu()
        navigationItem.rightBarButtonItem = moreBarButtonItem
    }

    private func setCachedWorkoutLoading(_ isLoading: Bool) {
        guard isLoadingCachedWorkouts != isLoading else {
            return
        }

        isLoadingCachedWorkouts = isLoading
        if isLoading {
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
        navigationBackgroundView.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.42)
        navigationBackgroundMask.colors = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0.78).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ]
        navigationBackgroundMask.locations = [0, 0.58, 1]
        navigationBackgroundView.layer.mask = navigationBackgroundMask

        view.addSubview(navigationBackgroundView)

        navigationBackgroundView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(navigationBackgroundHeight)
        }
    }

    private func updateNavigationBackgroundMask() {
        navigationBackgroundMask.frame = navigationBackgroundView.bounds
        navigationBackgroundMask.startPoint = CGPoint(x: 0.5, y: 0)
        navigationBackgroundMask.endPoint = CGPoint(x: 0.5, y: 1)
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
        statisticWorkouts.removeAll(keepingCapacity: false)
        knownStatisticWorkoutIDs.removeAll(keepingCapacity: false)
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
        prepareHeatmapRoutes()
        loadCachedWorkoutsProgressively()
    }

    private func loadCachedWorkoutsProgressively() {
        cacheLoadGeneration += 1
        let generation = cacheLoadGeneration
        setCachedWorkoutLoading(true)
        let cacheStore = cacheStore
        let cacheLoadBatchSize = cacheLoadBatchSize
        let samplingRatio = routeSamplingRatio
        let maximumRoutePointCount = maximumRoutePointCount
        let selectedFilters = selectedFilters
        let selectedYear = selectedYear

        cacheLoadQueue.async { [weak self, cacheStore, cacheLoadBatchSize] in
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

                    let statisticWorkouts = Self.statisticsWorkouts(from: cachedWorkoutBatch)
                    let routes = cachedWorkoutBatch.compactMap { workout -> HeatmapRoute? in
                        let isIncludedBySport = selectedFilters.contains { filter in
                            filter.includes(workout.sportKind)
                        }
                        let isIncludedByYear = selectedYear.map {
                            Calendar.current.component(.year, from: workout.startDate) == $0
                        } ?? true

                        guard isIncludedBySport && isIncludedByYear else {
                            return nil
                        }

                        return Self.makeHeatmapRoute(
                            for: workout,
                            samplingRatio: samplingRatio,
                            maximumPointCount: maximumRoutePointCount
                        )
                    }
                    guard !routes.isEmpty else {
                        DispatchQueue.main.async { [weak self] in
                            self?.mergeCachedHeatmapBatch(
                                routes: [],
                                statisticWorkouts: statisticWorkouts,
                                generation: generation
                            )
                        }
                        return
                    }

                    DispatchQueue.main.async { [weak self] in
                        self?.mergeCachedHeatmapBatch(
                            routes: routes,
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

                self.setCachedWorkoutLoading(false)
                self.scheduleSportsCareerStatisticsUpdate(immediate: true, animated: true)
            }
        }
    }

    private func mergeCachedHeatmapBatch(
        routes: [HeatmapRoute],
        statisticWorkouts: [TrackedWorkout],
        generation: Int
    ) {
        guard cacheLoadGeneration == generation else {
            return
        }

        mergeStatisticWorkouts(statisticWorkouts)
        guard !routes.isEmpty else {
            return
        }

        let loadingMapRect = routeLoadingMapRect()
        availableRouteYearValues.formUnion(routes.map(\.startYear))
        var didAppendRoute = false
        var didAppendVisibleRoute = false

        preparedRoutes.reserveCapacity(preparedRoutes.count + routes.count)
        for route in routes where route.boundingMapRect.intersects(loadingMapRect) && knownWorkoutIDs.insert(route.id).inserted {
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
            sportsCareerSheetViewController.updateWorkouts(statisticWorkouts, animated: animated)
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
                self.statisticWorkouts,
                animated: animated
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

        let mapStyleActions = AppMapDisplayStyle.menuCases.map { style in
            UIAction(
                title: style.title,
                state: style == selectedMapStyle ? .on : .off
            ) { [weak self] _ in
                self?.applyMapStyle(style)
            }
        }

        return UIMenu(
            title: "",
            identifier: UIMenu.Identifier("studio.pj.PTrack.heatmap.more"),
            children: [
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

    private func makeTimeMenuActions() -> [UIMenuElement] {
        var actions: [UIMenuElement] = [
            UIAction(
                title: AppLocalization.text(.all),
                state: selectedYear == nil ? .on : .off
            ) { [weak self] _ in
                self?.applyYearFilter(nil)
            }
        ]

        actions.append(contentsOf: availableRouteYears().map { year in
            UIAction(
                title: "\(year)",
                state: selectedYear == year ? .on : .off
            ) { [weak self] _ in
                self?.applyYearFilter(year)
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
            attributes: [.keepsMenuPresented],
            state: selectedFilters.contains(filter) ? .on : .off
        ) { [weak self] _ in
            self?.toggleFilter(filter)
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

            let resolvedWorkout = self.cacheStore.loadWorkout(id: workout.id) ?? workout
            let detailViewController = WorkoutRouteDetailViewController(workout: resolvedWorkout)
            self.navigationController?.pushViewController(detailViewController, animated: true)
        }
    }

    private func prepareHeatmapRoutes(resetCamera: Bool = true, preservesRenderedRoutes: Bool = false) {
        loadGeneration += 1
        let generation = loadGeneration
        let workouts = workouts
        let samplingRatio = routeSamplingRatio
        let maximumRoutePointCount = maximumRoutePointCount
        let routePoolMapRect = routeLoadingMapRect()
        let maximumPreparedRoutePoolCount = maximumPreparedRoutePoolCount

        DispatchQueue.global(qos: .userInitiated).async {
            var routes: [HeatmapRoute] = []
            routes.reserveCapacity(min(workouts.count, maximumPreparedRoutePoolCount))

            for workout in workouts {
                let route = Self.makeHeatmapRoute(
                    for: workout,
                    samplingRatio: samplingRatio,
                    maximumPointCount: maximumRoutePointCount
                )
                guard let route else {
                    continue
                }

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
        guard !hasFittedRoutes, !visibleRoutes.isEmpty else {
            return
        }

        fitMap(to: visibleRoutes, animated: false)
    }

    private func toggleFilter(_ filter: HeatmapFilter) {
        if selectedFilters.contains(filter) {
            selectedFilters.remove(filter)
        } else {
            selectedFilters.insert(filter)
        }

        updateFilterMenuActionStates()
        HeatmapFilterStore.shared.setSelectedFilters(selectedFilters)
        cancelCachedWorkoutLoading()
        applySelectedFilters(resetCamera: true, preservesRenderedRoutes: false)
        scheduleCurrentRegionCacheReload()
    }

    private func applyYearFilter(_ year: Int?) {
        guard selectedYear != year else {
            return
        }

        selectedYear = year
        cancelCachedWorkoutLoading()
        applySelectedFilters(resetCamera: true, preservesRenderedRoutes: false)
        scheduleCurrentRegionCacheReload()
    }

    private func cancelCachedWorkoutLoading() {
        cacheLoadGeneration += 1
        setCachedWorkoutLoading(false)
    }

    private func applySelectedFilters(resetCamera: Bool, preservesRenderedRoutes: Bool) {
        visibleRoutes = preparedRoutes.filter(isRouteIncludedBySelectedFilters)
        if !preservesRenderedRoutes {
            resetRenderedRouteState(removesCache: true)
        }

        if resetCamera {
            fitMap(to: visibleRoutes, animated: true)
        }

        if !visibleRoutes.isEmpty {
            scheduleVisibleRouteOverlayUpdate(
                immediate: true,
                preservesRenderedRoutes: preservesRenderedRoutes
            )
        }

        loadingIndicator.stopAnimating()
    }

    private func isRouteIncludedBySelectedFilters(_ route: HeatmapRoute) -> Bool {
        let isIncludedBySport = selectedFilters.contains { filter in
            filter.includes(route.sportKind)
        }
        let isIncludedByYear = selectedYear.map { route.startYear == $0 } ?? true
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

    private func fitMap(to routes: [HeatmapRoute], animated: Bool) {
        let boundingMapRect = routes.reduce(MKMapRect.null) { rect, route in
            rect.union(route.boundingMapRect)
        }

        guard !boundingMapRect.isNull,
              mapView.bounds.width > 1,
              mapView.bounds.height > 1 else {
            return
        }

        hasFittedRoutes = true
        mapView.setVisibleMapRect(
            boundingMapRect,
            edgePadding: UIEdgeInsets(
                top: 96,
                left: 32,
                bottom: SportsCareerViewController.heatmapSheetCollapsedHeight + 28,
                right: 32
            ),
            animated: animated
        )
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

        trimPreparedRoutePool(to: routeLoadingMapRect())
        prepareHeatmapRoutes(resetCamera: false, preservesRenderedRoutes: true)
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
