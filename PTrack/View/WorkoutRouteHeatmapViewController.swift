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

    private static let routeCache: NSCache<NSString, HeatmapRouteCacheBox> = {
        let cache = NSCache<NSString, HeatmapRouteCacheBox>()
        cache.countLimit = 3
        return cache
    }()

    private let workouts: [TrackedWorkout]
    private let mapContainerView = AppMapContainerView()
    private var mapView: MKMapView { mapContainerView.mapView }
    private let mapToneOverlay = AppMapStyle.makeToneOverlay()
    private let routesOverlay = HeatmapRoutesOverlay()
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let navigationBackgroundMask = CAGradientLayer()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var sportsCareerSheetViewController: SportsCareerViewController = {
        let viewController = SportsCareerViewController(
            workouts: workouts,
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
    private var hasPresentedSportsCareerSheet = false
    private var suppressSportsCareerSheetPresentation = false
    private var selectedFilters = HeatmapFilterStore.shared.selectedFilters()
    private var selectedMapStyle = AppMapDisplayStyleStore.shared.heatmapStyle()
    var routesOverlayRenderer: HeatmapRoutesOverlayRenderer?
    private var renderedRoutesByID: [String: HeatmapRenderedRoute] = [:]
    private var overlayUpdateWorkItem: DispatchWorkItem?
    private var progressiveOverlayWorkItem: DispatchWorkItem?
    private var overlayUpdateGeneration = 0

    private let routeSamplingRatio = 0.8
    private let maximumRoutePointCount = 360
    private let navigationBackgroundHeight: CGFloat = 124
    private let routeLoadingPaddingRatio = 0.42
    private let routeOverlayBatchSize = 28
    private let maximumActiveRouteOverlayCount = 420

    init(workouts: [TrackedWorkout]) {
        self.workouts = workouts
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
        prepareHeatmapRoutes()
    }

    deinit {
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
           isMovingFromParent || navigationController?.isBeingDismissed == true {
            hasPresentedSportsCareerSheet = false
            sportsCareerSheetViewController.dismiss(animated: false)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNavigationBackgroundMask()
        fitRoutesIfNeeded()
        scheduleVisibleRouteOverlayUpdate()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .darkContent
    }

    private func configureNavigationItem() {
        title = AppLocalization.text(.routeHeatmap)
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = makeMoreBarButtonItem()
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
        title = AppLocalization.text(.routeHeatmap)
        navigationItem.rightBarButtonItem = makeMoreBarButtonItem()
    }

    private func makeMoreBarButtonItem() -> UIBarButtonItem {
        let barButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: makeMoreMenu()
        )
        return barButtonItem
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
        loadingIndicator.startAnimating()

        view.addSubview(loadingIndicator)

        loadingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func makeMoreMenu() -> UIMenu {
        let filterActions = HeatmapFilter.allCases.map { filter in
            UIAction(
                title: filter.title,
                image: filter.image,
                attributes: [.keepsMenuPresented],
                state: selectedFilters.contains(filter) ? .on : .off
            ) { [weak self] _ in
                self?.toggleFilter(filter)
            }
        }

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
            children: [
                UIMenu(title: AppLocalization.text(.sportType), image: UIImage(systemName: "figure.walk"), children: filterActions),
                UIMenu(title: AppLocalization.text(.mapStyle), image: UIImage(systemName: "map"), children: mapStyleActions)
            ]
        )
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
            let detailViewController = WorkoutRouteDetailViewController(workout: workout)
            self?.navigationController?.pushViewController(detailViewController, animated: true)
        }
    }

    private func prepareHeatmapRoutes() {
        loadGeneration += 1
        let generation = loadGeneration
        let workouts = workouts
        let samplingRatio = routeSamplingRatio
        let maximumRoutePointCount = maximumRoutePointCount
        let cacheKey = Self.cacheKey(
            for: workouts,
            samplingRatio: samplingRatio,
            maximumPointCount: maximumRoutePointCount
        )

        if let cachedRoutes = Self.routeCache.object(forKey: cacheKey)?.routes {
            preparedRoutes = cachedRoutes
            applySelectedFilters(resetCamera: true)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var routes: [HeatmapRoute] = []
            routes.reserveCapacity(workouts.count)

            for workout in workouts {
                let route = Self.makeHeatmapRoute(
                    for: workout,
                    samplingRatio: samplingRatio,
                    maximumPointCount: maximumRoutePointCount
                )
                guard let route else {
                    continue
                }

                routes.append(route)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadGeneration == generation else {
                    return
                }

                Self.routeCache.setObject(HeatmapRouteCacheBox(routes: routes), forKey: cacheKey)
                self.preparedRoutes = routes
                self.applySelectedFilters(resetCamera: true)
            }
        }
    }

    private static func cacheKey(
        for workouts: [TrackedWorkout],
        samplingRatio: Double,
        maximumPointCount: Int
    ) -> NSString {
        var hasher = Hasher()
        hasher.combine(workouts.count)
        hasher.combine(samplingRatio)
        hasher.combine(maximumPointCount)

        for workout in workouts {
            hasher.combine(workout.id)
            hasher.combine(workout.coordinates.count)
            hasher.combine(workout.sportKind.rawValue)
        }

        return "\(workouts.count)-\(hasher.finalize())" as NSString
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

        HeatmapFilterStore.shared.setSelectedFilters(selectedFilters)
        applySelectedFilters(resetCamera: true)
    }

    private func applySelectedFilters(resetCamera: Bool) {
        navigationItem.rightBarButtonItem = makeMoreBarButtonItem()

        visibleRoutes = preparedRoutes.filter { route in
            selectedFilters.contains { filter in
                filter.includes(route.sportKind)
            }
        }
        clearRouteOverlays()

        if resetCamera {
            fitMap(to: visibleRoutes, animated: true)
        }

        if !visibleRoutes.isEmpty {
            scheduleVisibleRouteOverlayUpdate(immediate: true)
        }

        loadingIndicator.stopAnimating()
    }

    private func applyMapStyle(_ style: AppMapDisplayStyle) {
        guard style != selectedMapStyle else {
            return
        }

        selectedMapStyle = style
        AppMapDisplayStyleStore.shared.setHeatmapStyle(style)
        AppMapStyle.apply(style, to: mapView)
        AppMapStyle.setToneOverlay(mapToneOverlay, visible: style == .appDefault, on: mapView)
        navigationItem.rightBarButtonItem = makeMoreBarButtonItem()
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

    private func clearRouteOverlays() {
        overlayUpdateGeneration += 1
        overlayUpdateWorkItem?.cancel()
        progressiveOverlayWorkItem?.cancel()
        overlayUpdateWorkItem = nil
        progressiveOverlayWorkItem = nil

        renderedRoutesByID.removeAll(keepingCapacity: true)
        publishRenderedRoutes()
    }

    func suspendProgressiveRouteLoading() {
        overlayUpdateGeneration += 1
        overlayUpdateWorkItem?.cancel()
        progressiveOverlayWorkItem?.cancel()
        overlayUpdateWorkItem = nil
        progressiveOverlayWorkItem = nil
    }

    func scheduleVisibleRouteOverlayUpdate(immediate: Bool = false) {
        guard !visibleRoutes.isEmpty, mapView.bounds.width > 1, mapView.bounds.height > 1 else {
            return
        }

        overlayUpdateWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateVisibleRouteOverlays()
        }
        overlayUpdateWorkItem = workItem

        let delay: TimeInterval = immediate ? 0 : 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func updateVisibleRouteOverlays() {
        guard !visibleRoutes.isEmpty, mapView.bounds.width > 1, mapView.bounds.height > 1 else {
            return
        }

        let loadingMapRect = routeLoadingMapRect()
        let candidateRoutes = visibleRoutes.filter { route in
            route.boundingMapRect.intersects(loadingMapRect)
        }
        let targetRoutes = spatiallyDistributedRoutes(
            candidateRoutes,
            in: loadingMapRect,
            maximumCount: maximumActiveRouteOverlayCount
        )
        let targetRouteIDs = Set(targetRoutes.map(\.id))
        let obsoleteRouteIDs = renderedRoutesByID.keys.filter { !targetRouteIDs.contains($0) }

        let pointLimit = overlayPointLimitForCurrentZoom()
        let routesNeedingOverlay = targetRoutes.filter { route in
            renderedRoutesByID[route.id]?.pointLimit != pointLimit
        }
        guard !routesNeedingOverlay.isEmpty else {
            removeRenderedRoutes(withIDs: Array(obsoleteRouteIDs))
            publishRenderedRoutes()
            return
        }

        overlayUpdateGeneration += 1
        progressiveOverlayWorkItem?.cancel()
        addRouteOverlaysProgressively(
            routesNeedingOverlay,
            startIndex: 0,
            generation: overlayUpdateGeneration,
            pointLimit: pointLimit,
            obsoleteRouteIDs: Array(obsoleteRouteIDs)
        )
    }

    private func addRouteOverlaysProgressively(
        _ routes: [HeatmapRoute],
        startIndex: Int,
        generation: Int,
        pointLimit: Int,
        obsoleteRouteIDs: [String] = []
    ) {
        guard generation == overlayUpdateGeneration, startIndex < routes.count else {
            return
        }

        let endIndex = min(startIndex + routeOverlayBatchSize, routes.count)

        for route in routes[startIndex..<endIndex] where renderedRoutesByID[route.id]?.pointLimit != pointLimit {
            guard let renderedRoute = Self.renderedRoute(for: route, maximumCount: pointLimit) else {
                continue
            }

            renderedRoutesByID[route.id] = renderedRoute
        }

        if startIndex == 0 {
            removeRenderedRoutes(withIDs: obsoleteRouteIDs)
        }
        publishRenderedRoutes()

        guard endIndex < routes.count else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.addRouteOverlaysProgressively(
                routes,
                startIndex: endIndex,
                generation: generation,
                pointLimit: pointLimit
            )
        }
        progressiveOverlayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: workItem)
    }

    private func removeRenderedRoutes(withIDs routeIDs: [String]) {
        guard !routeIDs.isEmpty else {
            return
        }

        for routeID in routeIDs {
            renderedRoutesByID.removeValue(forKey: routeID)
        }
    }

    private func publishRenderedRoutes() {
        routesOverlay.renderedRoutes = Array(renderedRoutesByID.values)
        routesOverlayRenderer?.setNeedsDisplay()
    }

    private func routeLoadingMapRect() -> MKMapRect {
        let visibleMapRect = mapView.visibleMapRect
        let dx = visibleMapRect.size.width * routeLoadingPaddingRatio
        let dy = visibleMapRect.size.height * routeLoadingPaddingRatio
        return visibleMapRect.insetBy(dx: -dx, dy: -dy)
    }

    private func overlayPointLimitForCurrentZoom() -> Int {
        let longitudeDelta = abs(mapView.region.span.longitudeDelta)

        switch longitudeDelta {
        case 8...:
            return min(maximumRoutePointCount, 88)
        case 2..<8:
            return min(maximumRoutePointCount, 144)
        case 0.7..<2:
            return min(maximumRoutePointCount, 220)
        default:
            return maximumRoutePointCount
        }
    }

    private func spatiallyDistributedRoutes(
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

    private static func coordinates(for route: HeatmapRoute, maximumCount: Int) -> [CLLocationCoordinate2D] {
        guard route.coordinates.count > maximumCount, maximumCount > 2 else {
            return route.coordinates
        }

        let indexes = sampledIndexes(sourceCount: route.coordinates.count, targetCount: maximumCount)
        return indexes.map { route.coordinates[$0] }
    }

    private static func renderedRoute(
        for route: HeatmapRoute,
        maximumCount: Int
    ) -> HeatmapRenderedRoute? {
        let coordinates = coordinates(for: route, maximumCount: maximumCount)
        guard coordinates.count > 1 else {
            return nil
        }

        return HeatmapRenderedRoute(
            id: route.id,
            coordinates: coordinates,
            boundingMapRect: route.boundingMapRect,
            pointLimit: maximumCount
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
        let displayCoordinates = CoordinateTransformer.displayCoordinates(for: sampledCoordinates)
        var mapPoints: [MKMapPoint] = []
        mapPoints.reserveCapacity(displayCoordinates.count)
        var boundingMapRect = MKMapRect.null

        for coordinate in displayCoordinates {
            guard CLLocationCoordinate2DIsValid(coordinate) else {
                continue
            }

            let point = MKMapPoint(coordinate)
            mapPoints.append(point)
            boundingMapRect = boundingMapRect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

        guard mapPoints.count > 1, !boundingMapRect.isNull else {
            return nil
        }

        return HeatmapRoute(
            id: workout.id,
            coordinates: displayCoordinates,
            boundingMapRect: boundingMapRect,
            sportKind: workout.sportKind
        )
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
