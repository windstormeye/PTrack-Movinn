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
    private static let routeCache: NSCache<NSString, HeatmapRouteCacheBox> = {
        let cache = NSCache<NSString, HeatmapRouteCacheBox>()
        cache.countLimit = 3
        return cache
    }()

    private let workouts: [TrackedWorkout]
    private let mapView = MKMapView()
    private let mapToneOverlay = HeatmapToneTileOverlay()
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let navigationBackgroundMask = CAGradientLayer()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let filterButton = UIButton(type: .system)

    private var preparedRoutes: [HeatmapRoute] = []
    private var visibleRoutes: [HeatmapRoute] = []
    private var loadGeneration = 0
    private var hasFittedRoutes = false
    private var selectedFilter: HeatmapFilter = .all
    private var routeOverlays: [MKPolyline] = []

    private let routeSamplingRatio = 0.8
    private let maximumRoutePointCount = 360
    private let navigationBackgroundHeight: CGFloat = 124

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
        configureMapView()
        configureNavigationBackgroundView()
        configureFilterButton()
        configureLoadingIndicator()
        prepareHeatmapRoutes()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        configureNavigationBar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNavigationBackgroundMask()
        fitRoutesIfNeeded()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .darkContent
    }

    private func configureNavigationItem() {
        title = "路线热图"
        navigationItem.largeTitleDisplayMode = .never
        edgesForExtendedLayout = [.top, .bottom]
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
        configureHeatmapMapStyle()
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.backgroundColor = .systemBackground

        view.addSubview(mapView)

        mapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        mapView.addOverlay(mapToneOverlay, level: .aboveRoads)
    }

    private func configureHeatmapMapStyle() {
        mapView.overrideUserInterfaceStyle = .light

        if #available(iOS 16.0, *) {
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.emphasisStyle = .muted
            configuration.pointOfInterestFilter = .excludingAll
            mapView.preferredConfiguration = configuration
        } else {
            mapView.mapType = .mutedStandard
        }
    }

    private func configureLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.startAnimating()

        view.addSubview(loadingIndicator)

        loadingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    private func configureFilterButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(
            systemName: "line.3.horizontal",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = .systemBackground.withAlphaComponent(0.82)
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        configuration.cornerStyle = .capsule

        filterButton.configuration = configuration
        filterButton.showsMenuAsPrimaryAction = true
        filterButton.layer.shadowColor = UIColor.black.cgColor
        filterButton.layer.shadowOpacity = 0.14
        filterButton.layer.shadowRadius = 10
        filterButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        updateFilterMenu()

        view.addSubview(filterButton)

        filterButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(18)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(18)
            make.size.equalTo(48)
        }
    }

    private func updateFilterMenu() {
        let actions = HeatmapFilter.allCases.map { filter in
            UIAction(
                title: filter.title,
                state: filter == selectedFilter ? .on : .off
            ) { [weak self] _ in
                self?.applyFilter(filter, resetCamera: true)
            }
        }

        filterButton.menu = UIMenu(title: "", options: .displayInline, children: actions)
        filterButton.accessibilityLabel = "切换热图类型"
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
            applyFilter(selectedFilter, resetCamera: true)
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
                self.applyFilter(self.selectedFilter, resetCamera: true)
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
        }

        return "\(workouts.count)-\(hasher.finalize())" as NSString
    }

    private func fitRoutesIfNeeded() {
        guard !hasFittedRoutes, !visibleRoutes.isEmpty else {
            return
        }

        fitMap(to: visibleRoutes, animated: false)
    }

    private func applyFilter(_ filter: HeatmapFilter, resetCamera: Bool) {
        selectedFilter = filter
        updateFilterMenu()

        visibleRoutes = preparedRoutes.filter { route in
            filter.includes(route.activityType)
        }
        updateRouteOverlay()

        if resetCamera {
            fitMap(to: visibleRoutes, animated: true)
        }

        guard !visibleRoutes.isEmpty else {
            loadingIndicator.stopAnimating()
            return
        }

        loadingIndicator.stopAnimating()
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
            edgePadding: UIEdgeInsets(top: 96, left: 32, bottom: 72, right: 32),
            animated: animated
        )
    }

    private func updateRouteOverlay() {
        if !routeOverlays.isEmpty {
            mapView.removeOverlays(routeOverlays)
            routeOverlays.removeAll(keepingCapacity: true)
        }

        guard !visibleRoutes.isEmpty else {
            return
        }

        let polylines = visibleRoutes.map { route in
            MKPolyline(coordinates: route.coordinates, count: route.coordinates.count)
        }
        routeOverlays = polylines
        mapView.addOverlays(polylines, level: .aboveLabels)
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
            coordinates: displayCoordinates,
            boundingMapRect: boundingMapRect,
            activityType: workout.activityType
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
