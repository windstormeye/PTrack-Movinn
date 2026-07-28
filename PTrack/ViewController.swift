//
//  ViewController.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import AuthenticationServices
import CoreLocation
import MapKit
import OSLog
import SnapKit
import HealthKit
import UIKit

class ViewController: UIViewController {
    private enum DefaultsKey {
        static let healthHistoricalBackfillCompleted = "studio.pj.PTrack.health.historicalBackfillCompleted"
        static let healthHistoricalBackfillCacheCommitCompleted = "studio.pj.PTrack.health.historicalBackfillCacheCommitCompleted"
        static let healthCacheIntegrityRepairVersion = "studio.pj.PTrack.health.cacheIntegrityRepairVersion"
        static let healthLastFullCoverageReconciliationDate = "studio.pj.PTrack.health.lastFullCoverageReconciliationDate"
        static let healthImportInProgress = "studio.pj.PTrack.health.importInProgress"
        static let stravaHistoricalBackfillCompleted = "studio.pj.PTrack.strava.historicalBackfillCompleted"
        static let stravaHistoricalBackfillCacheCommitCompleted = "studio.pj.PTrack.strava.historicalBackfillCacheCommitCompleted"
        static let stravaCacheIntegrityRepairVersion = "studio.pj.PTrack.strava.cacheIntegrityRepairVersion"
        static let stravaLastFullCoverageReconciliationDate = "studio.pj.PTrack.strava.lastFullCoverageReconciliationDate"
        static let stravaLastPlaceholderEnrichmentAttemptDate = "studio.pj.PTrack.strava.lastPlaceholderEnrichmentAttemptDate"
        static let stravaImportInProgress = "studio.pj.PTrack.strava.importInProgress"
        static let homeRouteGridColumnCount = "studio.pj.PTrack.home.routeGridColumnCount"
    }

    private enum AppleFitnessDestination {
        static let applicationURLString = "fitnessapp://"
        static let appStoreURLString = "https://apps.apple.com/app/apple-fitness/id1208224953"
    }

    private enum RouteBookPanelDetent {
        case minimum
        case medium
    }

    private struct RouteBookRouteMatch {
        let progress: CGFloat
        let coordinate: CLLocationCoordinate2D
        let routeDistance: CLLocationDistance
        let segmentIndex: Int
        let segmentProjection: Double
    }

    private struct RouteBookMatchCache {
        let timestamp: Date
        let latitude: CLLocationDegrees
        let longitude: CLLocationDegrees
        let horizontalAccuracy: CLLocationAccuracy
        let match: RouteBookRouteMatch?

        func matches(_ location: CLLocation) -> Bool {
            timestamp == location.timestamp
                && latitude == location.coordinate.latitude
                && longitude == location.coordinate.longitude
                && horizontalAccuracy == location.horizontalAccuracy
        }
    }

    private struct RouteBookProjection {
        let distanceSquared: Double
        let projectedPoint: MKMapPoint
        let routeDistance: CLLocationDistance
        let segmentIndex: Int
        let segmentProjection: Double
    }

    private nonisolated struct RouteBookMatchingGeometry: Sendable {
        let coordinates: [CLLocationCoordinate2D]
        let cumulativeDistances: [CLLocationDistance]
        let segmentStartIndices: Set<Int>
        let sourceIndices: [Int]
    }

    private nonisolated struct PreparedRouteBookSlopeSegment: Sendable {
        let segmentIndex: Int
        let coordinates: [CLLocationCoordinate2D]
        let sourceLocations: [Double]
        let gradient: RouteSlopeGradient
        let totalDistance: CLLocationDistance
    }

    private struct PreparedRouteBook {
        let coordinates: [CLLocationCoordinate2D]
        let boundingMapRect: MKMapRect
        let replayDistances: [CLLocationDistance]
        let replayAltitudes: [Double?]
        let segmentStartIndices: Set<Int>
        let elevationSamples: [RouteElevationSample]
        let slopeSegments: [PreparedRouteBookSlopeSegment]
        let viewportGeometry: RouteViewportDistanceResolver.PreparedGeometry
        let displayGeometry: RouteViewportDistanceResolver.PreparedGeometry
        let matchingGeometry: RouteBookMatchingGeometry
    }

    private let store = HealthWorkoutStore()
    private let cacheStore = WorkoutCacheStore()
    private let routeCollectionStore = RouteCollectionStore()
    private let syncCoordinator = WorkoutSyncCoordinator()
    private let syncStateStore = WorkoutSyncStateStore()
    let newWorkoutBadgeStore = NewWorkoutBadgeStore()
    private let cacheLoadQueue = DispatchQueue(label: "studio.pj.PTrack.cache-load", qos: .userInitiated)
    private let cacheSaveQueue = DispatchQueue(label: "studio.pj.PTrack.cache-save", qos: .utility)
    private let routeSourcePrewarmQueue = DispatchQueue(label: "studio.pj.PTrack.route-source-prewarm", qos: .utility)
    private let routeBookPreparationQueue = DispatchQueue(label: "studio.pj.PTrack.route-book-prepare", qos: .userInitiated)
    var workouts: [TrackedWorkout] = []
    private var knownWorkoutIDs = Set<String>()
    private var workoutIndexByID: [String: Int] = [:]
    private var pendingWorkoutIndexByID: [String: Int] = [:]
    private var directStravaWorkoutsByStartDate: [Date: [TrackedWorkout]] = [:]
    private var healthWorkoutsByStartDate: [Date: [TrackedWorkout]] = [:]
    private var pendingWorkouts: [TrackedWorkout] = []
    private var pendingFlushWorkItem: DispatchWorkItem?
    private var pendingCacheSaveWorkItem: DispatchWorkItem?
    private var cacheSaveCompletionHandlers: [() -> Void] = []
    private var dirtyCacheWorkoutIDs = Set<String>()
    private var deletedCacheWorkoutIDs = Set<String>()
    private var isCacheSaveInProgress = false
    private var needsCacheSaveAfterCurrentSave = false
    private var consecutiveCacheSaveFailureCount = 0
    private var backgroundCacheSaveTask: UIBackgroundTaskIdentifier = .invalid
    private var totalDistanceMeters: Double = 0
    private var cachedWorkoutSummary: WorkoutCacheSummary?
    private var cachedManifestWorkoutIDs: Set<String>?
    private var didDetectCacheIntegrityIssue = false
    private var needsHealthCacheIntegrityRepair = false
    private var needsStravaCacheIntegrityRepair = false
    private var isCachePersistenceHealthy = true
    private var activeLoadingOperationCount = 0
    private var isCacheLoadInProgress = false
    private var isAppInBackground = false
    private var isCacheLoadShowingLoadingIndicator = false
    private var pendingDataSourceSyncRetryWorkItem: DispatchWorkItem?
    private var pendingDataSourceSyncRetryNotBefore: Date?
    private var pendingDataSourceSyncRetryAttempt = 0
    private var pendingStravaEnrichmentRetryWorkItem: DispatchWorkItem?
    private var isPullRefreshArmedInCurrentDrag = false
    private var collectionView: UICollectionView!
    private let routeGridView = WorkoutRouteGridView()
    private let routeBookMapContainerView = AppMapContainerView()
    private var routeBookMapView: MKMapView { routeBookMapContainerView.mapView }
    private let routeBookMapToneOverlay = AppMapStyle.makeToneOverlay()
    private let routeBookLocationManager = CLLocationManager()
    private lazy var routeBookScaleView: MKScaleView = {
        let scaleView = MKScaleView(mapView: routeBookMapView)
        scaleView.legendAlignment = .leading
        scaleView.scaleVisibility = .hidden
        scaleView.isHidden = true
        scaleView.alpha = 0
        return scaleView
    }()
    private let headerView = UIView()
    private let headerBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let titleLabel = UILabel()
    private let titleAccentLabel = UILabel()
    private let totalDistanceLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let moreButton = UIButton(type: .system)
    private let routeCollectionBadgeLabel = PaddingLabel(contentInsets: UIEdgeInsets(top: 1.5, left: 4, bottom: 1.5, right: 4))
    private let scrollDateIndicatorView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let scrollDateIndicatorLabel = PaddingLabel(contentInsets: UIEdgeInsets(top: 5, left: 11, bottom: 5, right: 11))
    private var headerHeightConstraint: Constraint?
    private var titleLeadingConstraint: Constraint?
    private var titleTopConstraint: Constraint?
    private var currentHeaderLayoutMetrics: HomeHeaderLayoutMetrics?
    private var totalDistanceTrailingToMoreConstraint: Constraint?
    private let routeBookLocateButton = UIButton(type: .system)
    private let routeBookMapStyleButton = UIButton(type: .system)
    private let routeBookSlopeVisibilityButton = UIButton(type: .system)
    private let routeBookSlopeVisibilityIconView = UIImageView()
    private let routeBookPanelSheetViewController = RouteBookPanelSheetViewController()
    private let routeBookPanelView = UIVisualEffectView(effect: ViewController.makeRouteBookPanelGlassEffect())
    private let routeBookPanelMetricsStackView = UIStackView()
    private let routeBookPanelDistanceLabel = UILabel()
    private let routeBookPanelDetailStackView = UIStackView()
    private let routeBookReplayRulerView = WorkoutRouteReplayRulerView()
    private let emptyDataSourceView = HomeDataSourceEmptyView()
    private let demoModeEntryButton = UIButton(type: .system)
    private let defaultColumnCount: CGFloat = 3
    private let itemSpacing: CGFloat = 12
    private let lineSpacing: CGFloat = 2
    private let headerBottomPadding: CGFloat = 8
    private let sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 16, right: 12)
    private let pendingWorkoutFlushDelay: TimeInterval = 0.35
    private let activeScrollFlushDelay: TimeInterval = 0.45
    private let cacheSaveDebounceDelay: TimeInterval = 1.0
    private let cacheSaveRetryMaximumDelay: TimeInterval = 30
    private let cacheSaveMaximumAutomaticRetryCount = 5
    private let cacheLoadPreviewBatchSize = 32
    private let homePreviewCoordinateLimit = 240
    private let currentCacheIntegrityRepairVersion = 1
    private let stravaRequestLimitPerPass = 80
    private let stravaIncrementalLookback: TimeInterval = 7 * 24 * 60 * 60
    private let healthFullCoverageReconciliationInterval: TimeInterval = 7 * 24 * 60 * 60
    private let stravaFullCoverageReconciliationInterval: TimeInterval = 30 * 24 * 60 * 60
    private let stravaPlaceholderEnrichmentInterval: TimeInterval = 6 * 60 * 60
    private let stravaIncompleteRetryBaseDelay: TimeInterval = 15 * 60
    private let stravaTransientRetryBaseDelay: TimeInterval = 60
    private let stravaRetryMaximumDelay: TimeInterval = 24 * 60 * 60
    private let stravaMaximumAutomaticUnchangedRetryCount = 6
    private let pullRefreshTriggerDistance: CGFloat = 86
    private let routeBookPanelHeight: CGFloat = 68
    private let routeBookPanelDetailContentTopSpacing: CGFloat = 24
    private let routeBookReplayRulerViewHeight: CGFloat = 98
    private let routeBookPanelMediumBottomPadding: CGFloat = 18
    private let routeBookPanelPrimaryContentSize: CGFloat = 28
    private let routeBookPanelExpandedPrimaryContentTop: CGFloat = 33
    private let routeBookPanelMinimumPrimaryContentScale: CGFloat = 0.88
    private let routeBookLocateButtonPanelSpacing: CGFloat = 18
    private let routeBookMaximumElevationSampleCount = 24_000
    private let routeBookMaximumSlopeRenderingCoordinateCount = 1_200
    private let routeBookMaximumSlopeSegmentCount = 8
    private let routeBookSlopeGeometrySimplificationToleranceMeters: CLLocationDistance = 4
    private let routeBookPreferredSlopeOverlayChunkDistance: CLLocationDistance = 15_000
    private let routeBookMaximumSlopeOverlayChunkCount = 8
    private let routeBookBaseMatchDistance: CLLocationDistance = 100
    private let routeBookMaximumLocationAccuracy: CLLocationAccuracy = 200
    private let routeBookMaximumLocationAge: TimeInterval = 120
    private var hasPresentedRouteBookPanelSheet = false
    private var selectedRouteBookPanelDetent: RouteBookPanelDetent = .minimum
    private var routeBookPanelMetricsCenterYConstraint: Constraint?
    private var routeBookLocateButtonBottomConstraint: Constraint?
    private var routeBookPresentedPanelHeight: CGFloat = 68
    private var isRouteBookModeActive = false
    private var routeBookWorkout: TrackedWorkout?
    private var routeBookBoundingMapRect: MKMapRect?
    private var routeBookDisplayPolylines: [MKPolyline] = []
    private var routeBookDirectionIndicatorPolylines: [MKPolyline] = []
    private var routeBookDirectionIndicatorBudgets: [ObjectIdentifier: Int] = [:]
    private var routeBookSlopePolylines: [MKPolyline] = []
    private var routeBookSlopeGradients: [ObjectIdentifier: RouteSlopeGradient] = [:]
    private var routeBookSlopeDirectionPolylines: [MKPolyline] = []
    private var routeBookSlopeDirectionPolylineIdentifiers = Set<ObjectIdentifier>()
    private var areRouteBookSlopeDirectionOverlaysSuspendedForMapChange = false
    private var isRouteBookSlopeVisible = false
    private var routeBookEndpointAnnotations: [RouteEndpointAnnotation] = []
    private var routeBookReplayAnnotation: RouteReplayAnnotation?
    private var routeBookReplayCoordinates: [CLLocationCoordinate2D] = []
    private var routeBookReplayDistances: [CLLocationDistance] = []
    private var routeBookReplayAltitudes: [Double?] = []
    private var routeBookReplaySegmentStartIndices = Set<Int>()
    private var routeBookViewportGeometry: RouteViewportDistanceResolver.PreparedGeometry?
    private var routeBookViewportUpdateWorkItem: DispatchWorkItem?
    private var routeBookLastFocusedDistance: CLLocationDistance?
    private var isRouteBookMapRegionChanging = false
    private var routeBookMatchingGeometry: RouteBookMatchingGeometry?
    private var routeBookMatchCache: RouteBookMatchCache?
    private var routeBookPreparationID: UUID?
    private var routeBookPreparationCancellationToken: RouteSlopePreparationCancellationToken?
    private var shouldCenterRouteBookOnNextLocation = false
    private var routeBookLastLocation: CLLocation?
    private var routeBookLastHeadingDegrees: CLLocationDirection?
    private var routeBookHeadingDisplayDegrees: CLLocationDirection?
    private var selectedRouteBookMapStyle = AppMapDisplayStyleStore.shared.routeBookStyle()
    private var shouldClearRouteImportIndicatorsOnNextHomeAppear = false
    private var isHealthAuthorizationRecoveryCheckInProgress = false
    private var isScrollDateIndicatorVisible = false
    private var scrollDateIndicatorHideWorkItem: DispatchWorkItem?
    private var lastScrollDateIndicatorOffsetY: CGFloat?
    private var lastScrollDateIndicatorTimestamp: CFTimeInterval?
    private var lastScrollDateIndicatorText: String?
    private lazy var scrollDateFormatter = Self.makeHomeScrollDateFormatter()

    deinit {
        routeBookPreparationCancellationToken?.cancel()
        routeBookViewportUpdateWorkItem?.cancel()
        pendingFlushWorkItem?.cancel()
        pendingCacheSaveWorkItem?.cancel()
        endBackgroundCacheSaveTask()
        scrollDateIndicatorHideWorkItem?.cancel()
        stopRouteBookLocationAndHeadingUpdates()
        routeBookPanelSheetViewController.sheetPresentationController?.delegate = nil
        routeBookPanelSheetViewController.onViewDidLayout = nil
        routeBookLocationManager.delegate = nil
        routeBookMapView.delegate = nil
        routeBookMapView.showsUserLocation = false
        if !routeBookMapView.overlays.isEmpty {
            routeBookMapView.removeOverlays(routeBookMapView.overlays)
        }
        if !routeBookMapView.annotations.isEmpty {
            routeBookMapView.removeAnnotations(routeBookMapView.annotations)
        }
        routeBookMapView.layer.removeAllAnimations()
        routeBookMapContainerView.layer.removeAllAnimations()
        AppMapContainerView.retainForMetalDrain(routeBookMapContainerView)
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadCachedWorkoutSummary()
        configureNavigationItem()
        configureCollectionView()
        configureRouteBookMapView()
        configureHeaderView()
        configureScrollDateIndicator()
        configureEmptyDataSourceView()
        configureDemoModeEntryButton()
        configureLoadingIndicator()
        registerLanguageObserver()
        registerRouteBookObserver()
        registerSharedRouteImportObserver()
        registerAppLifecycleObservers()
        registerHealthAuthorizationObserver()
        registerTraitChangeHandler()
        store.progressHandler = { message in
            PTrackLog.synchronization.debug("PTrack HealthKit: \(message)")
        }
        importPendingSharedRoutesIfNeeded()
        restorePersistedRouteBookModeIfNeeded()
        loadCachedWorkoutsThenSynchronize()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeaderLayoutForCurrentWindow()
        updateFullScreenInsets()
        positionLoadingIndicatorNextToTotalDistanceText()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        isRouteBookModeActive ? .darkContent : AppAppearanceStore.shared.preferredStatusBarStyle(for: traitCollection)
    }

    private static let routeBookMinimumPanelDetentIdentifier = UISheetPresentationController.Detent.Identifier(
        "RouteBookPanelMinimum"
    )
    private static let routeBookMediumPanelDetentIdentifier = UISheetPresentationController.Detent.Identifier(
        "RouteBookPanelMedium"
    )

    private static func makeRouteBookPanelGlassEffect() -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            effect.tintColor = AppColors.background(alpha: 0.06)
            return effect
        }

        return UIBlurEffect(style: .systemThinMaterial)
    }

    private static func makeHomeScrollDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguageStore.shared.language.rawValue)
        formatter.calendar = Calendar.current
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
        return formatter
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        clearRouteImportIndicatorsIfNeededOnHomeAppear()
        applyRouteBookInterfaceState()
        #if DEBUG
        updateTotalDistanceText()
        #endif
        updateDemoModeEntryVisibility()
        updateFullScreenInsets(force: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateFullScreenInsets(force: true)
        presentRouteBookPanelSheetIfNeeded()
        openRouteCollectionIfRequested()
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            updateFullScreenInsets(force: true)
            presentRouteBookPanelSheetIfNeeded()
            openRouteCollectionIfRequested()
            AppReviewPromptManager.shared.requestIfNeeded(from: self)
        }
    }

    private func configureNavigationItem() {
        title = "Movinn"
        navigationItem.largeTitleDisplayMode = .never
    }

    private func configureCollectionView() {
        view.backgroundColor = AppColors.solidBackground
        routeGridView.collectionView.backgroundColor = AppColors.solidBackground

        routeGridView.configureLayout(
            columns: cachedRouteGridColumnCount(),
            itemSpacing: itemSpacing,
            lineSpacing: lineSpacing,
            sectionInset: sectionInset
        )
        routeGridView.numberOfItemsProvider = { [weak self] in
            self?.workouts.count ?? 0
        }
        routeGridView.itemProvider = { [weak self] index in
            guard let self else {
                return nil
            }

            guard index >= 0, index < self.workouts.count else {
                return nil
            }

            let workout = self.workouts[index]
            return WorkoutRouteGridItem.route(
                workout,
                showsMap: false,
                showsNewBadge: self.newWorkoutBadgeStore.contains(workout)
            )
        }
        routeGridView.onSelectRoute = { [weak self] workout, indexPath, cell in
            self?.showWorkoutDetail(workout, indexPath: indexPath, cell: cell)
        }
        routeGridView.contextMenuConfigurationProvider = { [weak self] workout, _ in
            self?.makeWorkoutContextMenuConfiguration(for: workout)
        }
        routeGridView.onScroll = { [weak self] scrollView in
            self?.updatePullRefreshTracking(for: scrollView)
            self?.updateScrollDateIndicator(for: scrollView)
        }
        routeGridView.onEndDragging = { [weak self] _, decelerate in
            self?.performPullRefreshIfNeeded()
            if !decelerate {
                self?.flushPendingWorkouts()
                self?.resetScrollDateIndicatorTracking()
                self?.scheduleScrollDateIndicatorHide()
            }
        }
        routeGridView.onEndDecelerating = { [weak self] _ in
            self?.finishPullRefreshTracking()
            self?.flushPendingWorkouts()
            self?.resetScrollDateIndicatorTracking()
            self?.scheduleScrollDateIndicatorHide()
        }
        routeGridView.onColumnCountResolved = { [weak self] columnCount in
            self?.saveRouteGridColumnCount(columnCount)
        }
        routeGridView.onColumnSnapFinished = { [weak self] in
            self?.flushPendingWorkouts()
        }

        collectionView = routeGridView.collectionView

        view.addSubview(routeGridView)

        routeGridView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func cachedRouteGridColumnCount() -> CGFloat {
        let value = UserDefaults.standard.integer(forKey: DefaultsKey.homeRouteGridColumnCount)
        guard value >= 2, value <= 6 else {
            return defaultColumnCount
        }

        return CGFloat(value)
    }

    private func saveRouteGridColumnCount(_ columnCount: CGFloat) {
        let roundedColumnCount = Int(round(columnCount))
        let clampedColumnCount = min(max(roundedColumnCount, 2), 6)
        UserDefaults.standard.set(clampedColumnCount, forKey: DefaultsKey.homeRouteGridColumnCount)
        UserDefaults.standard.synchronize()
    }

    private func configureRouteBookMapView() {
        routeBookMapContainerView.isHidden = true
        routeBookMapView.delegate = self
        routeBookMapView.showsCompass = false
        routeBookMapView.showsScale = false
        routeBookMapView.showsUserLocation = false
        routeBookMapView.isRotateEnabled = false
        routeBookMapView.isPitchEnabled = false
        routeBookMapView.userTrackingMode = .none
        resetRouteBookMapHeading(animated: false)
        routeBookLocationManager.delegate = self
        routeBookLocationManager.desiredAccuracy = kCLLocationAccuracyBest
        routeBookLocationManager.headingFilter = 5

        applyRouteBookMapStyle(selectedRouteBookMapStyle, persistsSelection: false)

        view.addSubview(routeBookMapContainerView)
        view.sendSubviewToBack(routeBookMapContainerView)

        routeBookMapContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        configureRouteBookPanelView()
        configureRouteBookLocateButton()
        configureRouteBookSlopeVisibilityButton()
        configureRouteBookMapStyleButton()
    }

    private func configureRouteBookPanelView() {
        routeBookPanelSheetViewController.view.backgroundColor = .clear
        routeBookPanelSheetViewController.view.isOpaque = false
        routeBookPanelSheetViewController.modalPresentationStyle = .pageSheet
        routeBookPanelSheetViewController.isModalInPresentation = true
        routeBookPanelSheetViewController.onViewDidLayout = { [weak self] height in
            self?.updateRouteBookLocateButtonForPanelHeight(height, animated: false)
        }

        routeBookPanelView.backgroundColor = .clear
        routeBookPanelView.layer.cornerRadius = 0
        routeBookPanelView.layer.masksToBounds = true
        routeBookPanelView.layer.borderWidth = 0

        let distanceFont = UIFont.preferredFont(forTextStyle: .headline)
        routeBookPanelDistanceLabel.font = distanceFont
        routeBookPanelDistanceLabel.textAlignment = .right
        routeBookPanelDistanceLabel.adjustsFontSizeToFitWidth = true
        routeBookPanelDistanceLabel.minimumScaleFactor = 0.78
        routeBookPanelDistanceLabel.numberOfLines = 1
        routeBookPanelDistanceLabel.setContentHuggingPriority(.required, for: .horizontal)
        routeBookPanelDistanceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let metricsSpacerView = UIView()
        metricsSpacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metricsSpacerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        routeBookPanelMetricsStackView.axis = .horizontal
        routeBookPanelMetricsStackView.alignment = .center
        routeBookPanelMetricsStackView.distribution = .fill
        routeBookPanelMetricsStackView.spacing = 12
        routeBookPanelMetricsStackView.addArrangedSubview(routeBookPanelDistanceLabel)
        routeBookPanelMetricsStackView.addArrangedSubview(metricsSpacerView)

        routeBookPanelDetailStackView.axis = .vertical
        routeBookPanelDetailStackView.spacing = 0
        routeBookPanelDetailStackView.alpha = 1

        routeBookReplayRulerView.configure(
            totalDistanceText: routeBookReplayTotalDistanceText(totalMeters: 0),
            totalDistanceMeters: 0
        )
        routeBookReplayRulerView.addTarget(
            self,
            action: #selector(handleRouteBookReplayProgressChanged(_:)),
            for: .valueChanged
        )
        routeBookPanelDetailStackView.addArrangedSubview(routeBookReplayRulerView)

        updateRouteBookPanelAppearanceColors()

        routeBookPanelSheetViewController.view.addSubview(routeBookPanelView)
        routeBookPanelView.contentView.addSubview(routeBookPanelMetricsStackView)
        routeBookPanelView.contentView.addSubview(routeBookPanelDetailStackView)

        routeBookPanelView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        routeBookPanelMetricsStackView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(18)
            routeBookPanelMetricsCenterYConstraint = make.centerY.equalTo(routeBookPanelView.snp.top)
                .offset(routeBookPanelMetricsCenterYOffset(for: routeBookPanelHeight))
                .constraint
        }

        routeBookPanelDetailStackView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(18)
            make.top.equalTo(routeBookPanelView.snp.top).offset(routeBookPanelDetailStackTopOffset)
        }

        routeBookReplayRulerView.snp.makeConstraints { make in
            make.height.equalTo(routeBookReplayRulerViewHeight)
        }

        applyRouteBookPanelDetent(.minimum, animated: false)
    }

    private func configureRouteBookLocateButton() {
        let configuration = routeBookFloatingButtonConfiguration(systemName: "location.fill")
        routeBookLocateButton.configuration = configuration
        routeBookLocateButton.isHidden = true
        routeBookLocateButton.accessibilityLabel = AppLocalization.text(.navigation)
        applyRouteBookFloatingButtonShadow(to: routeBookLocateButton)
        routeBookLocateButton.addTarget(self, action: #selector(handleRouteBookLocateButtonTap), for: .touchUpInside)

        view.addSubview(routeBookLocateButton)

        routeBookLocateButton.snp.makeConstraints { make in
            make.trailing.equalTo(view.safeAreaLayoutGuide.snp.trailing).inset(18)
            routeBookLocateButtonBottomConstraint = make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
                .inset(routeBookPanelHeight + routeBookLocateButtonPanelSpacing)
                .constraint
            make.size.equalTo(48)
        }
    }

    private func configureRouteBookMapStyleButton() {
        let configuration = routeBookFloatingButtonConfiguration(systemName: "map")
        routeBookMapStyleButton.configuration = configuration
        routeBookMapStyleButton.isHidden = true
        routeBookMapStyleButton.menu = makeRouteBookMapStyleMenu()
        routeBookMapStyleButton.showsMenuAsPrimaryAction = true
        routeBookMapStyleButton.accessibilityLabel = AppLocalization.text(.mapStyle)
        applyRouteBookFloatingButtonShadow(to: routeBookMapStyleButton)

        view.addSubview(routeBookMapStyleButton)

        routeBookMapStyleButton.snp.makeConstraints { make in
            make.trailing.equalTo(routeBookLocateButton)
            make.bottom.equalTo(routeBookSlopeVisibilityButton.snp.top).offset(-12)
            make.size.equalTo(48)
        }
    }

    private func configureRouteBookSlopeVisibilityButton() {
        var configuration = routeBookFloatingButtonConfiguration(systemName: "mountain.2.fill")
        configuration.image = nil
        routeBookSlopeVisibilityButton.configuration = configuration
        routeBookSlopeVisibilityButton.isHidden = true
        routeBookSlopeVisibilityButton.isEnabled = false
        routeBookSlopeVisibilityButton.accessibilityLabel = AppLocalization.text(.routeSlope)
        routeBookSlopeVisibilityIconView.isUserInteractionEnabled = false
        routeBookSlopeVisibilityIconView.contentMode = .scaleAspectFit
        routeBookSlopeVisibilityIconView.image = UIImage(
            systemName: "mountain.2.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )?.withRenderingMode(.alwaysTemplate)
        routeBookSlopeVisibilityButton.addTarget(
            self,
            action: #selector(handleRouteBookSlopeVisibilityButtonTap),
            for: .touchUpInside
        )
        applyRouteBookFloatingButtonShadow(to: routeBookSlopeVisibilityButton)

        view.addSubview(routeBookSlopeVisibilityButton)
        routeBookSlopeVisibilityButton.addSubview(routeBookSlopeVisibilityIconView)

        routeBookSlopeVisibilityButton.snp.makeConstraints { make in
            make.trailing.equalTo(routeBookLocateButton)
            make.bottom.equalTo(routeBookLocateButton.snp.top).offset(-12)
            make.size.equalTo(48)
        }

        routeBookSlopeVisibilityIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(22)
        }
    }

    private func routeBookFloatingButtonConfiguration(systemName: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = AppColors.background(alpha: 0.92)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        return configuration
    }

    private func applyRouteBookFloatingButtonShadow(to button: UIButton) {
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.14
        button.layer.shadowRadius = 12
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    private func makeRouteBookMapStyleMenu() -> UIMenu {
        UIMenu(
            title: AppLocalization.text(.mapStyle),
            children: AppMapDisplayStyle.menuCases.map { style in
                UIAction(
                    title: style.title,
                    state: style == selectedRouteBookMapStyle ? .on : .off
                ) { [weak self] _ in
                    self?.applyRouteBookMapStyle(style)
                }
            }
        )
    }

    private func applyRouteBookMapStyle(_ style: AppMapDisplayStyle, persistsSelection: Bool = true) {
        selectedRouteBookMapStyle = style
        if persistsSelection {
            AppMapDisplayStyleStore.shared.setRouteBookStyle(style)
        }

        AppMapStyle.apply(style, to: routeBookMapView)
        AppMapStyle.setToneOverlay(routeBookMapToneOverlay, visible: style == .appDefault, on: routeBookMapView)
        routeBookMapStyleButton.menu = makeRouteBookMapStyleMenu()
        refreshRouteBookOverlayStrokeColor()
    }

    @objc private func handleRouteBookSlopeVisibilityButtonTap() {
        guard !routeBookSlopePolylines.isEmpty else {
            return
        }

        if isRouteBookSlopeVisible {
            setRouteBookSlopeVisible(false)
            return
        }

        Task { @MainActor [weak self] in
            guard let self, isRouteBookModeActive else {
                return
            }

            await ProSubscriptionManager.shared.ensureAccessResolved()
            guard ProSubscriptionManager.shared.isProUser else {
                routeBookModalPresentationHost.presentProPaywall { [weak self] in
                    self?.setRouteBookSlopeVisible(true)
                }
                return
            }

            setRouteBookSlopeVisible(true)
        }
    }

    private func setRouteBookSlopeVisible(_ isVisible: Bool) {
        guard isRouteBookModeActive,
              !routeBookSlopePolylines.isEmpty,
              isRouteBookSlopeVisible != isVisible else {
            return
        }

        isRouteBookSlopeVisible = isVisible
        replaceRouteBookOverlaysForSlopeVisibility()
        if isVisible {
            showRouteBookSlopeColorHint()
        }
        updateRouteBookSlopeVisibilityButtonAppearance()
    }

    private func replaceRouteBookOverlaysForSlopeVisibility() {
        guard routeBookBoundingMapRect != nil else {
            return
        }

        let visibleOverlayIdentifiers = Set(
            routeBookMapView.overlays.map { ObjectIdentifier($0 as AnyObject) }
        )
        let visibleDirectionPolylines = routeBookSlopeDirectionPolylines.filter {
            visibleOverlayIdentifiers.contains(ObjectIdentifier($0))
        }
        if !visibleDirectionPolylines.isEmpty {
            routeBookMapView.removeOverlays(visibleDirectionPolylines)
        }
        let visibleRoutePolylines = routeBookDisplayPolylines.filter {
            visibleOverlayIdentifiers.contains(ObjectIdentifier($0))
        }
        if !visibleRoutePolylines.isEmpty {
            routeBookMapView.removeOverlays(visibleRoutePolylines)
        }
        let visibleSlopePolylines = routeBookSlopePolylines.filter {
            visibleOverlayIdentifiers.contains(ObjectIdentifier($0))
        }
        if !visibleSlopePolylines.isEmpty {
            routeBookMapView.removeOverlays(visibleSlopePolylines)
        }

        if isRouteBookSlopeVisible, !routeBookSlopePolylines.isEmpty {
            routeBookMapView.addOverlays(routeBookSlopePolylines, level: .aboveLabels)
            addRouteBookSlopeDirectionOverlayIfNeeded()
        } else {
            routeBookMapView.addOverlays(routeBookDisplayPolylines, level: .aboveLabels)
        }
    }

    private func addRouteBookSlopeDirectionOverlayIfNeeded() {
        guard isRouteBookSlopeVisible,
              !areRouteBookSlopeDirectionOverlaysSuspendedForMapChange,
              !isRouteBookMapRegionChanging else {
            return
        }
        let visibleOverlayIdentifiers = Set(
            routeBookMapView.overlays.map { ObjectIdentifier($0 as AnyObject) }
        )
        let missingDirectionPolylines = routeBookSlopeDirectionPolylines.filter {
            !visibleOverlayIdentifiers.contains(ObjectIdentifier($0))
        }
        if !missingDirectionPolylines.isEmpty {
            routeBookMapView.addOverlays(missingDirectionPolylines, level: .aboveLabels)
        }
    }

    private func showRouteBookSlopeColorHint() {
        guard let window = view.window,
              RouteSlopeColorHintStore.consumeShouldShow() else {
            return
        }

        let message = AppLocalization.text(.routeSlopeColorHint)
        Toast.show(
            message,
            in: window,
            duration: 2.4,
            bottomInset: routeBookPresentedPanelHeight + routeBookLocateButtonPanelSpacing
        )
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private var routeBookRouteStrokeColor: UIColor {
        switch selectedRouteBookMapStyle {
        case .dark, .satellite:
            return .white
        case .appDefault, .standard:
            return .black
        }
    }

    private func refreshRouteBookOverlayStrokeColor() {
        for routeBookPolyline in routeBookDisplayPolylines {
            guard let renderer = routeBookMapView.renderer(for: routeBookPolyline) as? MKPolylineRenderer else {
                continue
            }
            renderer.strokeColor = routeBookRouteStrokeColor
            if let directionRenderer = renderer as? RouteDirectionPolylineRenderer {
                directionRenderer.directionIndicatorColor = routeBookRouteStrokeColor
            }
            renderer.setNeedsDisplay()
        }
        for directionPolyline in routeBookSlopeDirectionPolylines {
            guard let renderer = routeBookMapView.renderer(for: directionPolyline)
                    as? RouteDirectionPolylineRenderer else {
                continue
            }
            renderer.directionIndicatorColor = routeBookRouteStrokeColor
            renderer.setNeedsDisplay()
        }
    }

    private func configureHeaderView() {
        headerView.isUserInteractionEnabled = true
        headerView.backgroundColor = AppColors.solidBackground

        headerBlurView.isHidden = true
        updateHeaderAppearanceColors()

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
        moreButton.addTarget(self, action: #selector(handleHeaderMoreMenuTriggered), for: .menuActionTriggered)
        configureRouteCollectionBadgeLabel()
        updateHeaderMoreButtonMode()

        view.addSubview(headerView)
        headerView.addSubview(headerBlurView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(titleAccentLabel)
        headerView.addSubview(totalDistanceLabel)
        headerView.addSubview(loadingIndicator)
        headerView.addSubview(moreButton)
        headerView.addSubview(routeCollectionBadgeLabel)

        let layoutMetrics = HomeHeaderLayout.metrics(for: view)
        currentHeaderLayoutMetrics = layoutMetrics

        headerView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            headerHeightConstraint = make.height.equalTo(layoutMetrics.height).constraint
        }

        headerBlurView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        titleLabel.snp.makeConstraints { make in
            titleLeadingConstraint = make.leading.equalToSuperview().offset(layoutMetrics.titleLeading).constraint
            titleTopConstraint = make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(layoutMetrics.titleTop).constraint
        }

        titleAccentLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel.snp.trailing).offset(-1)
            make.lastBaseline.equalTo(titleLabel.snp.lastBaseline)
        }

        totalDistanceLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleAccentLabel.snp.trailing).offset(10)
            totalDistanceTrailingToMoreConstraint = make.trailing.lessThanOrEqualTo(moreButton.snp.leading).offset(-10).constraint
            make.lastBaseline.equalTo(titleLabel.snp.lastBaseline).offset(-3)
        }

        moreButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalTo(titleLabel)
            make.size.equalTo(36)
        }

        routeCollectionBadgeLabel.snp.makeConstraints { make in
            make.trailing.equalTo(moreButton.snp.trailing).offset(2)
            make.bottom.equalTo(moreButton.snp.top).offset(5)
        }

        updateTotalDistanceText()
        configureRouteBookScaleView()
    }

    private func updateHeaderLayoutForCurrentWindow() {
        let layoutMetrics = HomeHeaderLayout.metrics(for: view)
        guard layoutMetrics != currentHeaderLayoutMetrics else {
            return
        }

        currentHeaderLayoutMetrics = layoutMetrics
        headerHeightConstraint?.update(offset: layoutMetrics.height)
        titleLeadingConstraint?.update(offset: layoutMetrics.titleLeading)
        titleTopConstraint?.update(offset: layoutMetrics.titleTop)
        view.setNeedsLayout()
    }

    private func configureRouteCollectionBadgeLabel() {
        routeCollectionBadgeLabel.text = AppLocalization.text(.newRoute)
        routeCollectionBadgeLabel.textColor = AppColors.foreground(alpha: 0.86)
        routeCollectionBadgeLabel.font = .systemFont(ofSize: 8, weight: .bold)
        routeCollectionBadgeLabel.backgroundColor = AppColors.movinnGreen
        routeCollectionBadgeLabel.layer.cornerRadius = 5
        routeCollectionBadgeLabel.layer.masksToBounds = true
        routeCollectionBadgeLabel.isUserInteractionEnabled = false
        routeCollectionBadgeLabel.isHidden = true
    }

    private func configureScrollDateIndicator() {
        scrollDateIndicatorView.alpha = 0
        scrollDateIndicatorView.isHidden = true
        scrollDateIndicatorView.isUserInteractionEnabled = false
        scrollDateIndicatorView.layer.cornerRadius = 16
        scrollDateIndicatorView.layer.masksToBounds = true

        scrollDateIndicatorLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        scrollDateIndicatorLabel.numberOfLines = 1
        scrollDateIndicatorLabel.adjustsFontSizeToFitWidth = true
        scrollDateIndicatorLabel.minimumScaleFactor = 0.82
        scrollDateIndicatorLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        scrollDateIndicatorLabel.setContentHuggingPriority(.required, for: .horizontal)

        updateScrollDateIndicatorAppearance()

        view.addSubview(scrollDateIndicatorView)
        scrollDateIndicatorView.contentView.addSubview(scrollDateIndicatorLabel)

        scrollDateIndicatorView.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide.snp.leading).offset(16)
            make.top.equalTo(headerView.snp.bottom).offset(10)
            make.height.greaterThanOrEqualTo(32)
            make.width.lessThanOrEqualTo(view.safeAreaLayoutGuide.snp.width).multipliedBy(0.72)
        }

        scrollDateIndicatorLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func updateScrollDateIndicatorAppearance() {
        scrollDateIndicatorLabel.textColor = AppColors.foreground(alpha: 0.9)

        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = false
            effect.tintColor = AppColors.background(alpha: 0.08)
            scrollDateIndicatorView.effect = effect
            scrollDateIndicatorView.backgroundColor = .clear
            scrollDateIndicatorView.contentView.backgroundColor = .clear
        } else {
            scrollDateIndicatorView.effect = UIBlurEffect(style: .systemThinMaterial)
            scrollDateIndicatorView.backgroundColor = .clear
            scrollDateIndicatorView.contentView.backgroundColor = AppColors.background(alpha: 0.36)
        }
    }

    private func updateHeaderAppearanceColors() {
        headerBlurView.effect = nil
        headerBlurView.contentView.backgroundColor = .clear
        headerBlurView.layer.mask = nil
        if !isRouteBookModeActive {
            headerView.backgroundColor = AppColors.solidBackground
        }
    }

    private func updateRouteBookLocateButtonAppearance() {
        guard var configuration = routeBookLocateButton.configuration else {
            return
        }

        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = AppColors.background(alpha: 0.92)
        routeBookLocateButton.configuration = configuration

        guard var mapStyleConfiguration = routeBookMapStyleButton.configuration else {
            return
        }

        mapStyleConfiguration.baseForegroundColor = .label
        mapStyleConfiguration.baseBackgroundColor = AppColors.background(alpha: 0.92)
        routeBookMapStyleButton.configuration = mapStyleConfiguration

        updateRouteBookSlopeVisibilityButtonAppearance()
    }

    private func updateRouteBookSlopeVisibilityButtonAppearance() {
        let isAvailable = !routeBookSlopePolylines.isEmpty
        routeBookSlopeVisibilityButton.isEnabled = isAvailable
        guard var configuration = routeBookSlopeVisibilityButton.configuration else {
            return
        }

        configuration.baseForegroundColor = isRouteBookSlopeVisible
            ? AppColors.movinnGreen
            : UIColor.label.withAlphaComponent(isAvailable ? 1 : 0.38)
        configuration.baseBackgroundColor = AppColors.background(alpha: 0.92)
        routeBookSlopeVisibilityButton.configuration = configuration
        routeBookSlopeVisibilityIconView.tintColor = configuration.baseForegroundColor
        if isRouteBookSlopeVisible {
            routeBookSlopeVisibilityButton.accessibilityTraits.insert(.selected)
        } else {
            routeBookSlopeVisibilityButton.accessibilityTraits.remove(.selected)
        }
        routeBookSlopeVisibilityButton.accessibilityHint = isAvailable
            ? AppLocalization.text(isRouteBookSlopeVisible ? .disable : .enable)
            : nil
    }

    private func updateRouteBookPanelAppearanceColors() {
        routeBookPanelView.effect = Self.makeRouteBookPanelGlassEffect()
        if #available(iOS 26.0, *) {
            routeBookPanelView.contentView.backgroundColor = .clear
        } else {
            routeBookPanelView.contentView.backgroundColor = AppColors.background(alpha: 0.08)
        }
        routeBookPanelDistanceLabel.textColor = AppColors.foreground(alpha: 0.92)
    }

    private var routeBookModalPresentationHost: UIViewController {
        if presentedViewController === routeBookPanelSheetViewController {
            return routeBookPanelSheetViewController
        }

        return self
    }

    private func presentRouteBookPanelSheetIfNeeded() {
        guard isRouteBookModeActive,
              !hasPresentedRouteBookPanelSheet,
              presentedViewController == nil,
              view.window != nil,
              (navigationController?.topViewController ?? self) === self,
              transitionCoordinator == nil,
              navigationController?.transitionCoordinator == nil else {
            return
        }

        if let sheetPresentationController = routeBookPanelSheetViewController.sheetPresentationController {
            sheetPresentationController.detents = [
                .custom(identifier: Self.routeBookMinimumPanelDetentIdentifier) { [weak self] _ in
                    self?.routeBookPanelContentHeight(for: .minimum) ?? 68
                },
                .custom(identifier: Self.routeBookMediumPanelDetentIdentifier) { [weak self] _ in
                    self?.routeBookPanelContentHeight(for: .medium) ?? 187
                }
            ]
            sheetPresentationController.selectedDetentIdentifier = routeBookPanelDetentIdentifier(for: selectedRouteBookPanelDetent)
            sheetPresentationController.largestUndimmedDetentIdentifier = Self.routeBookMediumPanelDetentIdentifier
            sheetPresentationController.prefersGrabberVisible = true
            sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = false
            sheetPresentationController.preferredCornerRadius = 28
            sheetPresentationController.delegate = self
        }

        hasPresentedRouteBookPanelSheet = true
        present(routeBookPanelSheetViewController, animated: false)
    }

    private func dismissRouteBookPanelSheetIfNeeded(animated: Bool) {
        guard hasPresentedRouteBookPanelSheet ||
              presentedViewController === routeBookPanelSheetViewController else {
            hasPresentedRouteBookPanelSheet = false
            return
        }

        hasPresentedRouteBookPanelSheet = false
        routeBookPanelSheetViewController.dismiss(animated: animated)
    }

    private func routeBookPanelDetentIdentifier(
        for detent: RouteBookPanelDetent
    ) -> UISheetPresentationController.Detent.Identifier {
        switch detent {
        case .minimum:
            return Self.routeBookMinimumPanelDetentIdentifier
        case .medium:
            return Self.routeBookMediumPanelDetentIdentifier
        }
    }

    private func routeBookPanelContentHeight(for detent: RouteBookPanelDetent) -> CGFloat {
        switch detent {
        case .minimum:
            return routeBookPanelHeight
        case .medium:
            return routeBookPanelMediumHeight
        }
    }

    private var routeBookPanelMediumHeight: CGFloat {
        routeBookPanelExpandedPrimaryContentCenterY
            + routeBookPanelDetailContentTopSpacing
            + routeBookReplayRulerViewHeight
            + routeBookPanelMediumBottomPadding
    }

    private var routeBookPanelExpandedPrimaryContentCenterY: CGFloat {
        routeBookPanelExpandedPrimaryContentTop + routeBookPanelPrimaryContentSize / 2
    }

    private var routeBookPanelDetailStackTopOffset: CGFloat {
        routeBookPanelExpandedPrimaryContentCenterY + routeBookPanelDetailContentTopSpacing
    }

    private func routeBookPanelDetailProgress(for height: CGFloat) -> CGFloat {
        let minimumHeight = routeBookPanelContentHeight(for: .minimum)
        let mediumHeight = routeBookPanelContentHeight(for: .medium)
        guard mediumHeight > minimumHeight else {
            return 1
        }

        return min(max((height - minimumHeight) / (mediumHeight - minimumHeight), 0), 1)
    }

    private func routeBookPanelMetricsCenterYOffset(for height: CGFloat) -> CGFloat {
        let minimumCenterY = routeBookPanelHeight / 2
        let progress = routeBookPanelDetailProgress(for: height)
        return minimumCenterY + (routeBookPanelExpandedPrimaryContentCenterY - minimumCenterY) * progress
    }

    private func updateRouteBookPanelMetricsScale(for height: CGFloat) {
        let progress = routeBookPanelDetailProgress(for: height)
        let scale = routeBookPanelMinimumPrimaryContentScale
            + (1 - routeBookPanelMinimumPrimaryContentScale) * progress
        routeBookPanelMetricsStackView.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    private func applyRouteBookPanelDetent(_ detent: RouteBookPanelDetent, animated: Bool) {
        selectedRouteBookPanelDetent = detent
        let height = routeBookPanelContentHeight(for: detent)
        routeBookPanelMetricsCenterYConstraint?.update(offset: routeBookPanelMetricsCenterYOffset(for: height))
        updateRouteBookLocateButtonForPanelHeight(height, animated: animated)

        switch detent {
        case .minimum:
            routeBookReplayRulerView.setProgress(0)
            routeBookReplayRulerView.setIndicatorVisible(false)
            removeRouteBookReplayAnnotation()
        case .medium:
            updateRouteBookReplayProgressForCurrentLocation()
        }
        updateRouteBookReplayRulerVisibleRange()

        let changes = {
            self.updateRouteBookPanelMetricsScale(for: height)
            self.routeBookPanelSheetViewController.view.layoutIfNeeded()
            self.view.layoutIfNeeded()
        }

        guard animated else {
            changes()
            return
        }

        UIView.animate(
            withDuration: 0.36,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.7,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes
        )
    }

    private func updateRouteBookLocateButtonForPanelHeight(_ height: CGFloat, animated: Bool) {
        guard height > 0 else {
            return
        }

        let panelHeight = max(height, routeBookPanelHeight)
        guard abs(routeBookPresentedPanelHeight - panelHeight) > 0.5 else {
            return
        }

        routeBookPresentedPanelHeight = panelHeight
        routeBookLocateButtonBottomConstraint?.update(inset: panelHeight + routeBookLocateButtonPanelSpacing)

        guard animated else {
            view.layoutIfNeeded()
            return
        }

        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: { self.view.layoutIfNeeded() }
        )
    }

    private func configureRouteBookScaleView() {
        view.addSubview(routeBookScaleView)

        routeBookScaleView.snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide.snp.leading).offset(16)
            make.top.equalTo(headerView.snp.bottom).offset(8)
            make.width.equalTo(130)
            make.height.equalTo(28)
        }
    }

    private func makeHeaderMoreMenu() -> UIMenu {
        let moreAction = UIAction(
            title: AppLocalization.text(.more),
            image: UIImage(systemName: "ellipsis")
        ) { [weak self] _ in
            self?.showMoreSettings()
        }

        guard hasReadableDataSourceAuthorization else {
            return UIMenu(children: [moreAction])
        }

        let hasUnseenRoute = SharedRouteImportInbox.hasUnseenRoute
        let routeCollectionAction = UIAction(
            title: AppLocalization.text(.routeCollectionMenuTitle),
            image: routeCollectionMenuImage(hasUnseenRoute: hasUnseenRoute)
        ) { [weak self] _ in
            self?.showRouteCollection()
        }
        routeCollectionAction.subtitle = hasUnseenRoute ? AppLocalization.text(.newRoute) : nil

        let heatmapAction = UIAction(
            title: AppLocalization.text(.routeHeatmap),
            image: UIImage(systemName: "map")
        ) { [weak self] _ in
            self?.showHeatmap()
        }

        return UIMenu(children: [routeCollectionAction, heatmapAction, moreAction])
    }

    private func updateHeaderMoreButtonMode() {
        var buttonConfiguration = moreButton.configuration ?? .plain()
        buttonConfiguration.image = UIImage(
            systemName: isRouteBookModeActive ? "xmark" : "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: isRouteBookModeActive ? 15 : 18,
                weight: isRouteBookModeActive ? .bold : .semibold
            )
        )
        buttonConfiguration.contentInsets = isRouteBookModeActive
            ? NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
            : NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
        moreButton.configuration = buttonConfiguration
        moreButton.tintColor = isRouteBookModeActive ? .black : .label
        updateRouteCollectionBadgeVisibility()

        if isRouteBookModeActive {
            moreButton.menu = nil
            moreButton.showsMenuAsPrimaryAction = false
            return
        }

        moreButton.menu = makeHeaderMoreMenu()
        moreButton.showsMenuAsPrimaryAction = true
    }

    private func updateRouteCollectionBadgeVisibility() {
        routeCollectionBadgeLabel.text = AppLocalization.text(.newRoute)
        routeCollectionBadgeLabel.isHidden = isRouteBookModeActive
            || !hasReadableDataSourceAuthorization
            || !SharedRouteImportInbox.hasUnseenRoute
        if !isRouteBookModeActive {
            moreButton.menu = makeHeaderMoreMenu()
        }
    }

    private func routeCollectionMenuImage(hasUnseenRoute: Bool) -> UIImage? {
        let image = UIImage(systemName: "point.bottomleft.forward.to.point.topright.scurvepath")

        guard hasUnseenRoute else {
            return image
        }

        return image?.withTintColor(AppColors.movinnGreen, renderingMode: .alwaysOriginal)
    }

    @objc private func handleHeaderMoreButtonTap() {
        if isRouteBookModeActive {
            presentRouteBookExitAlert()
            return
        }

        guard !hasReadableDataSourceAuthorization else {
            return
        }
    }

    @objc private func handleHeaderMoreMenuTriggered() {
        guard !isRouteBookModeActive else {
            return
        }

        moreButton.menu = makeHeaderMoreMenu()
    }

    @objc private func handleDemoModeEntryButtonTap() {
        DemoModeCoordinator.activate(from: self)
    }

    private func configureLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = true
        loadingIndicator.sizeToFit()
        updateHeaderReadAuthorizationState()
    }

    private func configureEmptyDataSourceView() {
        emptyDataSourceView.onAppleHealthTap = { [weak self] in
            self?.handleEmptyAppleHealthSelection()
        }
        emptyDataSourceView.onStravaTap = { [weak self] in
            self?.handleEmptyStravaSelection()
        }
        emptyDataSourceView.onAppleFitnessTap = { [weak self] in
            self?.openAppleFitness()
        }
        emptyDataSourceView.isHidden = true

        view.addSubview(emptyDataSourceView)

        emptyDataSourceView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.equalToSuperview().offset(-48).priority(.high)
            make.width.lessThanOrEqualTo(360)
            make.centerY.equalTo(view.safeAreaLayoutGuide.snp.centerY).offset(-18)
            make.top.greaterThanOrEqualTo(headerView.snp.bottom).offset(36)
        }

        updateEmptyDataSourceVisibility()
    }

    private func configureDemoModeEntryButton() {
        demoModeEntryButton.setTitle(AppLocalization.text(.demoModeEntry), for: .normal)
        demoModeEntryButton.setTitleColor(.secondaryLabel, for: .normal)
        demoModeEntryButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        demoModeEntryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        demoModeEntryButton.backgroundColor = .clear
        demoModeEntryButton.addTarget(self, action: #selector(handleDemoModeEntryButtonTap), for: .touchUpInside)

        view.addSubview(demoModeEntryButton)
        demoModeEntryButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(8)
            make.height.greaterThanOrEqualTo(30)
        }
        updateDemoModeEntryVisibility()
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

    private func showCacheLoadLoadingIndicatorIfNeeded() {
        guard isCacheLoadInProgress, !isCacheLoadShowingLoadingIndicator else {
            return
        }

        isCacheLoadShowingLoadingIndicator = true
        beginLoadingOperation()
    }

    private func showHealthSyncLoadingIndicatorIfNeeded() {
        guard syncCoordinator.showLoadingIndicatorIfNeeded(.health) else {
            return
        }
        beginLoadingOperation()
    }

    private func showStravaSyncLoadingIndicatorIfNeeded() {
        guard syncCoordinator.showLoadingIndicatorIfNeeded(.strava) else {
            return
        }
        beginLoadingOperation()
    }

    private var isNewDataSyncInProgress: Bool {
        syncCoordinator.isNewDataSyncInProgress
    }

    private func setNewDataSyncInProgress(_ isInProgress: Bool, for source: WorkoutSyncCoordinator.Source) {
        syncCoordinator.setNewData(isInProgress, for: source)
        updateRouteGridPrefetchingState()
        updateTotalDistanceText()
    }

    private func updateRouteGridPrefetchingState() {
        routeGridView.isPrefetchingEnabled = !isCacheLoadInProgress && !isNewDataSyncInProgress
    }

    private var hasReadableDataSourceAuthorization: Bool {
        isSimulatingHomeEmptyData
            || store.authorizationState == .authorized
            || StravaManager.shared.hasStoredAuthorization
    }

    private var isSimulatingHomeEmptyData: Bool {
        #if DEBUG
        HomeEmptyDataDebugStore.isEnabled
        #else
        false
        #endif
    }

    private var hasUserSelectedPrimaryDataSource: Bool {
        DemoModeStore.hasSelectedPrimaryDataSource
            || store.authorizationState != .notDetermined
            || StravaManager.shared.authorizationState != .notDetermined
    }

    private var shouldShowHomeDemoModeEntry: Bool {
        !isRouteBookModeActive
            && !isSimulatingHomeEmptyData
            && !hasUserSelectedPrimaryDataSource
    }

    private func updateDemoModeEntryVisibility() {
        demoModeEntryButton.isHidden = !shouldShowHomeDemoModeEntry
    }

    private func updateHeaderReadAuthorizationState() {
        totalDistanceLabel.isHidden = isRouteBookModeActive || !hasReadableDataSourceAuthorization
        updateDemoModeEntryVisibility()
        updateLoadingIndicatorVisibility()
        updateHeaderMoreButtonMode()
    }

    private func updateLoadingIndicatorVisibility() {
        let shouldShowLoadingIndicator = (activeLoadingOperationCount > 0 || isNewDataSyncInProgress)
            && hasReadableDataSourceAuthorization
            && !isRouteBookModeActive
            && !isSimulatingHomeEmptyData

        if shouldShowLoadingIndicator {
            totalDistanceTrailingToMoreConstraint?.activate()
            loadingIndicator.startAnimating()
            positionLoadingIndicatorNextToTotalDistanceText()
        } else {
            loadingIndicator.stopAnimating()
            totalDistanceTrailingToMoreConstraint?.activate()
        }
    }

    private func positionLoadingIndicatorNextToTotalDistanceText() {
        guard loadingIndicator.isAnimating,
              !totalDistanceLabel.isHidden,
              !totalDistanceLabel.frame.isEmpty else {
            return
        }

        headerView.layoutIfNeeded()
        loadingIndicator.sizeToFit()

        let text = totalDistanceLabel.text ?? ""
        let textWidth = ceil((text as NSString).size(withAttributes: [
            .font: totalDistanceLabel.font ?? UIFont.systemFont(ofSize: 11, weight: .medium)
        ]).width)
        let spacing: CGFloat = 5
        let indicatorSize = loadingIndicator.bounds.size
        let desiredX = totalDistanceLabel.frame.minX + textWidth + spacing
        let maxX = moreButton.frame.minX - 10 - indicatorSize.width
        let x = max(totalDistanceLabel.frame.minX, min(desiredX, maxX))
        let y = totalDistanceLabel.frame.midY - indicatorSize.height / 2
        loadingIndicator.frame = CGRect(origin: CGPoint(x: x, y: y), size: indicatorSize)
    }

    private func updateFullScreenInsets(force: Bool = false) {
        guard let collectionView else {
            return
        }

        view.layoutIfNeeded()
        let headerMaxY = headerView.convert(headerView.bounds, to: view).maxY

        let bottomInset: CGFloat = shouldShowHomeDemoModeEntry ? 46 : 0
        let contentInset = UIEdgeInsets(
            top: headerMaxY + headerBottomPadding,
            left: 0,
            bottom: bottomInset,
            right: 0
        )
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

    func synchronizeDataSourcesForAppOpen(showsLoadingIndicator: Bool = true) {
        guard !isCacheLoadInProgress,
              !isAppInBackground,
              !syncCoordinator.isInProgress(.health),
              !syncCoordinator.isInProgress(.strava),
              !isHealthAuthorizationRecoveryCheckInProgress else {
            queueDataSourceSynchronization(showsLoadingIndicator: showsLoadingIndicator)
            if showsLoadingIndicator, isCacheLoadInProgress {
                showCacheLoadLoadingIndicatorIfNeeded()
            } else if showsLoadingIndicator, syncCoordinator.isInProgress(.health) {
                showHealthSyncLoadingIndicatorIfNeeded()
            } else if showsLoadingIndicator, syncCoordinator.isInProgress(.strava) {
                showStravaSyncLoadingIndicatorIfNeeded()
            }
            PTrackLog.synchronization.debug("PTrack Sync: coalesced data-source synchronization behind the active operation")
            return
        }

        updateHeaderReadAuthorizationState()

        switch store.authorizationState {
        case .authorized:
            queueStravaSyncAfterHealthIfNeeded(showsLoadingIndicator: showsLoadingIndicator)
            loadAuthorizedHealthWorkouts(showsLoadingIndicator: showsLoadingIndicator)
        case .needsAttention:
            PTrackLog.synchronization.debug("PTrack HealthKit: checking pending authorization on app open")
            queueStravaSyncAfterHealthIfNeeded(showsLoadingIndicator: showsLoadingIndicator)
            recoverHealthAuthorizationIfNeeded(showsLoadingIndicator: showsLoadingIndicator)
        case .notDetermined:
            PTrackLog.synchronization.debug("PTrack HealthKit: skipped import, no stored authorization")
            loadAuthorizedStravaWorkouts(showsLoadingIndicator: showsLoadingIndicator)
        }
    }

    func updatePullRefreshTracking(for scrollView: UIScrollView) {
        guard scrollView.isDragging else {
            isPullRefreshArmedInCurrentDrag = false
            return
        }

        let pullDistance = max(-(scrollView.contentOffset.y + scrollView.contentInset.top), 0)
        isPullRefreshArmedInCurrentDrag = pullDistance >= pullRefreshTriggerDistance
    }

    private func updateScrollDateIndicator(for scrollView: UIScrollView) {
        guard scrollView === collectionView,
              !isRouteBookModeActive,
              !workouts.isEmpty,
              updateScrollDateIndicatorTextForVisibleWorkout() else {
            resetScrollDateIndicatorTracking()
            setScrollDateIndicatorVisible(false, animated: true)
            return
        }

        let now = CACurrentMediaTime()
        let currentOffsetY = scrollView.contentOffset.y
        let panVelocityY = scrollView.panGestureRecognizer.velocity(in: scrollView).y
        let measuredVelocityY: CGFloat
        if let lastOffsetY = lastScrollDateIndicatorOffsetY,
           let lastTimestamp = lastScrollDateIndicatorTimestamp {
            let elapsedTime = max(now - lastTimestamp, 0.001)
            measuredVelocityY = (currentOffsetY - lastOffsetY) / CGFloat(elapsedTime)
        } else {
            measuredVelocityY = 0
        }

        lastScrollDateIndicatorOffsetY = currentOffsetY
        lastScrollDateIndicatorTimestamp = now

        let isFastScroll = abs(panVelocityY) > 780 || abs(measuredVelocityY) > 780 || scrollView.isDecelerating
        guard isFastScroll else {
            if isScrollDateIndicatorVisible {
                scheduleScrollDateIndicatorHide()
            }
            return
        }

        setScrollDateIndicatorVisible(true, animated: true)
    }

    private func updateScrollDateIndicatorTextForVisibleWorkout() -> Bool {
        guard let visibleIndexPath = collectionView.indexPathsForVisibleItems
            .filter({ $0.section == 0 && $0.item >= 0 && $0.item < workouts.count })
            .min(by: { lhs, rhs in
                let lhsFrame = collectionView.layoutAttributesForItem(at: lhs)?.frame ?? .zero
                let rhsFrame = collectionView.layoutAttributesForItem(at: rhs)?.frame ?? .zero
                if abs(lhsFrame.minY - rhsFrame.minY) > 0.5 {
                    return lhsFrame.minY < rhsFrame.minY
                }

                return lhs.item < rhs.item
            }) else {
            return false
        }

        let dateText = scrollDateFormatter.string(from: workouts[visibleIndexPath.item].startDate)
        guard dateText != lastScrollDateIndicatorText else {
            return true
        }

        lastScrollDateIndicatorText = dateText
        scrollDateIndicatorLabel.text = dateText
        return true
    }

    private func setScrollDateIndicatorVisible(_ isVisible: Bool, animated: Bool) {
        scrollDateIndicatorHideWorkItem?.cancel()
        scrollDateIndicatorHideWorkItem = nil

        guard !isVisible || (!isRouteBookModeActive && !workouts.isEmpty) else {
            return
        }

        let changes = {
            self.scrollDateIndicatorView.alpha = isVisible ? 1 : 0
            self.scrollDateIndicatorView.transform = isVisible
                ? .identity
                : CGAffineTransform(translationX: 0, y: -4)
        }

        if isVisible {
            scrollDateIndicatorView.isHidden = false
            view.bringSubviewToFront(scrollDateIndicatorView)
        }

        guard isScrollDateIndicatorVisible != isVisible || scrollDateIndicatorView.isHidden == isVisible else {
            changes()
            return
        }

        isScrollDateIndicatorVisible = isVisible

        guard animated else {
            changes()
            scrollDateIndicatorView.isHidden = !isVisible
            return
        }

        UIView.animate(
            withDuration: isVisible ? 0.18 : 0.2,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: changes
        ) { _ in
            self.scrollDateIndicatorView.isHidden = !isVisible
        }
    }

    private func scheduleScrollDateIndicatorHide(delay: TimeInterval = 0.5) {
        scrollDateIndicatorHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.setScrollDateIndicatorVisible(false, animated: true)
        }
        scrollDateIndicatorHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func resetScrollDateIndicatorTracking() {
        lastScrollDateIndicatorOffsetY = nil
        lastScrollDateIndicatorTimestamp = nil
    }

    func performPullRefreshIfNeeded() {
        guard isPullRefreshArmedInCurrentDrag else {
            isPullRefreshArmedInCurrentDrag = false
            return
        }

        isPullRefreshArmedInCurrentDrag = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        synchronizeDataSourcesForPullRefresh()
    }

    func finishPullRefreshTracking() {
        isPullRefreshArmedInCurrentDrag = false
    }

    private var isDataSourceSyncInProgress: Bool {
        isCacheLoadInProgress
            || syncCoordinator.isInProgress(.health)
            || syncCoordinator.isInProgress(.strava)
    }

    private var authoritativeWorkouts: [TrackedWorkout] {
        workouts + pendingWorkouts
    }

    private func synchronizeDataSourcesForPullRefresh() {
        if isCacheLoadInProgress {
            showCacheLoadLoadingIndicatorIfNeeded()
        }

        synchronizeDataSourcesForAppOpen()
    }

    private func queueDataSourceSynchronization(showsLoadingIndicator: Bool) {
        syncCoordinator.queueDataSource(showsLoadingIndicator: showsLoadingIndicator)
    }

    @discardableResult
    private func runPendingDataSourceSynchronizationIfNeeded() -> Bool {
        guard syncCoordinator.pendingDataSourceRequest != nil,
              pendingDataSourceSyncRetryNotBefore.map({ $0 <= Date() }) != false,
              !isCacheLoadInProgress,
              !isAppInBackground,
              !syncCoordinator.isInProgress(.health),
              !syncCoordinator.isInProgress(.strava),
              !isHealthAuthorizationRecoveryCheckInProgress else {
            return false
        }

        guard let request = syncCoordinator.takePendingDataSourceRequest() else {
            return false
        }
        pendingDataSourceSyncRetryWorkItem?.cancel()
        pendingDataSourceSyncRetryWorkItem = nil
        pendingDataSourceSyncRetryNotBefore = nil
        synchronizeDataSourcesForAppOpen(showsLoadingIndicator: request.showsLoadingIndicator)
        return true
    }

    private func queueStravaSyncAfterHealthIfNeeded(showsLoadingIndicator: Bool) {
        guard StravaManager.shared.hasStoredAuthorization else {
            return
        }

        syncCoordinator.queueStrava(
            showsLoadingIndicator: showsLoadingIndicator,
            presentsErrors: false
        )
    }

    private func queueStravaSync(
        showsLoadingIndicator: Bool,
        presentsErrors: Bool
    ) {
        guard StravaManager.shared.hasStoredAuthorization else {
            return
        }

        syncCoordinator.queueStrava(
            showsLoadingIndicator: showsLoadingIndicator,
            presentsErrors: presentsErrors
        )
    }

    @discardableResult
    private func runPendingStravaSyncAfterHealthIfNeeded() -> Bool {
        guard syncCoordinator.pendingStravaRequest != nil,
              pendingDataSourceSyncRetryNotBefore.map({ $0 <= Date() }) != false,
              !isCacheLoadInProgress,
              !isAppInBackground,
              !syncCoordinator.isInProgress(.health),
              !syncCoordinator.isInProgress(.strava) else {
            return false
        }

        guard let request = syncCoordinator.takePendingStravaRequest() else {
            return false
        }
        pendingDataSourceSyncRetryWorkItem?.cancel()
        pendingDataSourceSyncRetryWorkItem = nil
        pendingDataSourceSyncRetryNotBefore = nil
        loadAuthorizedStravaWorkouts(
            showsLoadingIndicator: request.showsLoadingIndicator,
            presentsErrors: request.presentsErrors
        )
        return true
    }

    private func continueDataSourceSynchronizationAfterHealth() {
        if syncCoordinator.needsHealthRepairAfterStrava,
           runPendingHealthRepairAfterStravaIfNeeded(canConsumePendingFullRefresh: false) {
            return
        }
        if !runPendingStravaSyncAfterHealthIfNeeded() {
            _ = runPendingDataSourceSynchronizationIfNeeded()
        }
    }

    private func continueDataSourceSynchronizationAfterStrava(
        completion: WorkoutSyncCoordinator.StravaCompletion
    ) {
        let completedActivitySummary: Bool
        let shouldContinuePendingWithoutStrava: Bool
        switch completion {
        case .summarySuccess:
            completedActivitySummary = true
            shouldContinuePendingWithoutStrava = false
        case .partialSuccess:
            completedActivitySummary = false
            shouldContinuePendingWithoutStrava = false
        case .failure(_, let retriesQueuedStravaImmediately, let schedulesPendingRetry):
            completedActivitySummary = false
            shouldContinuePendingWithoutStrava = !retriesQueuedStravaImmediately
                && !schedulesPendingRetry
        }

        if case .partialSuccess(let retryAfter) = completion,
           retryAfter != nil {
            schedulePendingDataSourceSynchronizationRetryIfNeeded(retryAfter: retryAfter)
        } else if case .failure(
            let retryAfter,
            let retriesQueuedStravaImmediately,
            let schedulesPendingRetry
        ) = completion,
                  !retriesQueuedStravaImmediately,
                  schedulesPendingRetry {
            schedulePendingDataSourceSynchronizationRetryIfNeeded(retryAfter: retryAfter)
        }

        if case .summarySuccess(let detailRetryAfter) = completion,
           detailRetryAfter != nil {
            // The complete summary already satisfies a duplicate queued Strava
            // refresh. Keep detail enrichment on its own delayed intent instead
            // of immediately spending another stream-request budget.
            syncCoordinator.clearPendingStravaRequest()
        } else if shouldContinuePendingWithoutStrava {
            // A non-retryable Strava failure must not strand the HealthKit half
            // of a pull refresh, nor leave an impossible Strava retry queued.
            syncCoordinator.clearPendingStravaRequest()
        }

        if runPendingHealthRepairAfterStravaIfNeeded(
            canConsumePendingFullRefresh: completedActivitySummary
                || shouldContinuePendingWithoutStrava
        ) {
            return
        }

        switch completion {
        case .summarySuccess(let detailRetryAfter):
            pendingDataSourceSyncRetryAttempt = 0
            pendingDataSourceSyncRetryNotBefore = nil
            guard detailRetryAfter == nil else {
                return
            }
            if !runPendingDataSourceSynchronizationIfNeeded() {
                _ = runPendingStravaSyncAfterHealthIfNeeded()
            }
        case .partialSuccess(let retryAfter):
            guard retryAfter == nil else {
                return
            }
            pendingDataSourceSyncRetryAttempt = 0
            pendingDataSourceSyncRetryNotBefore = nil
            if !runPendingDataSourceSynchronizationIfNeeded() {
                _ = runPendingStravaSyncAfterHealthIfNeeded()
            }
        case .failure(_, let retriesQueuedStravaImmediately, _):
            if retriesQueuedStravaImmediately,
               runPendingStravaSyncAfterHealthIfNeeded() {
                return
            }
        }
    }

    private func schedulePendingDataSourceSynchronizationRetryIfNeeded(retryAfter: Date?) {
        guard syncCoordinator.pendingDataSourceRequest != nil
                || syncCoordinator.pendingStravaRequest != nil else {
            return
        }

        pendingDataSourceSyncRetryWorkItem?.cancel()
        pendingDataSourceSyncRetryWorkItem = nil
        pendingDataSourceSyncRetryAttempt += 1
        let retryExponent = min(max(pendingDataSourceSyncRetryAttempt - 1, 0), 8)
        let fallbackDelay = min(TimeInterval(5 * (1 << retryExponent)), 15 * 60)
        let delay = max(retryAfter?.timeIntervalSinceNow ?? fallbackDelay, fallbackDelay)
        pendingDataSourceSyncRetryNotBefore = Date().addingTimeInterval(delay)
        guard syncStateStore.stravaDeferredRetryAttempt
                <= stravaMaximumAutomaticUnchangedRetryCount else {
            PTrackLog.synchronization.debug(
                "PTrack Strava: stopped autonomous retries after \(self.syncStateStore.stravaDeferredRetryAttempt) unchanged attempt(s); a later app-open refresh remains gated until \(Self.debugDateString(self.pendingDataSourceSyncRetryNotBefore))"
            )
            return
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.pendingDataSourceSyncRetryWorkItem = nil
            if !self.runPendingDataSourceSynchronizationIfNeeded() {
                _ = self.runPendingStravaSyncAfterHealthIfNeeded()
            }
        }
        pendingDataSourceSyncRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    @discardableResult
    private func runPendingHealthRepairAfterStravaIfNeeded(
        canConsumePendingFullRefresh: Bool
    ) -> Bool {
        let hasHealthOnlyWork = syncCoordinator.needsHealthRepairAfterStrava
            || (canConsumePendingFullRefresh && syncCoordinator.pendingDataSourceRequest != nil)
        guard hasHealthOnlyWork,
              !isCacheLoadInProgress,
              !isAppInBackground,
              !syncCoordinator.isInProgress(.health),
              !syncCoordinator.isInProgress(.strava),
              !isHealthAuthorizationRecoveryCheckInProgress else {
            return false
        }

        // The just-finished pass either satisfied the queued Strava refresh or
        // reached a non-retryable Strava failure. Merge its loading preference
        // into Health-only work so the other source is never stranded.
        let showsLoadingIndicator = canConsumePendingFullRefresh
            ? syncCoordinator.takePendingDataSourceRequest()?.showsLoadingIndicator == true
            : false
        syncCoordinator.consumeHealthRepairAfterStrava()

        switch store.authorizationState {
        case .authorized:
            loadAuthorizedHealthWorkouts(showsLoadingIndicator: showsLoadingIndicator)
            return true
        case .needsAttention:
            recoverHealthAuthorizationIfNeeded(showsLoadingIndicator: showsLoadingIndicator)
            return true
        case .notDetermined:
            return false
        }
    }

    private func updateTotalDistanceText() {
        if isNewDataSyncInProgress, !isSimulatingHomeEmptyData {
            totalDistanceLabel.text = AppLocalization.text(.newDataSyncing)
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
            return
        }

        let authoritativeTotalDistanceMeters = totalDistanceMeters
            + pendingWorkouts.reduce(0) { $0 + $1.distanceMeters }
        let displayedTotalDistanceMeters = isSimulatingHomeEmptyData
            ? 0
            : (cachedWorkoutSummary?.totalDistanceMeters ?? authoritativeTotalDistanceMeters)
        let displayedWorkoutCount = isSimulatingHomeEmptyData
            ? 0
            : (cachedWorkoutSummary?.workoutCount ?? authoritativeWorkouts.count)
        let totalKilometers = displayedTotalDistanceMeters / 1000
        let distanceText = AppLocalization.format(.totalDistanceFormat, Int(totalKilometers.rounded()))
        let activityCountText = AppLocalization.format(.totalActivityCountFormat, displayedWorkoutCount)
        totalDistanceLabel.text = "\(distanceText)/\(activityCountText)"
        updateHeaderReadAuthorizationState()
        updateEmptyDataSourceVisibility()
    }

    private func updateEmptyDataSourceVisibility() {
        let displayedAppleHealthAuthorizationState: HealthWorkoutStore.AuthorizationState = isSimulatingHomeEmptyData
            ? .authorized
            : store.authorizationState
        emptyDataSourceView.updateAuthorizationState(appleHealth: displayedAppleHealthAuthorizationState)

        let hasDisplayedWorkouts = !authoritativeWorkouts.isEmpty
            || (cachedWorkoutSummary?.workoutCount ?? 0) > 0
        guard !isRouteBookModeActive,
              isSimulatingHomeEmptyData || !hasDisplayedWorkouts else {
            emptyDataSourceView.isHidden = true
            return
        }

        if isSimulatingHomeEmptyData {
            emptyDataSourceView.setMode(.noData)
        } else if isDataSourceSyncInProgress {
            emptyDataSourceView.setMode(.loading)
        } else if hasReadableDataSourceAuthorization {
            emptyDataSourceView.setMode(.noData)
        } else {
            emptyDataSourceView.setMode(.authorization)
        }
        emptyDataSourceView.isHidden = false
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
        demoModeEntryButton.setTitle(AppLocalization.text(.demoModeEntry), for: .normal)
        updateTotalDistanceText()
        if let routeBookWorkout {
            routeBookPanelDistanceLabel.text = routeBookPanelDistanceText(for: routeBookWorkout)
            routeBookPanelDistanceLabel.isHidden = routeBookPanelDistanceLabel.text == nil
        }
        emptyDataSourceView.updateLocalizedText()
        routeBookMapStyleButton.menu = makeRouteBookMapStyleMenu()
        routeBookMapStyleButton.accessibilityLabel = AppLocalization.text(.mapStyle)
        routeBookSlopeVisibilityButton.accessibilityLabel = AppLocalization.text(.routeSlope)
        scrollDateFormatter = Self.makeHomeScrollDateFormatter()
        lastScrollDateIndicatorText = nil
        _ = updateScrollDateIndicatorTextForVisibleWorkout()
        updateHeaderMoreButtonMode()
        collectionView.reloadData()
    }

    private func registerRouteBookObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteBookWorkoutDidSelect(_:)),
            name: RouteBookMode.didSelectWorkoutNotification,
            object: nil
        )
    }

    private func registerSharedRouteImportObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePendingSharedRoutesDidChange),
            name: SharedRouteImportInbox.pendingRoutesDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteCollectionOpenRequest),
            name: SharedRouteImportInbox.openRouteCollectionNotification,
            object: nil
        )
    }

    private func registerAppLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    private func registerHealthAuthorizationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHealthAuthorizationStateDidChange),
            name: HealthWorkoutStore.authorizationStateDidChangeNotification,
            object: nil
        )
    }

    private func registerTraitChangeHandler() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (viewController: Self, _) in
            viewController.updateHeaderAppearanceColors()
            viewController.updateScrollDateIndicatorAppearance()
            viewController.updateRouteBookLocateButtonAppearance()
            viewController.updateRouteBookPanelAppearanceColors()
            viewController.collectionView?.reloadData()
        }
    }

    @objc private func handleAppWillEnterForeground() {
        isAppInBackground = false
        AppLanguageStore.shared.refreshFromSystemSettingsIfNeeded()
        if !isCacheLoadInProgress,
           (!dirtyCacheWorkoutIDs.isEmpty || !deletedCacheWorkoutIDs.isEmpty) {
            scheduleCacheSave(delay: 0)
        }
        if !runPendingHealthRepairAfterStravaIfNeeded(canConsumePendingFullRefresh: false) {
            recoverHealthAuthorizationIfNeeded(showsLoadingIndicator: false)
        }
        updateHeaderReadAuthorizationState()
        updateEmptyDataSourceVisibility()
    }

    @objc private func handleAppDidEnterBackground() {
        isAppInBackground = true
        _ = flushPendingWorkouts(force: true)

        guard !isCacheLoadInProgress else {
            PTrackLog.synchronization.debug("PTrack Cache: skipped background save while the complete cache snapshot is still loading")
            return
        }

        guard isCacheSaveInProgress
                || !dirtyCacheWorkoutIDs.isEmpty
                || !deletedCacheWorkoutIDs.isEmpty else {
            refreshWidgetSnapshot()
            return
        }

        if beginBackgroundCacheSaveTaskIfNeeded() {
            runAfterPendingCacheSave { [weak self] in
                self?.endBackgroundCacheSaveTask()
            }
        }
        scheduleCacheSave(delay: 0)
    }

    @discardableResult
    private func beginBackgroundCacheSaveTaskIfNeeded() -> Bool {
        guard backgroundCacheSaveTask == .invalid else {
            return false
        }

        backgroundCacheSaveTask = UIApplication.shared.beginBackgroundTask(
            withName: "PTrackWorkoutCacheSave"
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.endBackgroundCacheSaveTask()
            }
        }
        return backgroundCacheSaveTask != .invalid
    }

    private func endBackgroundCacheSaveTask() {
        guard backgroundCacheSaveTask != .invalid else {
            return
        }

        let task = backgroundCacheSaveTask
        backgroundCacheSaveTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }

    @objc private func handleHealthAuthorizationStateDidChange() {
        Task { @MainActor in
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
        }
    }

    @objc private func handlePendingSharedRoutesDidChange() {
        importPendingSharedRoutesIfNeeded()
        updateHeaderMoreButtonMode()
    }

    @objc private func handleRouteCollectionOpenRequest() {
        importPendingSharedRoutesIfNeeded()
        updateHeaderMoreButtonMode()
        openRouteCollectionIfRequested()
    }

    private func importPendingSharedRoutesIfNeeded() {
        let importedRoutes = SharedRouteImportInbox.importPendingRoutes()
        if !importedRoutes.isEmpty {
            PTrackLog.synchronization.debug("PTrack Route Collection: imported \(importedRoutes.count) shared GPX routes")
        }
        updateRouteCollectionBadgeVisibility()
    }

    private func openRouteCollectionFromDeepLink() {
        guard let navigationController else {
            return
        }

        if navigationController.topViewController is RouteCollectionViewController {
            return
        }

        if isRouteBookModeActive {
            exitRouteBookMode()
        }

        if navigationController.topViewController !== self {
            navigationController.popToViewController(self, animated: false)
        }

        showRouteCollection()
    }

    private func openRouteCollectionIfRequested() {
        guard SharedRouteImportInbox.hasPendingRouteCollectionOpenRequest,
              isViewLoaded,
              navigationController?.view.window != nil else {
            return
        }

        SharedRouteImportInbox.consumeRouteCollectionOpenRequest()
        importPendingSharedRoutesIfNeeded()
        updateHeaderMoreButtonMode()

        DispatchQueue.main.async { [weak self] in
            self?.openRouteCollectionFromDeepLink()
        }
    }

    private func clearRouteImportIndicatorsIfNeededOnHomeAppear() {
        guard shouldClearRouteImportIndicatorsOnNextHomeAppear else {
            return
        }

        shouldClearRouteImportIndicatorsOnNextHomeAppear = false
        SharedRouteImportInbox.clearRouteImportIndicators()
        updateHeaderMoreButtonMode()
    }

    @objc private func handleRouteBookWorkoutDidSelect(_ notification: Notification) {
        guard let workout = notification.userInfo?[RouteBookMode.workoutUserInfoKey] as? TrackedWorkout else {
            return
        }

        enterRouteBookMode(with: workout)
    }

    private func loadCachedWorkoutSummary() {
        let startupState = cacheStore.loadStartupState()
        let integrityStatus = startupState.integrityStatus
        didDetectCacheIntegrityIssue = integrityStatus.requiresReconciliation
        needsHealthCacheIntegrityRepair = integrityStatus.requiresReconciliation
        needsStravaCacheIntegrityRepair = integrityStatus.requiresReconciliation
        isCachePersistenceHealthy = !integrityStatus.requiresReconciliation
        cachedWorkoutSummary = startupState.summary
        cachedManifestWorkoutIDs = startupState.indexedWorkoutIDs
        if integrityStatus.requiresReconciliation {
            markHealthHistoricalBackfillRequired()
            markStravaHistoricalBackfillRequired()
            PTrackLog.synchronization.debug(
                "PTrack Cache: startup reconciliation required, indexed: \(integrityStatus.indexedWorkoutCount), files: \(integrityStatus.existingWorkoutFileCount), orphaned: \(integrityStatus.orphanedWorkoutFileCount), missing: \(integrityStatus.missingIndexedWorkoutFileCount)"
            )
        }
    }

    private func loadCachedWorkoutsThenSynchronize() {
        isCacheLoadInProgress = true
        updateRouteGridPrefetchingState()
        isCacheLoadShowingLoadingIndicator = cachedWorkoutSummary == nil
        if isCacheLoadShowingLoadingIndicator {
            beginLoadingOperation()
        } else {
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
        }

        cacheLoadQueue.async { [weak self] in
            guard let self else {
                return
            }

            let cacheLoadResult = self.cacheStore.loadProgressively(
                batchSize: self.cacheLoadPreviewBatchSize,
                shouldContinue: { [weak self] in
                    self != nil
                },
                onBatch: { [weak self] cachedWorkoutBatch in
                    guard let self else {
                        return
                    }

                    let previewBatch = cachedWorkoutBatch.map {
                        $0.listPreview(maximumCoordinateCount: self.homePreviewCoordinateLimit)
                    }

                    DispatchQueue.main.async { [weak self] in
                        self?.appendCachedWorkoutBatch(previewBatch)
                    }
                }
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                let loadedWorkoutCount = cacheLoadResult.loadedWorkoutCount
                let hadCachedSummary = self.cachedWorkoutSummary != nil
                let loadedWorkoutIDs = Set(self.authoritativeWorkouts.map(\.id))
                let didLoadEveryIndexedWorkout = self.cachedManifestWorkoutIDs.map {
                    $0.isSubset(of: loadedWorkoutIDs)
                } ?? true
                let didLoadCompleteCacheSnapshot = cacheLoadResult.didFinishScanningWorkoutFiles
                    && loadedWorkoutCount == cacheLoadResult.discoveredWorkoutFileCount
                    && didLoadEveryIndexedWorkout
                if !didLoadCompleteCacheSnapshot {
                    self.didDetectCacheIntegrityIssue = true
                    self.needsHealthCacheIntegrityRepair = true
                    self.needsStravaCacheIntegrityRepair = true
                    self.isCachePersistenceHealthy = false
                    self.markHealthHistoricalBackfillRequired()
                    self.markStravaHistoricalBackfillRequired()
                    PTrackLog.synchronization.debug(
                        "PTrack Cache: decoded \(loadedWorkoutCount)/\(cacheLoadResult.discoveredWorkoutFileCount) discovered workout file(s); scheduling source reconciliation for unreadable records"
                    )
                }
                let manifestRebuildSnapshot = self.finishApplyingCachedWorkoutPreviews(
                    canRebuildManifest: didLoadCompleteCacheSnapshot
                )
                guard let manifestRebuildSnapshot else {
                    self.completeCachedWorkoutLoad(
                        loadedWorkoutCount: loadedWorkoutCount,
                        hadCachedSummary: hadCachedSummary
                    )
                    return
                }

                // Cache loading and all preview-batch applications are complete
                // at this point. Keep the cache-load gate closed while the
                // manifest transaction runs back on the serial load queue, so a
                // save or source sync cannot race its directory moves.
                self.cacheLoadQueue.async { [weak self, manifestRebuildSnapshot] in
                    guard let self else {
                        return
                    }

                    let rebuildResult = self.cacheStore.rebuildManifestAfterCompleteLoad(
                        for: manifestRebuildSnapshot
                    )
                    DispatchQueue.main.async { [weak self] in
                        guard let self else {
                            return
                        }

                        self.isCachePersistenceHealthy = rebuildResult.didSucceed
                        if rebuildResult.didSucceed {
                            self.cachedWorkoutSummary = nil
                            self.cachedManifestWorkoutIDs = Set(
                                manifestRebuildSnapshot.map(\.id)
                            )
                            self.updateTotalDistanceText()
                        } else {
                            self.didDetectCacheIntegrityIssue = true
                            self.needsHealthCacheIntegrityRepair = true
                            self.needsStravaCacheIntegrityRepair = true
                            self.markHealthHistoricalBackfillRequired()
                            self.markStravaHistoricalBackfillRequired()
                        }
                        self.completeCachedWorkoutLoad(
                            loadedWorkoutCount: loadedWorkoutCount,
                            hadCachedSummary: hadCachedSummary
                        )
                    }
                }
            }
        }
    }

    private func appendCachedWorkoutBatch(_ cachedWorkoutBatch: [TrackedWorkout]) {
        guard isCacheLoadInProgress, !cachedWorkoutBatch.isEmpty else {
            return
        }

        let incomingWorkouts = cachedWorkoutBatch.filter { knownWorkoutIDs.insert($0.id).inserted }
        guard !incomingWorkouts.isEmpty else {
            return
        }

        appendWorkoutsToList(incomingWorkouts)
        restorePersistedRouteBookModeIfNeeded()
    }

    private func finishApplyingCachedWorkoutPreviews(
        canRebuildManifest: Bool
    ) -> [TrackedWorkout]? {
        let didRemoveCachedConflicts = removeCachedAppleHealthWorkoutsConflictingWithStrava()
        markHealthAuthorizationVerifiedFromCachedWorkoutsIfNeeded()
        knownWorkoutIDs = Set(authoritativeWorkouts.map(\.id))
        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        let shouldRebuildCacheManifest = cachedWorkoutSummary == nil || didDetectCacheIntegrityIssue
        // Keep the manifest-backed total visible if even one cache file failed
        // to decode. A transient read must not replace a verified 1,500-item
        // summary with whichever subset happened to load (for example 226).
        if canRebuildManifest,
           !shouldRebuildCacheManifest,
           !didRemoveCachedConflicts {
            cachedWorkoutSummary = nil
        }
        updateTotalDistanceText()
        if didRemoveCachedConflicts {
            collectionView.reloadData()
        }
        prewarmInitialRouteSources()
        restorePersistedRouteBookModeIfNeeded()
        if shouldRebuildCacheManifest, canRebuildManifest {
            return authoritativeWorkouts
        } else if shouldRebuildCacheManifest {
            isCachePersistenceHealthy = false
            PTrackLog.synchronization.debug("PTrack Cache: skipped manifest rebuild because the workout-file scan did not complete")
        }
        return nil
    }

    private func completeCachedWorkoutLoad(
        loadedWorkoutCount: Int,
        hadCachedSummary: Bool
    ) {
        isCacheLoadInProgress = false
        refreshWidgetSnapshot()
        updateRouteGridPrefetchingState()
        if isCacheLoadShowingLoadingIndicator {
            isCacheLoadShowingLoadingIndicator = false
            endLoadingOperation()
        } else {
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
        }

        if needsCacheSaveAfterCurrentSave
            || !dirtyCacheWorkoutIDs.isEmpty
            || !deletedCacheWorkoutIDs.isEmpty {
            needsCacheSaveAfterCurrentSave = false
            scheduleCacheSave(delay: 0)
        }

        queueDataSourceSynchronization(
            showsLoadingIndicator: loadedWorkoutCount == 0 && !hadCachedSummary
        )
        _ = runPendingDataSourceSynchronizationIfNeeded()
    }

    private func markHealthAuthorizationVerifiedFromCachedWorkoutsIfNeeded() {
        guard workouts.contains(where: \.isHealthKitSource) else {
            return
        }

        store.markAuthorizationVerified()
    }

    private func recoverHealthAuthorizationIfNeeded(showsLoadingIndicator: Bool) {
        guard store.authorizationState == .needsAttention else {
            continueDataSourceSynchronizationAfterHealth()
            return
        }

        guard !syncCoordinator.isInProgress(.health) else {
            return
        }

        guard !isHealthAuthorizationRecoveryCheckInProgress else {
            return
        }

        isHealthAuthorizationRecoveryCheckInProgress = true
        store.authorizationRequestAvailability { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isHealthAuthorizationRecoveryCheckInProgress = false
                guard self.store.authorizationState == .needsAttention else {
                    self.continueDataSourceSynchronizationAfterHealth()
                    return
                }

                guard !self.syncCoordinator.isInProgress(.health) else {
                    return
                }

                switch result {
                case .success(.settingsRequired):
                    self.store.markAuthorizationVerified()
                    self.loadAuthorizedHealthWorkouts(showsLoadingIndicator: showsLoadingIndicator)
                case .success(.canRequest), .failure:
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                    self.continueDataSourceSynchronizationAfterHealth()
                }
            }
        }
    }

    private func loadAuthorizedHealthWorkouts(showsLoadingIndicator: Bool = true) {
        guard !isAppInBackground else {
            queueDataSourceSynchronization(showsLoadingIndicator: showsLoadingIndicator)
            PTrackLog.synchronization.debug("PTrack HealthKit: queued import until the app returns to the foreground")
            return
        }

        guard !isCacheLoadInProgress else {
            queueDataSourceSynchronization(showsLoadingIndicator: showsLoadingIndicator)
            if showsLoadingIndicator {
                showCacheLoadLoadingIndicatorIfNeeded()
            }
            PTrackLog.synchronization.debug("PTrack HealthKit: deferred import until cached workouts finish loading")
            return
        }

        guard !syncCoordinator.isInProgress(.strava) else {
            queueDataSourceSynchronization(showsLoadingIndicator: showsLoadingIndicator)
            if showsLoadingIndicator {
                showStravaSyncLoadingIndicatorIfNeeded()
            }
            PTrackLog.synchronization.debug("PTrack HealthKit: queued import behind the active Strava sync")
            return
        }

        guard !syncCoordinator.isInProgress(.health) else {
            if showsLoadingIndicator {
                showHealthSyncLoadingIndicatorIfNeeded()
            }
            return
        }

        syncCoordinator.begin(.health, showsLoadingIndicator: showsLoadingIndicator)
        if showsLoadingIndicator {
            beginLoadingOperation()
        } else {
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
        }
        loadIncrementalHealthWorkouts()
    }

    private func requestHealthAuthorizationAndLoadWorkouts() {
        guard !syncCoordinator.isInProgress(.health) else {
            return
        }

        syncCoordinator.begin(.health, showsLoadingIndicator: false)
        store.requestAuthorization { [weak self] authorizationResult in
            guard let self else { return }
            switch authorizationResult {
            case .success:
                Task { @MainActor in
                    guard !self.isAppInBackground,
                          !self.isCacheLoadInProgress,
                          !self.syncCoordinator.isInProgress(.strava) else {
                        _ = self.syncCoordinator.finish(.health)
                        self.queueDataSourceSynchronization(showsLoadingIndicator: true)
                        self.updateHeaderReadAuthorizationState()
                        self.updateEmptyDataSourceVisibility()
                        PTrackLog.synchronization.debug("PTrack HealthKit: queued newly authorized import behind the active operation")
                        return
                    }

                    _ = self.syncCoordinator.showLoadingIndicatorIfNeeded(.health)
                    self.beginLoadingOperation()
                    self.loadIncrementalHealthWorkouts()
                }
            case .failure(let error):
                PTrackLog.synchronization.debug("PTrack HealthKit: authorization failed: \(error)")
                Task { @MainActor in
                    _ = self.syncCoordinator.finish(.health)
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                    self.presentHealthAuthorizationError(error)
                    self.continueDataSourceSynchronizationAfterHealth()
                }
            }
        }
    }

    private func loadAuthorizedStravaWorkouts(
        showsLoadingIndicator: Bool = true,
        presentsErrors: Bool = false
    ) {
        guard StravaManager.shared.hasStoredAuthorization else {
            PTrackLog.synchronization.debug("PTrack Strava: skipped import, no stored authorization")
            updateHeaderReadAuthorizationState()
            continueDataSourceSynchronizationAfterStrava(
                completion: .partialSuccess(retryAfter: nil)
            )
            return
        }

        let cachedDirectStravaActivityIDs = directStravaActivityIDsInMemory()
        let latestStartDate = latestStravaStartDateForIncrementalSync()
        PTrackLog.synchronization.debug(
            "PTrack Strava: authorized import requested, latest incremental start: \(Self.debugDateString(latestStartDate)), cached direct Strava activities: \(cachedDirectStravaActivityIDs.count)"
        )
        loadStravaWorkouts(
            excludingStravaActivityIDs: cachedDirectStravaActivityIDs,
            after: latestStartDate,
            presentsErrors: presentsErrors,
            showsLoadingIndicator: showsLoadingIndicator
        )
    }

    private func loadStravaWorkouts(
        excludingStravaActivityIDs: Set<Int64>,
        after startDate: Date? = nil,
        presentsErrors: Bool,
        showsLoadingIndicator: Bool = true
    ) {
        guard !isAppInBackground else {
            queueStravaSync(
                showsLoadingIndicator: showsLoadingIndicator,
                presentsErrors: presentsErrors
            )
            PTrackLog.synchronization.debug("PTrack Strava: queued import until the app returns to the foreground")
            return
        }

        guard !isCacheLoadInProgress else {
            queueStravaSync(
                showsLoadingIndicator: showsLoadingIndicator,
                presentsErrors: presentsErrors
            )
            if showsLoadingIndicator {
                showCacheLoadLoadingIndicatorIfNeeded()
            }
            PTrackLog.synchronization.debug("PTrack Strava: deferred import until cached workouts finish loading")
            return
        }

        guard !syncCoordinator.isInProgress(.health) else {
            queueStravaSync(
                showsLoadingIndicator: showsLoadingIndicator,
                presentsErrors: presentsErrors
            )
            if showsLoadingIndicator {
                showHealthSyncLoadingIndicatorIfNeeded()
            }
            PTrackLog.synchronization.debug("PTrack Strava: queued import behind the active HealthKit sync")
            return
        }

        guard !syncCoordinator.isInProgress(.strava) else {
            queueStravaSync(
                showsLoadingIndicator: showsLoadingIndicator,
                presentsErrors: presentsErrors
            )
            if showsLoadingIndicator {
                showStravaSyncLoadingIndicatorIfNeeded()
            }
            PTrackLog.synchronization.debug("PTrack Strava: coalesced import behind the active Strava sync")
            return
        }

        guard let syncAthleteIDValue = StravaManager.shared.storedAthleteID else {
            markStravaHistoricalBackfillRequired()
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
            continueDataSourceSynchronizationAfterStrava(
                completion: .partialSuccess(retryAfter: nil)
            )
            PTrackLog.synchronization.debug("PTrack Strava: skipped import because the stored authorization has no athlete identity")
            return
        }
        let syncAthleteID = String(syncAthleteIDValue)
        let accountChange = confirmedStravaAthleteChange()

        if let accountChange {
            // A deferred date belongs to the previous account's import state.
            // Never let it postpone establishing the newly authorized owner.
            clearStravaDeferredRetryState()
            syncCoordinator.clearPendingStravaRequest()
            let currentAthleteActivityIDs = Set(
                authoritativeWorkouts.compactMap { workout -> Int64? in
                    guard workout.isDirectStravaSource,
                          workout.stravaAthleteID.map(String.init) == syncAthleteID else {
                        return nil
                    }
                    return workout.stravaActivityID
                }
            )
            let removedWorkoutCount = reconcileDirectStravaWorkouts(
                withAuthoritativeActivityIDs: currentAthleteActivityIDs
            )
            PTrackLog.synchronization.debug(
                "PTrack Strava: athlete changed from \(accountChange.previous) to \(accountChange.current); removed \(removedWorkoutCount) direct cached workout(s) before synchronization"
            )
        } else {
            // Tagged records from another athlete can only be leftovers from a
            // previously interrupted migration. Legacy untagged records are
            // provisionally owned by the current athlete until the first durable
            // pass commits their owner.
            let activityIDsAllowedForCurrentAthlete = Set(
                authoritativeWorkouts.compactMap { workout -> Int64? in
                    guard workout.isDirectStravaSource,
                          workout.stravaAthleteID.map({ String($0) == syncAthleteID }) != false else {
                        return nil
                    }
                    return workout.stravaActivityID
                }
            )
            let foreignWorkoutCount = authoritativeWorkouts.lazy.filter {
                $0.isDirectStravaSource
                    && $0.stravaAthleteID.map({ String($0) != syncAthleteID }) == true
            }.count
            if foreignWorkoutCount > 0 {
                _ = reconcileDirectStravaWorkouts(
                    withAuthoritativeActivityIDs: activityIDsAllowedForCurrentAthlete
                )
            }
        }

        let placeholderActivityIDsNeedingEnrichment = Set(
            authoritativeWorkouts.compactMap { workout -> Int64? in
                guard workout.isDirectStravaSource,
                      workout.isStravaSummaryPlaceholder,
                      !workout.isStravaTerminalPlaceholder else {
                    return nil
                }
                return workout.stravaActivityID
            }
        )
        // Authoritative repair needs a complete summary immediately. Once that
        // summary is durable, old placeholder detail is enriched on a cooldown;
        // count correctness must not force an 80-stream full pass on every open.
        let requiresHistoricalCoverageRepair = shouldRunStravaHistoricalBackfill()
        if accountChange == nil,
           requiresHistoricalCoverageRepair,
           let retryDate = syncStateStore.stravaDeferredRetryDate,
           retryDate > Date() {
            // Preserve a server/local backoff across process restarts. Queueing
            // the request before installing the coordinator timer also keeps a
            // pull-to-refresh from bypassing the same quota gate.
            queueStravaSync(
                showsLoadingIndicator: showsLoadingIndicator,
                presentsErrors: presentsErrors
            )
            pendingStravaEnrichmentRetryWorkItem?.cancel()
            pendingStravaEnrichmentRetryWorkItem = nil
            schedulePendingDataSourceSynchronizationRetryIfNeeded(
                retryAfter: retryDate
            )
            PTrackLog.synchronization.debug(
                "PTrack Strava: deferred historical repair until \(Self.debugDateString(retryDate))"
            )
            return
        }

        let deferredEnrichmentRetryDate = syncStateStore.stravaDeferredRetryDate
        let isPlaceholderEnrichmentDue: Bool
        if let deferredEnrichmentRetryDate {
            // A persisted exponential/server backoff always wins over the
            // routine six-hour maintenance cadence.
            isPlaceholderEnrichmentDue = deferredEnrichmentRetryDate <= Date()
        } else {
            isPlaceholderEnrichmentDue = isFullCoverageReconciliationDue(
                lastRunKey: DefaultsKey.stravaLastPlaceholderEnrichmentAttemptDate,
                interval: stravaPlaceholderEnrichmentInterval
            )
        }
        let shouldRunPlaceholderEnrichment = !requiresHistoricalCoverageRepair
            && !placeholderActivityIDsNeedingEnrichment.isEmpty
            && isPlaceholderEnrichmentDue
        let shouldRunHistoricalBackfill = requiresHistoricalCoverageRepair
            || shouldRunPlaceholderEnrichment
        let effectiveStartDate = shouldRunHistoricalBackfill ? nil : startDate
        let placeholderActivityIDsToEnrich = shouldRunHistoricalBackfill
            ? placeholderActivityIDsNeedingEnrichment
            : []
        let effectiveExcludedActivityIDs = excludingStravaActivityIDs
            .intersection(directStravaActivityIDsInMemory())
            .subtracting(placeholderActivityIDsToEnrich)

        let syncGeneration = syncCoordinator.beginStravaTransaction(
            athleteID: syncAthleteID,
            showsLoadingIndicator: showsLoadingIndicator,
            workouts: workouts,
            pendingWorkouts: pendingWorkouts
        )
        // A direct entry may start while an older gated request is still
        // queued. This transaction subsumes that intent; requests arriving
        // after this point remain queued for completion-time coordination.
        syncCoordinator.clearPendingStravaRequest()
        pendingStravaEnrichmentRetryWorkItem?.cancel()
        pendingStravaEnrichmentRetryWorkItem = nil
        pendingDataSourceSyncRetryWorkItem?.cancel()
        pendingDataSourceSyncRetryWorkItem = nil
        pendingDataSourceSyncRetryNotBefore = nil
        // Stage ownership for every pass, including a legacy owner=nil cache.
        // This closes the A -> B switch window even before the first full pass.
        stageStravaCachedAthleteIDCommit(
            syncAthleteID,
            syncGeneration: syncGeneration
        )

        if shouldRunHistoricalBackfill {
            // Keep an in-flight lease instead of clearing the persisted gate.
            // If the process is killed before a result arrives, the next launch
            // cannot immediately spend another full-history request budget.
            let leaseAttempt = max(syncStateStore.stravaDeferredRetryAttempt, 1)
            syncStateStore.stravaDeferredRetryDate = Date().addingTimeInterval(
                stravaRetryDelay(
                    baseDelay: stravaPersistedRetryBaseDelay(),
                    attempt: leaseAttempt
                )
            )
            UserDefaults.standard.set(
                Date(),
                forKey: DefaultsKey.stravaLastPlaceholderEnrichmentAttemptDate
            )
        }

        UserDefaults.standard.set(true, forKey: DefaultsKey.stravaImportInProgress)
        if showsLoadingIndicator {
            beginLoadingOperation()
        } else {
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
        }
        PTrackLog.synchronization.debug(
            "PTrack Strava: starting import, after: \(Self.debugDateString(effectiveStartDate)), excluding cached activities: \(effectiveExcludedActivityIDs.count), historical repair: \(requiresHistoricalCoverageRepair), placeholder enrichment: \(shouldRunPlaceholderEnrichment)"
        )

        let requestLimit = stravaRequestLimitPerPass
        Task { [weak self, requestLimit, syncGeneration, syncAthleteID] in
            do {
                let importResult = try await StravaManager.shared.loadTrackedWorkoutResult(
                    after: effectiveStartDate,
                    excludingStravaActivityIDs: effectiveExcludedActivityIDs,
                    requestLimit: requestLimit,
                    onNewDataDetected: { [weak self] _ in
                        await MainActor.run {
                            guard let self,
                                  self.isCurrentStravaSync(
                                      generation: syncGeneration,
                                      athleteID: syncAthleteID
                                  ) else {
                                return
                            }
                            self.setNewDataSyncInProgress(true, for: .strava)
                        }
                    },
                    onTrackedWorkouts: { [weak self] importedBatch in
                        await MainActor.run {
                            guard let self,
                                  self.isCurrentStravaSync(
                                      generation: syncGeneration,
                                      athleteID: syncAthleteID
                                  ) else {
                                return
                            }

                            self.upsertTrackedWorkouts(importedBatch)
                        }
                    }
                )
                let importedWorkouts = importResult.workouts

                guard let self else {
                    return
                }
                guard self.isCurrentStravaSync(
                    generation: syncGeneration,
                    athleteID: syncAthleteID
                ), String(importResult.athleteID) == syncAthleteID else {
                    throw StravaManagerError.authorizationChangedDuringImport
                }
                let resultAthleteID = String(importResult.athleteID)

                let didFlushPendingWorkouts = self.flushPendingWorkouts(force: true)
                let removedStaleStravaWorkoutCount: Int
                if importResult.didCompleteAuthoritativeSummary {
                    let reconciliationDecision = self.stravaReconciliationDecision(
                        after: importResult.reconciliationSnapshot
                    )
                    removedStaleStravaWorkoutCount = self.reconcileDirectStravaWorkouts(
                        withAuthoritativeActivityIDs: reconciliationDecision.retainedActivityIDs
                    )
                    self.stageStravaReconciliationRecordCommit(
                        importResult.reconciliationSnapshot,
                        missingCandidateIDs: reconciliationDecision.missingCandidateIDs,
                        syncGeneration: syncGeneration
                    )
                } else {
                    removedStaleStravaWorkoutCount = 0
                }
                if !importedWorkouts.isEmpty {
                    self.scheduleCacheSave(delay: 0)
                    PTrackLog.synchronization.debug("PTrack Strava: scheduled cache save for imported routes: \(importedWorkouts.count)")
                }
                if !importResult.didLoadCompleteActivitySummary {
                    self.markStravaHistoricalBackfillRequired()
                }
                self.markStravaHistoricalBackfillCompletedAfterCacheSaveIfNeeded(
                    didRunHistoricalBackfill: shouldRunHistoricalBackfill,
                    didCompleteAuthoritativeSummary: importResult.didCompleteAuthoritativeSummary,
                    syncGeneration: syncGeneration,
                    syncAthleteID: resultAthleteID
                )
                self.markStravaImportCompletedAfterCacheSaveIfNeeded(
                    didCompleteActivitySummary: importResult.didLoadCompleteActivitySummary,
                    syncGeneration: syncGeneration,
                    syncAthleteID: resultAthleteID
                )

                PTrackLog.synchronization.debug(
                    "PTrack Strava: import completed, loaded routes: \(importedWorkouts.count), removed stale: \(removedStaleStravaWorkoutCount), summary complete: \(importResult.didLoadCompleteActivitySummary), complete scope: \(importResult.didUseCompleteActivityReadScope), activity failures: \(importResult.failedActivityCount), terminal: \(importResult.terminalActivityCount), deferred: \(importResult.deferredActivityCount), flushed: \(didFlushPendingWorkouts)"
                )
                _ = self.syncCoordinator.finish(.strava, generation: syncGeneration)
                self.updateRouteGridPrefetchingState()
                self.updateTotalDistanceText()
                if self.syncCoordinator.consumeLoadingIndicator(.strava) {
                    self.endLoadingOperation()
                } else {
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                }
                let deferredRetryDate = self.scheduleDeferredStravaEnrichmentIfNeeded(
                    importResult,
                    didRunHistoricalPass: shouldRunHistoricalBackfill
                )
                let completion: WorkoutSyncCoordinator.StravaCompletion
                if importResult.didLoadCompleteActivitySummary {
                    completion = .summarySuccess(
                        detailRetryAfter: deferredRetryDate
                    )
                } else if let deferredRetryDate {
                    completion = .partialSuccess(retryAfter: deferredRetryDate)
                } else {
                    completion = .partialSuccess(retryAfter: nil)
                }
                self.continueDataSourceSynchronizationAfterStrava(completion: completion)
            } catch {
                guard let self else {
                    return
                }
                guard self.syncCoordinator.isCurrent(.strava, generation: syncGeneration) else {
                    return
                }

                PTrackLog.synchronization.debug("PTrack Strava: import failed: \(error)")
                let authorizationChanged = (error as? StravaManagerError).map {
                    if case .authorizationChangedDuringImport = $0 { return true }
                    return false
                } ?? false
                let requiresReauthorization = StravaManager.requiresReauthorization(error)
                let storedAthleteIDAfterFailure = StravaManager.shared.storedAthleteID
                    .map(String.init)
                // Only an actual A -> B credential handoff warrants one
                // immediate restart. A refresh response that repeatedly
                // disagrees with unchanged stored credentials must enter the
                // finite persisted backoff instead of spinning forever.
                let canRetryChangedAuthorizationImmediately = authorizationChanged
                    && storedAthleteIDAfterFailure != nil
                    && storedAthleteIDAfterFailure != syncAthleteID
                let shouldRetryAuthorizationMismatch = authorizationChanged
                    && storedAthleteIDAfterFailure == syncAthleteID
                let shouldRetryTransientFailure = !requiresReauthorization
                    && StravaManager.shared.hasStoredAuthorization
                    && (shouldRetryAuthorizationMismatch
                        || (!authorizationChanged
                            && StravaManager.shouldRetryImport(after: error)))
                var retryAfter = Self.stravaRetryDate(from: error)
                let didFlushPendingWorkouts: Bool
                if authorizationChanged {
                    didFlushPendingWorkouts = false
                    self.rollbackStravaTransaction(
                        generation: syncGeneration,
                        athleteID: syncAthleteID
                    )
                } else {
                    didFlushPendingWorkouts = self.flushPendingWorkouts(force: true)
                }
                self.markStravaHistoricalBackfillRequired()
                if didFlushPendingWorkouts
                    || !self.dirtyCacheWorkoutIDs.isEmpty
                    || !self.deletedCacheWorkoutIDs.isEmpty {
                    self.scheduleCacheSave(delay: 0)
                    PTrackLog.synchronization.debug("PTrack Strava: preserved partially imported routes for a durable retry")
                }
                _ = self.syncCoordinator.finish(.strava, generation: syncGeneration)
                self.updateRouteGridPrefetchingState()
                self.updateTotalDistanceText()
                if self.syncCoordinator.consumeLoadingIndicator(.strava) {
                    self.endLoadingOperation()
                } else {
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                }
                if requiresReauthorization {
                    self.clearStravaDeferredRetryState()
                    self.syncCoordinator.clearPendingStravaRequest()
                    self.presentSimpleAlert(
                        title: AppLocalization.text(.strava),
                        message: AppLocalization.text(.stravaReauthorizationRequired)
                    )
                } else if canRetryChangedAuthorizationImmediately {
                    self.clearStravaDeferredRetryState()
                    self.pendingDataSourceSyncRetryWorkItem?.cancel()
                    self.pendingDataSourceSyncRetryWorkItem = nil
                    self.pendingDataSourceSyncRetryAttempt = 0
                    self.pendingDataSourceSyncRetryNotBefore = nil
                    self.queueStravaSync(
                        showsLoadingIndicator: showsLoadingIndicator,
                        presentsErrors: presentsErrors
                    )
                } else if shouldRetryTransientFailure {
                    let transientRetry = self.registerStravaTransientRetryProgress(
                        for: error
                    )
                    retryAfter = max(
                        retryAfter ?? .distantPast,
                        transientRetry.0
                    )
                    self.pendingStravaEnrichmentRetryWorkItem?.cancel()
                    self.pendingStravaEnrichmentRetryWorkItem = nil
                    self.queueStravaSync(
                        showsLoadingIndicator: showsLoadingIndicator,
                        presentsErrors: presentsErrors
                    )
                } else if presentsErrors {
                    self.presentSimpleAlert(title: AppLocalization.text(.strava), message: error.localizedDescription)
                }
                self.continueDataSourceSynchronizationAfterStrava(
                    completion: .failure(
                        retryAfter: retryAfter,
                        retriesQueuedStravaImmediately: canRetryChangedAuthorizationImmediately,
                        schedulesPendingRetry: shouldRetryTransientFailure
                    )
                )
            }
        }
    }

    private func stravaReconciliationDecision(
        after snapshot: StravaManager.ActivityReconciliationSnapshot
    ) -> (retainedActivityIDs: Set<Int64>, missingCandidateIDs: Set<Int64>) {
        let currentLocalActivityIDs = directStravaActivityIDsInMemory()
        guard snapshot.isAuthoritative else {
            return (currentLocalActivityIDs, [])
        }

        let missingCandidateIDs = currentLocalActivityIDs.subtracting(snapshot.activityIDs)
        guard let previousSnapshot = syncStateStore.stravaReconciliationRecord,
              previousSnapshot.athleteID == String(snapshot.athleteID),
              let previousMissingCandidateIDs = previousSnapshot.missingCandidateIDs else {
            // The first complete absence is only a tombstone candidate. Keep
            // the local record until a second complete listing confirms it.
            return (
                currentLocalActivityIDs.union(snapshot.activityIDs),
                missingCandidateIDs
            )
        }

        let confirmedMissing = missingCandidateIDs.intersection(previousMissingCandidateIDs)
        return (
            currentLocalActivityIDs
                .subtracting(confirmedMissing)
                .union(snapshot.activityIDs),
            missingCandidateIDs
        )
    }

    private func stageStravaReconciliationRecordCommit(
        _ snapshot: StravaManager.ActivityReconciliationSnapshot,
        missingCandidateIDs: Set<Int64>,
        syncGeneration: UInt64
    ) {
        guard snapshot.isAuthoritative else {
            return
        }

        let athleteID = String(snapshot.athleteID)
        runAfterPendingCacheSave { [weak self] in
            guard let self,
                  self.isCurrentStravaSync(
                      generation: syncGeneration,
                      athleteID: athleteID
                  ),
                  self.isCachePersistenceHealthy else {
                return
            }
            self.syncStateStore.stravaReconciliationRecord = .init(
                athleteID: athleteID,
                activityIDs: snapshot.activityIDs,
                missingCandidateIDs: missingCandidateIDs,
                capturedAt: snapshot.capturedAt
            )
        }
    }

    private func rollbackStravaTransaction(generation: UInt64, athleteID: String) {
        guard let snapshot = syncCoordinator.rollbackSnapshot(
            generation: generation,
            athleteID: athleteID
        ) else {
            return
        }

        pendingFlushWorkItem?.cancel()
        pendingFlushWorkItem = nil
        let currentAuthoritativeWorkouts = authoritativeWorkouts
        let currentWorkoutIDs = Set(currentAuthoritativeWorkouts.map(\.id))
        let baselineWorkouts = snapshot.workouts + snapshot.pendingWorkouts
        let baselineWorkoutIDs = Set(baselineWorkouts.map(\.id))
        let newlyInsertedWorkoutIDs = currentWorkoutIDs.subtracting(baselineWorkoutIDs)
        let removedBaselineHealthIDs = Set(
            baselineWorkouts.lazy
                .filter(\.isHealthKitSource)
                .map(\.id)
        ).subtracting(currentWorkoutIDs)

        for workout in currentAuthoritativeWorkouts where newlyInsertedWorkoutIDs.contains(workout.id) {
            newWorkoutBadgeStore.markSeen(workout)
        }

        workouts = snapshot.workouts
        pendingWorkouts = snapshot.pendingWorkouts
        knownWorkoutIDs = baselineWorkoutIDs
        rebuildWorkoutIndexes()

        // Direct records written before the authorization changed were still
        // validated against this transaction's athlete, so their full on-disk
        // form is safe to retain. Rewriting them from list-preview snapshots
        // would discard route detail. Only restore HealthKit duplicates that
        // the abandoned generation temporarily displaced.
        for workoutID in removedBaselineHealthIDs
            where cacheStore.loadWorkout(id: workoutID) == nil {
            markCacheDirty(workoutID)
        }
        markCacheDeleted(newlyInsertedWorkoutIDs)
        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        updateTotalDistanceText()
        collectionView.reloadData()
        scheduleCacheSave(delay: 0)
        PTrackLog.synchronization.debug(
            "PTrack Strava: rolled back generation \(generation) after athlete authorization changed"
        )
    }

    private func scheduleDeferredStravaEnrichmentIfNeeded(
        _ result: StravaManager.LoadResult,
        didRunHistoricalPass: Bool
    ) -> Date? {
        if result.needsDeferredRetry {
            // An incomplete listing may not have produced a placeholder for
            // activities on pages that were never reached. Retry it even when
            // there is currently no local placeholder to inspect.
            let retryAttempt = registerStravaDeferredRetryProgress(for: result)
            let retryDelay = stravaRetryDelay(
                baseDelay: stravaIncompleteRetryBaseDelay,
                attempt: retryAttempt
            )
            let retryDate = max(
                result.retryAfterDate ?? .distantPast,
                Date().addingTimeInterval(retryDelay)
            ).addingTimeInterval(2)
            let hasCoordinatorRetry = !result.didLoadCompleteActivitySummary
                && (syncCoordinator.pendingDataSourceRequest != nil
                    || syncCoordinator.pendingStravaRequest != nil)
            scheduleDeferredStravaEnrichmentRetry(
                at: retryDate,
                schedulesWorkItem: retryAttempt <= stravaMaximumAutomaticUnchangedRetryCount
                    && !hasCoordinatorRetry
            )
            return retryDate
        }

        let hasPendingPlaceholderEnrichment = authoritativeWorkouts.contains { workout in
            workout.isDirectStravaSource
                && workout.isStravaSummaryPlaceholder
                && !workout.isStravaTerminalPlaceholder
        }

        guard hasPendingPlaceholderEnrichment else {
            clearStravaDeferredRetryState()
            return nil
        }

        let retryDate: Date
        let schedulesWorkItem: Bool
        if result.failedActivityCount > 0 {
            // Retry schema/transport/404 failures with persistent exponential
            // backoff. After repeated unchanged results, stop the autonomous
            // timer; a later app open can still make one gated recovery pass.
            let retryAttempt = registerStravaDeferredRetryProgress(for: result)
            retryDate = Date().addingTimeInterval(
                stravaRetryDelay(
                    baseDelay: stravaPlaceholderEnrichmentInterval,
                    attempt: retryAttempt
                )
            )
            schedulesWorkItem = retryAttempt <= stravaMaximumAutomaticUnchangedRetryCount
        } else if !didRunHistoricalPass,
                  let persistedRetryDate = syncStateStore.stravaDeferredRetryDate {
            // An ordinary incremental pass must not erase a future enrichment
            // retry restored after relaunch.
            retryDate = persistedRetryDate
            schedulesWorkItem = syncStateStore.stravaDeferredRetryAttempt
                <= stravaMaximumAutomaticUnchangedRetryCount
        } else {
            clearStravaDeferredRetryState()
            return nil
        }

        let hasCoordinatorRetry = !result.didLoadCompleteActivitySummary
            && (syncCoordinator.pendingDataSourceRequest != nil
                || syncCoordinator.pendingStravaRequest != nil)
        scheduleDeferredStravaEnrichmentRetry(
            at: retryDate,
            schedulesWorkItem: schedulesWorkItem && !hasCoordinatorRetry
        )
        return retryDate
    }

    private func scheduleDeferredStravaEnrichmentRetry(
        at retryDate: Date,
        schedulesWorkItem: Bool
    ) {
        syncStateStore.stravaDeferredRetryDate = retryDate
        pendingStravaEnrichmentRetryWorkItem?.cancel()
        pendingStravaEnrichmentRetryWorkItem = nil

        guard schedulesWorkItem else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.pendingStravaEnrichmentRetryWorkItem = nil
            self.queueStravaSync(showsLoadingIndicator: false, presentsErrors: false)
            _ = self.runPendingStravaSyncAfterHealthIfNeeded()
        }
        pendingStravaEnrichmentRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(retryDate.timeIntervalSinceNow, 1),
            execute: workItem
        )
    }

    private func registerStravaDeferredRetryProgress(
        for result: StravaManager.LoadResult
    ) -> Int {
        let snapshot = result.reconciliationSnapshot
        let progressKey = [
            String(snapshot.athleteID),
            snapshot.didReachNaturalEnd ? "complete" : "partial",
            String(snapshot.activityIDs.count),
            snapshot.activityIDs.min().map(String.init) ?? "none",
            snapshot.activityIDs.max().map(String.init) ?? "none",
            String(result.deferredActivityCount),
            String(result.failedActivityCount)
        ].joined(separator: "|")
        let didMakeProgress = syncStateStore.stravaDeferredRetryProgressKey != progressKey
        let retryAttempt = didMakeProgress
            ? 1
            : min(syncStateStore.stravaDeferredRetryAttempt + 1, 64)
        syncStateStore.stravaDeferredRetryProgressKey = progressKey
        syncStateStore.stravaDeferredRetryAttempt = retryAttempt
        if didMakeProgress {
            pendingDataSourceSyncRetryAttempt = 0
        }
        return retryAttempt
    }

    private func registerStravaTransientRetryProgress(for error: Error) -> (Date, Int) {
        let progressKey = "transient|\(Self.stravaRetryCategory(for: error))"
        let didChangeFailure = syncStateStore.stravaDeferredRetryProgressKey != progressKey
        let retryAttempt = didChangeFailure
            ? 1
            : min(syncStateStore.stravaDeferredRetryAttempt + 1, 64)
        syncStateStore.stravaDeferredRetryProgressKey = progressKey
        syncStateStore.stravaDeferredRetryAttempt = retryAttempt
        if didChangeFailure {
            pendingDataSourceSyncRetryAttempt = 0
        }
        let retryDate = Date().addingTimeInterval(
            stravaRetryDelay(
                baseDelay: stravaTransientRetryBaseDelay,
                attempt: retryAttempt
            )
        )
        syncStateStore.stravaDeferredRetryDate = retryDate
        return (retryDate, retryAttempt)
    }

    private func stravaRetryDelay(baseDelay: TimeInterval, attempt: Int) -> TimeInterval {
        let exponent = min(max(attempt - 1, 0), 10)
        return min(
            baseDelay * TimeInterval(1 << exponent),
            stravaRetryMaximumDelay
        )
    }

    private func stravaPersistedRetryBaseDelay() -> TimeInterval {
        guard let progressKey = syncStateStore.stravaDeferredRetryProgressKey else {
            return stravaIncompleteRetryBaseDelay
        }
        if progressKey.hasPrefix("transient|") {
            return stravaTransientRetryBaseDelay
        }
        if let failedCount = progressKey.split(separator: "|").last.flatMap({ Int($0) }),
           failedCount > 0 {
            return stravaPlaceholderEnrichmentInterval
        }
        return stravaIncompleteRetryBaseDelay
    }

    private func clearStravaDeferredRetryState() {
        syncStateStore.stravaDeferredRetryDate = nil
        syncStateStore.stravaDeferredRetryProgressKey = nil
        syncStateStore.stravaDeferredRetryAttempt = 0
        pendingStravaEnrichmentRetryWorkItem?.cancel()
        pendingStravaEnrichmentRetryWorkItem = nil
        pendingDataSourceSyncRetryWorkItem?.cancel()
        pendingDataSourceSyncRetryWorkItem = nil
        pendingDataSourceSyncRetryNotBefore = nil
        pendingDataSourceSyncRetryAttempt = 0
    }

    private static func stravaRetryDate(from error: Error) -> Date? {
        guard let managerError = error as? StravaManagerError,
              case .requestBudgetExhausted(let retryAfter) = managerError else {
            return nil
        }
        return retryAfter
    }

    private static func stravaRetryCategory(for error: Error) -> String {
        if let managerError = error as? StravaManagerError {
            if case .requestBudgetExhausted = managerError {
                return "request-budget"
            }
            return "manager-\(String(describing: managerError))"
        }
        guard let networkError = error as? NetworkError else {
            return String(describing: type(of: error))
        }
        switch networkError {
        case .httpStatus(let statusCode, _, _, _):
            return "http-\(statusCode)"
        case .decodingFailed(_, let statusCode, _, _):
            return "decode-\(statusCode)"
        case .transportFailed(let underlying):
            if let urlError = underlying as? URLError {
                return "transport-\(urlError.code.rawValue)"
            }
            return "transport"
        case .invalidResponse:
            return "invalid-response"
        case .invalidURL:
            return "invalid-url"
        }
    }

    private func latestStravaStartDateForIncrementalSync() -> Date? {
        guard !shouldRunStravaHistoricalBackfill() else {
            PTrackLog.synchronization.debug("PTrack Strava: historical backfill not completed; requesting full activity history")
            return nil
        }

        let latestStartDate = authoritativeWorkouts
            .filter(\.isDirectStravaSource)
            .map(\.startDate)
            .max()

        return latestStartDate?.addingTimeInterval(-stravaIncrementalLookback)
    }

    private func directStravaActivityIDsInMemory() -> Set<Int64> {
        Set(
            authoritativeWorkouts
                .filter(\.isDirectStravaSource)
                .compactMap(\.stravaActivityID)
        )
    }

    @discardableResult
    private func reconcileDirectStravaWorkouts(
        withAuthoritativeActivityIDs activityIDs: Set<Int64>
    ) -> Int {
        var removedWorkouts: [TrackedWorkout] = []
        workouts.removeAll { workout in
            guard workout.isDirectStravaSource,
                  workout.stravaActivityID.map({ !activityIDs.contains($0) }) ?? true else {
                return false
            }

            removedWorkouts.append(workout)
            return true
        }
        pendingWorkouts.removeAll { workout in
            guard workout.isDirectStravaSource,
                  workout.stravaActivityID.map({ !activityIDs.contains($0) }) ?? true else {
                return false
            }

            removedWorkouts.append(workout)
            return true
        }

        guard !removedWorkouts.isEmpty else {
            return 0
        }

        // A direct Strava record may previously have replaced its HealthKit
        // duplicate. Once that direct record disappears (account switch or
        // remote deletion), force a serialized HealthKit full pass so the
        // fallback source cannot remain missing until the periodic repair.
        // Invalidate any older Health cache-save completion before it can mark
        // this newly-required repair as complete.
        _ = syncCoordinator.beginGeneration(.health)
        markHealthHistoricalBackfillRequired()
        syncCoordinator.requireHealthRepairAfterStrava()

        for workout in removedWorkouts {
            knownWorkoutIDs.remove(workout.id)
            newWorkoutBadgeStore.markSeen(workout)
        }
        markCacheDeleted(Set(removedWorkouts.map(\.id)))
        rebuildWorkoutIndexes()
        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        updateTotalDistanceText()
        collectionView.reloadData()
        scheduleCacheSave(delay: 0)
        PTrackLog.synchronization.debug(
            "PTrack Strava: removed \(removedWorkouts.count) direct workout(s) absent from the complete current-athlete summary"
        )
        return removedWorkouts.count
    }

    private func shouldRunStravaHistoricalBackfill() -> Bool {
        needsStravaCacheIntegrityRepair
            || UserDefaults.standard.bool(forKey: DefaultsKey.stravaHistoricalBackfillCompleted) == false
            || UserDefaults.standard.bool(forKey: DefaultsKey.stravaHistoricalBackfillCacheCommitCompleted) == false
            || UserDefaults.standard.integer(forKey: DefaultsKey.stravaCacheIntegrityRepairVersion)
                < currentCacheIntegrityRepairVersion
            || UserDefaults.standard.bool(forKey: DefaultsKey.stravaImportInProgress)
            || hasStravaAthleteChangedSinceLastFullSync()
            || isFullCoverageReconciliationDue(
                lastRunKey: DefaultsKey.stravaLastFullCoverageReconciliationDate,
                interval: stravaFullCoverageReconciliationInterval
            )
    }

    private func markStravaHistoricalBackfillRequired() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.stravaHistoricalBackfillCompleted)
        UserDefaults.standard.set(false, forKey: DefaultsKey.stravaHistoricalBackfillCacheCommitCompleted)
    }

    private func hasStravaAthleteChangedSinceLastFullSync() -> Bool {
        guard let currentAthleteID = StravaManager.shared.storedAthleteID else {
            return false
        }

        return syncStateStore.lastSynchronizedStravaAthleteID != String(currentAthleteID)
    }

    private func confirmedStravaAthleteChange() -> (previous: String, current: String)? {
        guard let currentAthleteID = StravaManager.shared.storedAthleteID else {
            return nil
        }
        let currentAthleteIDString = String(currentAthleteID)

        if let previousAthleteID = effectiveStravaCachedAthleteID {
            guard previousAthleteID != currentAthleteIDString else {
                return nil
            }
            return (previousAthleteID, currentAthleteIDString)
        }

        // The migration release may see legacy direct records without either
        // ownership key. Only an explicit durable OAuth A -> B handoff is safe
        // evidence that those untagged records belong to another account.
        guard let handoff = syncStateStore.stravaAuthorizationHandoff,
              handoff.authorizedAthleteIDs.contains(currentAthleteIDString),
              handoff.cacheOwnerAthleteID != currentAthleteIDString else {
            return nil
        }
        return (handoff.cacheOwnerAthleteID, currentAthleteIDString)
    }

    private var effectiveStravaCachedAthleteID: String? {
        syncCoordinator.pendingStravaCacheAthleteID
            ?? syncStateStore.cachedStravaAthleteID
            // Existing installs used the completed-full-sync value as the cache
            // owner. Keep it as a migration fallback until the next durable save.
            ?? syncStateStore.lastSynchronizedStravaAthleteID
    }

    private func isCurrentStravaSync(generation: UInt64, athleteID: String) -> Bool {
        syncCoordinator.isCurrent(.strava, generation: generation)
            && StravaManager.shared.storedAthleteID.map(String.init) == athleteID
    }

    private func stageStravaCachedAthleteIDCommit(
        _ athleteID: String,
        syncGeneration: UInt64
    ) {
        syncCoordinator.stageStravaCacheOwner(athleteID)
        runAfterPendingCacheSave { [weak self] in
            guard let self,
                  self.syncCoordinator.pendingStravaCacheAthleteID == athleteID,
                  self.isCurrentStravaSync(
                      generation: syncGeneration,
                      athleteID: athleteID
                  ),
                  self.isCachePersistenceHealthy else {
                return
            }

            self.syncStateStore.cachedStravaAthleteID = athleteID
            // Once a current owner is durable, any multi-hop authorization
            // evidence is superseded by that stronger cache ownership record.
            self.syncStateStore.stravaAuthorizationHandoff = nil
            self.syncCoordinator.clearPendingStravaCacheOwner(ifMatching: athleteID)
            PTrackLog.synchronization.debug("PTrack Strava: cache ownership committed for athlete \(athleteID)")
        }
    }

    private func markStravaHistoricalBackfillCompletedAfterCacheSaveIfNeeded(
        didRunHistoricalBackfill: Bool,
        didCompleteAuthoritativeSummary: Bool,
        syncGeneration: UInt64,
        syncAthleteID: String
    ) {
        guard didRunHistoricalBackfill,
              didCompleteAuthoritativeSummary else {
            return
        }

        runAfterPendingCacheSave { [weak self] in
            guard let self,
                  self.isCurrentStravaSync(
                      generation: syncGeneration,
                      athleteID: syncAthleteID
                  ) else {
                return
            }
            self.markStravaHistoricalBackfillCompleted(athleteID: syncAthleteID)
        }
    }

    private func markStravaImportCompletedAfterCacheSaveIfNeeded(
        didCompleteActivitySummary: Bool,
        syncGeneration: UInt64,
        syncAthleteID: String
    ) {
        guard didCompleteActivitySummary else {
            return
        }

        runAfterPendingCacheSave { [weak self] in
            guard let self,
                  self.isCurrentStravaSync(
                      generation: syncGeneration,
                      athleteID: syncAthleteID
                  ) else {
                return
            }
            UserDefaults.standard.set(false, forKey: DefaultsKey.stravaImportInProgress)
        }
    }

    private func markStravaHistoricalBackfillCompleted(athleteID: String) {
        guard isCachePersistenceHealthy else {
            PTrackLog.synchronization.debug("PTrack Strava: kept historical coverage repair pending because the cache manifest is not durably committed")
            return
        }

        UserDefaults.standard.set(true, forKey: DefaultsKey.stravaHistoricalBackfillCompleted)
        UserDefaults.standard.set(true, forKey: DefaultsKey.stravaHistoricalBackfillCacheCommitCompleted)
        UserDefaults.standard.set(
            currentCacheIntegrityRepairVersion,
            forKey: DefaultsKey.stravaCacheIntegrityRepairVersion
        )
        UserDefaults.standard.set(
            Date(),
            forKey: DefaultsKey.stravaLastFullCoverageReconciliationDate
        )
        UserDefaults.standard.set(false, forKey: DefaultsKey.stravaImportInProgress)
        syncStateStore.cachedStravaAthleteID = athleteID
        syncStateStore.lastSynchronizedStravaAthleteID = athleteID
        needsStravaCacheIntegrityRepair = false
        PTrackLog.synchronization.debug("PTrack Strava: historical coverage repair marked completed after cache save")
    }

    private static func debugDateString(_ date: Date?) -> String {
        guard let date else {
            return "nil"
        }

        return ISO8601DateFormatter().string(from: date)
    }

    private func isFullCoverageReconciliationDue(
        lastRunKey: String,
        interval: TimeInterval
    ) -> Bool {
        guard let lastRunDate = UserDefaults.standard.object(forKey: lastRunKey) as? Date else {
            return true
        }

        return Date().timeIntervalSince(lastRunDate) >= interval
    }

    private func loadIncrementalHealthWorkouts() {
        let cachedIDs = knownWorkoutIDs
        let staleWorkouts = workouts.filter(\.needsHealthDataRefresh)
        let staleWorkoutIDs = Set(staleWorkouts.map(\.id))
        let cachedHealthWorkouts = workouts.filter {
            $0.isHealthKitSource
        }
        let shouldBackfillHistory = shouldRunHealthHistoricalBackfill()
        let syncGeneration = syncCoordinator.beginGeneration(.health)
        let queryStartDate = shouldBackfillHistory
            ? nil
            : staleWorkouts.map(\.startDate).min() ?? cachedHealthWorkouts.map(\.startDate).max()
        let excludedIDs = cachedIDs.subtracting(staleWorkoutIDs)
        if !staleWorkouts.isEmpty {
            PTrackLog.synchronization.debug("PTrack HealthKit: refreshing \(staleWorkouts.count) cached workouts for expanded health data")
        }
        if shouldBackfillHistory {
            PTrackLog.synchronization.debug("PTrack HealthKit: historical backfill not completed; requesting full workout history")
        }

        UserDefaults.standard.set(true, forKey: DefaultsKey.healthImportInProgress)
        store.loadTrackedWorkouts(
            after: queryStartDate,
            excludingIDs: excludedIDs,
            onNewDataDetected: { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self,
                          self.syncCoordinator.isCurrent(.health, generation: syncGeneration) else {
                        return
                    }
                    self.setNewDataSyncInProgress(true, for: .health)
                }
            },
            onTrackedWorkouts: { [weak self] trackedWorkouts in
                DispatchQueue.main.async {
                    guard let self,
                          self.syncCoordinator.isCurrent(.health, generation: syncGeneration) else {
                        return
                    }
                    self.upsertTrackedWorkouts(trackedWorkouts)
                }
            },
            completion: { [weak self] loadResult in
                // HealthWorkoutStore emits each workout and then completion in
                // sequence. A single FIFO main queue preserves that ordering so
                // completion cannot commit a backfill marker before the final
                // workout has entered the authoritative model.
                DispatchQueue.main.async {
                    self?.handleLoadResult(
                        loadResult,
                        syncGeneration: syncGeneration,
                        didRunHistoricalBackfill: shouldBackfillHistory
                    )
                }
            }
        )
    }

    private func shouldRunHealthHistoricalBackfill() -> Bool {
        needsHealthCacheIntegrityRepair
            || UserDefaults.standard.bool(forKey: DefaultsKey.healthHistoricalBackfillCompleted) == false
            || UserDefaults.standard.bool(forKey: DefaultsKey.healthHistoricalBackfillCacheCommitCompleted) == false
            || UserDefaults.standard.integer(forKey: DefaultsKey.healthCacheIntegrityRepairVersion)
                < currentCacheIntegrityRepairVersion
            || UserDefaults.standard.bool(forKey: DefaultsKey.healthImportInProgress)
            || isFullCoverageReconciliationDue(
                lastRunKey: DefaultsKey.healthLastFullCoverageReconciliationDate,
                interval: healthFullCoverageReconciliationInterval
            )
    }

    private func upsertTrackedWorkouts(_ incomingWorkouts: [TrackedWorkout]) {
        guard !incomingWorkouts.isEmpty else {
            return
        }

        // Keep the final version of a repeated ID in this publication batch.
        var orderedWorkoutIDs: [String] = []
        var incomingByID: [String: TrackedWorkout] = [:]
        incomingByID.reserveCapacity(incomingWorkouts.count)
        for workout in incomingWorkouts {
            if incomingByID.updateValue(workout, forKey: workout.id) == nil {
                orderedWorkoutIDs.append(workout.id)
            }
        }

        rebuildWorkoutIndexes()
        var acceptedWorkouts: [TrackedWorkout] = []
        acceptedWorkouts.reserveCapacity(orderedWorkoutIDs.count)
        for workoutID in orderedWorkoutIDs {
            guard let workout = incomingByID[workoutID] else {
                continue
            }
            if let conflict = stravaConflict(for: workout) {
                PTrackLog.synchronization.debug(
                    "PTrack Sync: skipped Apple Health workout \(workout.id) because Strava workout \(conflict.id) has precedence"
                )
                continue
            }
            acceptedWorkouts.append(workout)
        }

        guard !acceptedWorkouts.isEmpty else {
            return
        }

        let previousWorkouts = workouts
        let previousPendingWorkouts = pendingWorkouts
        let conflictingHealthWorkoutIDs = Set(
            acceptedWorkouts
                .filter(\.isDirectStravaSource)
                .flatMap { directWorkout in
                    (healthWorkoutsByStartDate[directWorkout.startDate] ?? []).compactMap { candidate in
                        candidate.isSamePhysicalWorkout(as: directWorkout) ? candidate.id : nil
                    }
                }
        )

        if !conflictingHealthWorkoutIDs.isEmpty {
            workouts.removeAll { conflictingHealthWorkoutIDs.contains($0.id) }
            pendingWorkouts.removeAll { conflictingHealthWorkoutIDs.contains($0.id) }
            for removedWorkout in (previousWorkouts + previousPendingWorkouts)
                where conflictingHealthWorkoutIDs.contains(removedWorkout.id) {
                knownWorkoutIDs.remove(removedWorkout.id)
                newWorkoutBadgeStore.markSeen(removedWorkout)
            }
            markCacheDeleted(conflictingHealthWorkoutIDs)
            rebuildWorkoutIndexes()
        }

        var didAppendPendingWorkout = false
        var replacedVisibleWorkoutIDs = Set<String>()
        var needsVisibleWorkoutResort = false
        for workout in acceptedWorkouts {
            if let existingIndex = workoutIndexByID[workout.id] {
                needsVisibleWorkoutResort = needsVisibleWorkoutResort
                    || workouts[existingIndex].startDate != workout.startDate
                workouts[existingIndex] = workout
                knownWorkoutIDs.insert(workout.id)
                replacedVisibleWorkoutIDs.insert(workout.id)
            } else if let pendingIndex = pendingWorkoutIndexByID[workout.id] {
                pendingWorkouts[pendingIndex] = workout
                knownWorkoutIDs.insert(workout.id)
            } else if knownWorkoutIDs.insert(workout.id).inserted {
                pendingWorkoutIndexByID[workout.id] = pendingWorkouts.count
                pendingWorkouts.append(workout)
                newWorkoutBadgeStore.markIfNeeded(workout)
                didAppendPendingWorkout = true
            }
            markCacheDirty(workout.id)
        }

        if needsVisibleWorkoutResort {
            workouts.sort { $0.startDate > $1.startDate }
        }
        rebuildWorkoutIndexes()
        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        updateTotalDistanceText()

        if needsVisibleWorkoutResort
            || (!conflictingHealthWorkoutIDs.isEmpty && !replacedVisibleWorkoutIDs.isEmpty) {
            collectionView.reloadData()
        } else if !conflictingHealthWorkoutIDs.isEmpty {
            let deletedIndexPaths = previousWorkouts.enumerated().compactMap { index, workout in
                conflictingHealthWorkoutIDs.contains(workout.id)
                    ? IndexPath(item: index, section: 0)
                    : nil
            }
            applyWorkoutListDeletions(deletedIndexPaths, previousItemCount: previousWorkouts.count)
        } else if !replacedVisibleWorkoutIDs.isEmpty,
                  collectionView.numberOfItems(inSection: 0) == workouts.count {
            let reloadedIndexPaths = workouts.enumerated().compactMap { index, workout in
                replacedVisibleWorkoutIDs.contains(workout.id)
                    ? IndexPath(item: index, section: 0)
                    : nil
            }
            collectionView.reloadItems(at: reloadedIndexPaths)
        }

        if didAppendPendingWorkout {
            schedulePendingWorkoutFlush()
        }
        scheduleCacheSave()
    }

    private func stravaConflict(for workout: TrackedWorkout) -> TrackedWorkout? {
        guard workout.isHealthKitSource else {
            return nil
        }
        return directStravaWorkoutsByStartDate[workout.startDate]?.first {
            $0.isSamePhysicalWorkout(as: workout)
        }
    }

    private func rebuildWorkoutIndexes() {
        workoutIndexByID.removeAll(keepingCapacity: true)
        workoutIndexByID.reserveCapacity(workouts.count)
        pendingWorkoutIndexByID.removeAll(keepingCapacity: true)
        pendingWorkoutIndexByID.reserveCapacity(pendingWorkouts.count)
        directStravaWorkoutsByStartDate.removeAll(keepingCapacity: true)
        healthWorkoutsByStartDate.removeAll(keepingCapacity: true)

        for (index, workout) in workouts.enumerated() {
            workoutIndexByID[workout.id] = index
            indexWorkoutBySource(workout)
        }
        for (index, workout) in pendingWorkouts.enumerated() {
            pendingWorkoutIndexByID[workout.id] = index
            indexWorkoutBySource(workout)
        }
    }

    private func indexWorkoutBySource(_ workout: TrackedWorkout) {
        if workout.isDirectStravaSource {
            directStravaWorkoutsByStartDate[workout.startDate, default: []].append(workout)
        } else if workout.isHealthKitSource {
            healthWorkoutsByStartDate[workout.startDate, default: []].append(workout)
        }
    }

    @discardableResult
    private func removeCachedAppleHealthWorkoutsConflictingWithStrava() -> Bool {
        let stravaWorkoutsByStartDate = Dictionary(
            grouping: workouts.filter(\.isDirectStravaSource),
            by: \.startDate
        )
        guard !stravaWorkoutsByStartDate.isEmpty else {
            return false
        }

        var removedWorkouts: [TrackedWorkout] = []
        workouts.removeAll { workout in
            guard workout.isHealthKitSource else {
                return false
            }

            let hasStravaConflict = stravaWorkoutsByStartDate[workout.startDate]?.contains {
                $0.isSamePhysicalWorkout(as: workout)
            } == true
            if hasStravaConflict {
                removedWorkouts.append(workout)
                newWorkoutBadgeStore.markSeen(workout)
            }
            return hasStravaConflict
        }

        guard !removedWorkouts.isEmpty else {
            return false
        }

        markCacheDeleted(Set(removedWorkouts.map(\.id)))
        rebuildWorkoutIndexes()

        PTrackLog.synchronization.debug("PTrack Sync: removed \(removedWorkouts.count) cached Apple Health duplicate(s) because Strava has precedence")
        scheduleCacheSave(delay: 0)
        return true
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
        pendingWorkoutIndexByID.removeAll(keepingCapacity: true)

        appendWorkoutsToList(incomingWorkouts)
        scheduleCacheSave()
        restorePersistedRouteBookModeIfNeeded()
        return true
    }

    private func appendWorkoutsToList(_ incomingWorkouts: [TrackedWorkout]) {
        guard !incomingWorkouts.isEmpty else {
            return
        }

        let previousItemCount = workouts.count
        let incomingWorkoutIDs = Set(incomingWorkouts.map(\.id))

        let sortedIncomingWorkouts = incomingWorkouts.sorted { $0.startDate > $1.startDate }
        var mergedWorkouts: [TrackedWorkout] = []
        mergedWorkouts.reserveCapacity(workouts.count + sortedIncomingWorkouts.count)
        var existingIndex = 0
        var incomingIndex = 0
        while existingIndex < workouts.count, incomingIndex < sortedIncomingWorkouts.count {
            if workouts[existingIndex].startDate >= sortedIncomingWorkouts[incomingIndex].startDate {
                mergedWorkouts.append(workouts[existingIndex])
                existingIndex += 1
            } else {
                mergedWorkouts.append(sortedIncomingWorkouts[incomingIndex])
                incomingIndex += 1
            }
        }
        if existingIndex < workouts.count {
            mergedWorkouts.append(contentsOf: workouts[existingIndex...])
        }
        if incomingIndex < sortedIncomingWorkouts.count {
            mergedWorkouts.append(contentsOf: sortedIncomingWorkouts[incomingIndex...])
        }
        workouts = mergedWorkouts
        totalDistanceMeters += incomingWorkouts.reduce(0) { $0 + $1.distanceMeters }
        updateTotalDistanceText()
        rebuildWorkoutIndexes()

        let insertedIndexPaths = workouts.enumerated().compactMap { index, workout -> IndexPath? in
            guard incomingWorkoutIDs.contains(workout.id) else {
                return nil
            }

            return IndexPath(item: index, section: 0)
        }
        applyWorkoutListInsertions(insertedIndexPaths, previousItemCount: previousItemCount)
    }

    private func applyWorkoutListInsertions(
        _ insertedIndexPaths: [IndexPath],
        previousItemCount: Int
    ) {
        guard insertedIndexPaths.count == workouts.count - previousItemCount,
              collectionView.numberOfItems(inSection: 0) == previousItemCount else {
            collectionView.reloadData()
            return
        }

        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates {
                collectionView.insertItems(at: insertedIndexPaths)
            }
        }
    }

    private func applyWorkoutListDeletions(
        _ deletedIndexPaths: [IndexPath],
        previousItemCount: Int
    ) {
        guard !deletedIndexPaths.isEmpty else {
            return
        }

        guard collectionView.numberOfItems(inSection: 0) == previousItemCount else {
            collectionView.reloadData()
            return
        }

        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates {
                collectionView.deleteItems(at: deletedIndexPaths)
            }
        }
    }

    private var isCollectionViewBusy: Bool {
        collectionView.isTracking
            || collectionView.isDragging
            || collectionView.isDecelerating
            || !collectionView.isScrollEnabled
    }

    private func markCacheDirty(_ workoutID: String) {
        guard !workoutID.isEmpty else {
            return
        }

        dirtyCacheWorkoutIDs.insert(workoutID)
        deletedCacheWorkoutIDs.remove(workoutID)
    }

    private func markCacheDeleted(_ workoutIDs: Set<String>) {
        let resolvedWorkoutIDs = Set(workoutIDs.filter { !$0.isEmpty })
        guard !resolvedWorkoutIDs.isEmpty else {
            return
        }

        dirtyCacheWorkoutIDs.subtract(resolvedWorkoutIDs)
        deletedCacheWorkoutIDs.formUnion(resolvedWorkoutIDs)
        // Heatmap snapshots are filtered against the current workout IDs, and
        // their next complete progressive load prunes stale derived files in a
        // single batch. Avoid queuing a stale prune that could race an upsert or
        // authorization rollback which revives the same workout ID.
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
        guard !isCacheLoadInProgress else {
            needsCacheSaveAfterCurrentSave = true
            PTrackLog.synchronization.debug("PTrack Cache: deferred save until cached workouts finish loading")
            return
        }

        if isCacheSaveInProgress {
            needsCacheSaveAfterCurrentSave = true
            return
        }

        let dirtyWorkoutIDs = dirtyCacheWorkoutIDs
        let deletedWorkoutIDs = deletedCacheWorkoutIDs
        guard !dirtyWorkoutIDs.isEmpty || !deletedWorkoutIDs.isEmpty else {
            // A save request can be coalesced while the preceding transaction
            // is active even if it adds no new mutations. The prior success is
            // already durable, so finish any retained summary/widget publish
            // now rather than silently losing that completion edge.
            needsCacheSaveAfterCurrentSave = false
            if isCachePersistenceHealthy {
                if cachedWorkoutSummary != nil {
                    cachedWorkoutSummary = nil
                    updateTotalDistanceText()
                }
                refreshWidgetSnapshot()
            }
            runCacheSaveCompletionHandlersIfReady()
            return
        }

        dirtyCacheWorkoutIDs.subtract(dirtyWorkoutIDs)
        deletedCacheWorkoutIDs.subtract(deletedWorkoutIDs)
        isCacheSaveInProgress = true

        // Pending workouts are already part of the authoritative in-memory model,
        // even when collection-view updates are intentionally delayed while the
        // user is scrolling. Excluding them can consume their dirty IDs without
        // ever writing their files.
        let cachedWorkouts = authoritativeWorkouts
        cacheSaveQueue.async { [cacheStore = self.cacheStore] in
            let persistenceResult = cacheStore.saveIncremental(
                cachedWorkouts,
                dirtyWorkoutIDs: dirtyWorkoutIDs,
                deletedWorkoutIDs: deletedWorkoutIDs
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.isCacheSaveInProgress = false
                self.isCachePersistenceHealthy = persistenceResult.didSucceed
                if persistenceResult == .success {
                    self.consecutiveCacheSaveFailureCount = 0
                } else {
                    if persistenceResult == .transientFailure {
                        self.consecutiveCacheSaveFailureCount += 1
                    } else {
                        self.consecutiveCacheSaveFailureCount = 0
                    }
                    self.restoreUncommittedCacheChanges(
                        dirtyWorkoutIDs: dirtyWorkoutIDs,
                        deletedWorkoutIDs: deletedWorkoutIDs
                    )

                    if persistenceResult == .reconciliationRequired
                        || persistenceResult == .invalidSnapshot {
                        self.didDetectCacheIntegrityIssue = true
                        self.needsHealthCacheIntegrityRepair = true
                        self.needsStravaCacheIntegrityRepair = true
                        self.markHealthHistoricalBackfillRequired()
                        self.markStravaHistoricalBackfillRequired()
                        self.queueDataSourceSynchronization(showsLoadingIndicator: false)
                    }
                }

                let shouldScheduleNextSave = self.needsCacheSaveAfterCurrentSave
                    || !self.dirtyCacheWorkoutIDs.isEmpty
                    || !self.deletedCacheWorkoutIDs.isEmpty
                self.needsCacheSaveAfterCurrentSave = false

                if persistenceResult == .success, shouldScheduleNextSave {
                    self.scheduleCacheSave(delay: 0)
                } else if persistenceResult == .transientFailure,
                          shouldScheduleNextSave,
                          self.consecutiveCacheSaveFailureCount <= self.cacheSaveMaximumAutomaticRetryCount {
                    let retryDelay = self.cacheSaveRetryDelay()
                    PTrackLog.synchronization.debug(
                        "PTrack Cache: transient save failure; retrying in \(Int(retryDelay)) second(s) without discarding pending mutations"
                    )
                    self.scheduleCacheSave(delay: retryDelay)
                } else if persistenceResult == .success {
                    if self.cachedWorkoutSummary != nil {
                        self.cachedWorkoutSummary = nil
                        self.updateTotalDistanceText()
                    }
                    self.refreshWidgetSnapshot()
                    self.runCacheSaveCompletionHandlersIfReady()
                } else {
                    switch persistenceResult {
                    case .transientFailure:
                        PTrackLog.synchronization.debug(
                            "PTrack Cache: stopped automatic save retries after \(self.consecutiveCacheSaveFailureCount) consecutive transient failure(s); pending mutations remain available for the next lifecycle save"
                        )
                    case .reconciliationRequired:
                        PTrackLog.synchronization.debug("PTrack Cache: stopped incremental retries and queued full source reconciliation")
                    case .invalidSnapshot:
                        PTrackLog.synchronization.debug("PTrack Cache: stopped incremental retries because the in-memory snapshot was invalid; queued source reconciliation")
                    case .success:
                        break
                    }
                    self.endBackgroundCacheSaveTask()
                    _ = self.runPendingDataSourceSynchronizationIfNeeded()
                }
            }
        }
    }

    private func runAfterPendingCacheSave(_ handler: @escaping () -> Void) {
        guard isCacheSaveInProgress || !dirtyCacheWorkoutIDs.isEmpty || !deletedCacheWorkoutIDs.isEmpty else {
            handler()
            return
        }

        cacheSaveCompletionHandlers.append(handler)
        scheduleCacheSave(delay: 0)
    }

    private func runCacheSaveCompletionHandlersIfReady() {
        guard !isCacheSaveInProgress,
              dirtyCacheWorkoutIDs.isEmpty,
              deletedCacheWorkoutIDs.isEmpty,
              !cacheSaveCompletionHandlers.isEmpty else {
            return
        }

        let handlers = cacheSaveCompletionHandlers
        cacheSaveCompletionHandlers.removeAll()
        handlers.forEach { $0() }
    }

    private func restoreUncommittedCacheChanges(
        dirtyWorkoutIDs: Set<String>,
        deletedWorkoutIDs: Set<String>
    ) {
        for workoutID in dirtyWorkoutIDs where !deletedCacheWorkoutIDs.contains(workoutID) {
            dirtyCacheWorkoutIDs.insert(workoutID)
        }

        for workoutID in deletedWorkoutIDs {
            // A newer upsert may have revived an ID that this failed batch tried
            // to delete. Preserve the newer dirty intent instead of restoring
            // the stale deletion over it.
            if !dirtyCacheWorkoutIDs.contains(workoutID) {
                deletedCacheWorkoutIDs.insert(workoutID)
            }
        }
    }

    private func cacheSaveRetryDelay() -> TimeInterval {
        let exponent = min(max(consecutiveCacheSaveFailureCount - 1, 0), 5)
        return min(TimeInterval(1 << exponent), cacheSaveRetryMaximumDelay)
    }

    private func refreshWidgetSnapshot() {
        // Never publish while cache loading/reconciliation says the in-memory
        // list may be a partial subset of the last durable snapshot.
        guard !isCacheLoadInProgress,
              !isCacheSaveInProgress,
              dirtyCacheWorkoutIDs.isEmpty,
              deletedCacheWorkoutIDs.isEmpty,
              !needsCacheSaveAfterCurrentSave,
              isCachePersistenceHealthy else {
            PTrackLog.synchronization.debug("PTrack Widget: skipped refresh from an incomplete workout snapshot")
            return
        }
        PTrackWidgetSnapshotStore.refresh(with: authoritativeWorkouts)
    }

    private func prewarmInitialRouteSources() {
        let initialPrewarmCount = min(workouts.count, 24)
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

    private func handleLoadResult(
        _ result: Result<HealthWorkoutStore.LoadResult, Error>,
        syncGeneration: UInt64,
        didRunHistoricalBackfill: Bool
    ) {
        guard syncCoordinator.isCurrent(.health, generation: syncGeneration) else {
            return
        }
        _ = syncCoordinator.finish(.health, generation: syncGeneration)
        updateRouteGridPrefetchingState()
        updateTotalDistanceText()
        let didFlushPendingWorkouts = flushPendingWorkouts()
        switch result {
        case .success(let loadResult):
            PTrackLog.synchronization.debug(
                "PTrack HealthKit: route query completed, loaded routes: \(loadResult.trackedWorkoutCount), route failures: \(loadResult.failedRouteLoadCount)"
            )
            if !loadResult.didCompleteWithoutRouteFailures {
                markHealthHistoricalBackfillRequired()
            }
            markHealthHistoricalBackfillCompletedAfterCacheSaveIfNeeded(
                didRunHistoricalBackfill: didRunHistoricalBackfill,
                didCompleteWithoutRouteFailures: loadResult.didCompleteWithoutRouteFailures,
                syncGeneration: syncGeneration
            )
            markHealthImportCompletedAfterCacheSaveIfNeeded(
                didCompleteWithoutRouteFailures: loadResult.didCompleteWithoutRouteFailures,
                syncGeneration: syncGeneration
            )
            newWorkoutBadgeStore.markInitialSyncCompleted()
        case .failure(let error):
            PTrackLog.synchronization.debug("PTrack HealthKit: route query failed: \(error)")
            markHealthHistoricalBackfillRequired()
        }
        if syncCoordinator.consumeLoadingIndicator(.health) {
            endLoadingOperation()
        } else {
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
        }
        if didFlushPendingWorkouts {
            scheduleCacheSave(delay: 0)
        }
        continueDataSourceSynchronizationAfterHealth()
    }

    private func markHealthHistoricalBackfillCompletedAfterCacheSaveIfNeeded(
        didRunHistoricalBackfill: Bool,
        didCompleteWithoutRouteFailures: Bool,
        syncGeneration: UInt64
    ) {
        guard didRunHistoricalBackfill,
              didCompleteWithoutRouteFailures else {
            return
        }

        runAfterPendingCacheSave { [weak self] in
            guard let self,
                  self.syncCoordinator.isCurrent(.health, generation: syncGeneration) else {
                return
            }
            self.markHealthHistoricalBackfillCompleted()
        }
    }

    private func markHealthImportCompletedAfterCacheSaveIfNeeded(
        didCompleteWithoutRouteFailures: Bool,
        syncGeneration: UInt64
    ) {
        guard didCompleteWithoutRouteFailures else {
            return
        }

        runAfterPendingCacheSave { [weak self] in
            guard let self,
                  self.syncCoordinator.isCurrent(.health, generation: syncGeneration) else {
                return
            }
            UserDefaults.standard.set(false, forKey: DefaultsKey.healthImportInProgress)
        }
    }

    private func markHealthHistoricalBackfillCompleted() {
        guard isCachePersistenceHealthy else {
            PTrackLog.synchronization.debug("PTrack HealthKit: kept historical coverage repair pending because the cache manifest is not durably committed")
            return
        }

        UserDefaults.standard.set(true, forKey: DefaultsKey.healthHistoricalBackfillCompleted)
        UserDefaults.standard.set(true, forKey: DefaultsKey.healthHistoricalBackfillCacheCommitCompleted)
        UserDefaults.standard.set(
            currentCacheIntegrityRepairVersion,
            forKey: DefaultsKey.healthCacheIntegrityRepairVersion
        )
        UserDefaults.standard.set(
            Date(),
            forKey: DefaultsKey.healthLastFullCoverageReconciliationDate
        )
        UserDefaults.standard.set(false, forKey: DefaultsKey.healthImportInProgress)
        needsHealthCacheIntegrityRepair = false
        PTrackLog.synchronization.debug("PTrack HealthKit: historical backfill marked completed after cache save")
    }

    private func markHealthHistoricalBackfillRequired() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.healthHistoricalBackfillCompleted)
        UserDefaults.standard.set(false, forKey: DefaultsKey.healthHistoricalBackfillCacheCommitCompleted)
    }

    private func showHeatmap() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await ProSubscriptionManager.shared.ensureAccessResolved()
            guard ProSubscriptionManager.shared.isProUser else {
                presentProPaywall { [weak self] in
                    self?.showHeatmapUnlocked()
                }
                return
            }

            showHeatmapUnlocked()
        }
    }

    private func showHeatmapUnlocked() {
        flushPendingWorkouts(force: true)
        let heatmapViewController = WorkoutRouteHeatmapViewController(workouts: workouts)
        navigationController?.pushViewController(heatmapViewController, animated: true)
    }

    private func showWorkoutDetail(
        _ workout: TrackedWorkout,
        indexPath: IndexPath,
        cell: WorkoutRouteCell?
    ) {
        let workout = resolvedWorkoutForDetailedUse(workout)
        if newWorkoutBadgeStore.markSeen(workout) {
            cell?.setShowsNewBadge(false)
        }

        let detailViewController = WorkoutRouteDetailViewController(
            workout: workout,
            mergeSourceWorkouts: workouts
        )
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    private func resolvedWorkoutForDetailedUse(_ workout: TrackedWorkout) -> TrackedWorkout {
        guard workout.fullCoordinates == nil,
              !workout.isRouteCollectionSource else {
            return workout
        }

        return cacheStore.loadWorkout(id: workout.id) ?? workout
    }

    private func makeWorkoutContextMenuConfiguration(for workout: TrackedWorkout) -> UIContextMenuConfiguration {
        UIContextMenuConfiguration(identifier: workout.id as NSString, previewProvider: nil) { [weak self] _ in
            guard let self else {
                return UIMenu(children: [])
            }

            let openStartAction = UIAction(
                title: AppLocalization.text(.openStart),
                image: UIImage(systemName: "location")
            ) { [weak self] _ in
                self?.openEndpointInMaps(for: workout, kind: .start)
            }

            let openEndAction = UIAction(
                title: AppLocalization.text(.openEnd),
                image: UIImage(systemName: "mappin.and.ellipse")
            ) { [weak self] _ in
                self?.openEndpointInMaps(for: workout, kind: .end)
            }

            let routeBookAction = UIAction(
                title: AppLocalization.text(.routeBook),
                image: UIImage(systemName: "map")
            ) { [weak self] _ in
                self?.enterRouteBookMode(with: workout)
            }

            return UIMenu(children: [
                openStartAction,
                openEndAction,
                routeBookAction
            ])
        }
    }

    private func openEndpointInMaps(for workout: TrackedWorkout, kind: RouteEndpointKind) {
        guard let coordinate = endpointCoordinate(for: workout, kind: kind) else {
            presentSimpleAlert(
                title: AppLocalization.text(kind == .start ? .startNotFound : .endNotFound),
                message: nil
            )
            return
        }

        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = AppLocalization.text(kind == .start ? .workoutStart : .workoutEnd)

        let launchOptions: [String: Any] = [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(
                mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        ]

        guard mapItem.openInMaps(launchOptions: launchOptions) else {
            presentSimpleAlert(title: AppLocalization.text(.systemMapsNotFound), message: nil)
            return
        }
    }

    private func endpointCoordinate(for workout: TrackedWorkout, kind: RouteEndpointKind) -> CLLocationCoordinate2D? {
        let coordinates = workout.displayCoordinates
        let fallbackCoordinates = workout.coordinates.map(\.coordinate)
        switch kind {
        case .start:
            return coordinates.first ?? fallbackCoordinates.first
        case .end:
            return coordinates.last ?? fallbackCoordinates.last
        }
    }

    private func showRouteCollection() {
        shouldClearRouteImportIndicatorsOnNextHomeAppear = true
        SharedRouteImportInbox.markRoutePromptSeen()
        updateHeaderMoreButtonMode()
        let routeCollectionViewController = RouteCollectionViewController()
        navigationController?.pushViewController(routeCollectionViewController, animated: true)
    }

    private func showMoreSettings() {
        let moreSettingsViewController = MoreSettingsViewController()
        moreSettingsViewController.existingStravaActivityIDsProvider = { [weak self] in
            self?.directStravaActivityIDsInMemory() ?? []
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
        DemoModeStore.markPrimaryDataSourceSelected()
        updateDemoModeEntryVisibility()
        updateFullScreenInsets(force: true)
        switch store.authorizationState {
        case .authorized:
            Toast.show(AppLocalization.text(.healthDataReadAuthorized), in: view)
            return
        case .needsAttention:
            requestHealthAuthorizationIfAvailable()
            return
        case .notDetermined:
            break
        }

        guard !syncCoordinator.isInProgress(.health) else {
            return
        }

        requestHealthAuthorizationAndLoadWorkouts()
    }

    private func requestHealthAuthorizationIfAvailable() {
        guard !syncCoordinator.isInProgress(.health) else {
            return
        }

        store.authorizationRequestAvailability { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                switch result {
                case .success(.canRequest):
                    self.requestHealthAuthorizationAndLoadWorkouts()
                case .success(.settingsRequired):
                    self.store.markAuthorizationVerified()
                    self.loadAuthorizedHealthWorkouts()
                case .failure(let error):
                    self.presentHealthAuthorizationError(error)
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                }
            }
        }
    }

    private func handleEmptyStravaSelection() {
        DemoModeStore.markPrimaryDataSourceSelected()
        updateDemoModeEntryVisibility()
        updateFullScreenInsets(force: true)
        guard !syncCoordinator.isInProgress(.strava) else {
            return
        }

        let excludedActivityIDs = directStravaActivityIDsInMemory()
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
                self.updateDemoModeEntryVisibility()
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

    private func openAppleFitness() {
        guard let applicationURL = URL(string: AppleFitnessDestination.applicationURLString),
              let appStoreURL = URL(string: AppleFitnessDestination.appStoreURLString) else {
            return
        }

        if UIApplication.shared.canOpenURL(applicationURL) {
            UIApplication.shared.open(applicationURL)
        } else {
            UIApplication.shared.open(appStoreURL)
        }
    }

    private func presentSimpleAlert(title: String, message: String?) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .default))
        present(alertController, animated: true)
    }

    private func presentHealthAuthorizationSettingsAlert() {
        let alertController = UIAlertController(
            title: AppLocalization.text(.healthAuthorizationSettingsRequiredTitle),
            message: AppLocalization.text(.healthAuthorizationSettingsRequiredMessage),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(
            title: AppLocalization.text(.cancel),
            style: .cancel
        ))
        alertController.addAction(UIAlertAction(
            title: AppLocalization.text(.openSettings),
            style: .default
        ) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                return
            }
            UIApplication.shared.open(url)
        })
        present(alertController, animated: true)
    }

    private func presentHealthAuthorizationError(_ error: Error) {
        presentSimpleAlert(
            title: AppLocalization.text(.healthAuthorizationFailed),
            message: localizedHealthErrorMessage(for: error)
        )
    }

    private func localizedHealthErrorMessage(for error: Error) -> String {
        guard let storeError = error as? HealthWorkoutStoreError else {
            return error.localizedDescription
        }

        switch storeError {
        case .healthDataUnavailable:
            return AppLocalization.text(.healthDataUnavailable)
        case .authorizationDenied:
            return AppLocalization.text(.healthAuthorizationDenied)
        case .authorizationTemporarilyUnavailable:
            return AppLocalization.text(.healthAuthorizationTemporarilyUnavailable)
        }
    }

    private func restorePersistedRouteBookModeIfNeeded() {
        guard !isRouteBookModeActive,
              let workout = persistedRouteBookWorkout() else {
            return
        }

        enterRouteBookMode(with: workout, persists: false)
    }

    private func persistedRouteBookWorkout() -> TrackedWorkout? {
        guard let activeSession = RouteBookMode.activeSession else {
            return nil
        }

        if let workout = persistedRouteBookWorkout(
            routeID: activeSession.routeID,
            preferredSource: activeSession.source
        ) {
            return workout
        }

        if let workout = workouts.first(where: { $0.id == activeSession.routeID }) {
            return workout
        }

        if let snapshot = RouteBookMode.activeWorkoutSnapshot {
            return snapshot
        }

        return nil
    }

    private func persistedRouteBookWorkout(
        routeID: String,
        preferredSource: RouteBookMode.StorageSource?
    ) -> TrackedWorkout? {
        switch preferredSource {
        case .routeCollection:
            if let workout = routeCollectionStore.loadRoute(id: routeID) {
                return workout
            }
            return cacheStore.loadWorkout(id: routeID)
        case .workoutCache:
            if let workout = cacheStore.loadWorkout(id: routeID) {
                return workout
            }
            return routeCollectionStore.loadRoute(id: routeID)
        case nil:
            if let workout = cacheStore.loadWorkout(id: routeID) {
                return workout
            }
            return routeCollectionStore.loadRoute(id: routeID)
        }
    }

    private func enterRouteBookMode(with workout: TrackedWorkout, persists: Bool = true) {
        let workout = resolvedWorkoutForDetailedUse(workout)
        guard workout.routeDetailCoordinates.count > 1 else {
            presentSimpleAlert(title: AppLocalization.text(.routeBook), message: AppLocalization.text(.unknownLocation))
            return
        }

        if persists {
            RouteBookMode.activate(workout: workout)
        }

        routeBookWorkout = workout
        isRouteBookModeActive = true
        applyRouteBookPanelDetent(.minimum, animated: false)
        updateRouteBookPanelText()
        applyRouteBookInterfaceState()

        startRouteBookPreparation(for: workout)
        requestRouteBookLocationAuthorizationIfNeeded()
        updateRouteBookLocateButtonState()
        updateHeaderReadAuthorizationState()
    }

    private func updateRouteBookPanelText() {
        guard let routeBookWorkout else {
            routeBookPanelDistanceLabel.text = nil
            routeBookPanelDistanceLabel.isHidden = true
            routeBookReplayCoordinates = []
            routeBookReplayDistances = []
            routeBookReplayAltitudes = []
            routeBookReplaySegmentStartIndices = []
            routeBookViewportGeometry = nil
            routeBookLastFocusedDistance = nil
            routeBookMatchingGeometry = nil
            routeBookMatchCache = nil
            removeRouteBookReplayAnnotation()
            routeBookReplayRulerView.configure(
                totalDistanceText: routeBookReplayTotalDistanceText(totalMeters: 0),
                totalDistanceMeters: 0,
                elevationSamples: []
            )
            routeBookReplayRulerView.setProgress(0)
            routeBookReplayRulerView.setIndicatorVisible(false)
            return
        }

        routeBookPanelDistanceLabel.text = routeBookPanelDistanceText(for: routeBookWorkout)
        routeBookPanelDistanceLabel.isHidden = routeBookPanelDistanceLabel.text == nil
    }

    private func routeBookPanelDistanceText(for workout: TrackedWorkout) -> String? {
        let distanceText: String
        if workout.distanceMeters >= 1000 {
            distanceText = String(format: "%.1f km", workout.distanceMeters / 1000)
        } else if workout.distanceMeters > 0 {
            distanceText = AppLocalization.format(.distanceMetersFormat, workout.distanceMeters)
        } else {
            return nil
        }

        guard let elevationGainText = routeBookPanelElevationGainText(for: workout) else {
            return distanceText
        }

        return "\(distanceText) / \(elevationGainText)"
    }

    private func routeBookPanelElevationGainText(for workout: TrackedWorkout) -> String? {
        guard let elevationGainMeters = workout.displayElevationGainMeters,
              elevationGainMeters.isFinite,
              elevationGainMeters > 0 else {
            return nil
        }

        let roundedElevationGain = elevationGainMeters.rounded()
        if AppLanguageStore.shared.language == .chinese {
            return "爬升\(Int(roundedElevationGain)) 米"
        }

        return AppLocalization.format(.elevationGainFormat, roundedElevationGain)
    }

    private func startRouteBookPreparation(for workout: TrackedWorkout) {
        routeBookPreparationCancellationToken?.cancel()
        routeBookViewportUpdateWorkItem?.cancel()
        routeBookViewportUpdateWorkItem = nil
        let cancellationToken = RouteSlopePreparationCancellationToken()
        routeBookPreparationCancellationToken = cancellationToken
        let preparationID = UUID()
        routeBookPreparationID = preparationID
        routeBookReplayCoordinates = []
        routeBookReplayDistances = []
        routeBookReplayAltitudes = []
        routeBookReplaySegmentStartIndices = []
        routeBookViewportGeometry = nil
        routeBookLastFocusedDistance = nil
        routeBookMatchingGeometry = nil
        routeBookMatchCache = nil
        removeRouteBookReplayAnnotation()
        if !routeBookDisplayPolylines.isEmpty {
            routeBookMapView.removeOverlays(routeBookDisplayPolylines)
        }
        if !routeBookSlopePolylines.isEmpty {
            routeBookMapView.removeOverlays(routeBookSlopePolylines)
        }
        if !routeBookSlopeDirectionPolylines.isEmpty {
            routeBookMapView.removeOverlays(routeBookSlopeDirectionPolylines)
        }
        routeBookBoundingMapRect = nil
        routeBookDisplayPolylines = []
        routeBookDirectionIndicatorPolylines = []
        routeBookDirectionIndicatorBudgets = [:]
        routeBookSlopePolylines = []
        routeBookSlopeGradients = [:]
        routeBookSlopeDirectionPolylines = []
        routeBookSlopeDirectionPolylineIdentifiers = []
        areRouteBookSlopeDirectionOverlaysSuspendedForMapChange = false
        isRouteBookSlopeVisible = false
        updateRouteBookSlopeVisibilityButtonAppearance()
        isRouteBookMapRegionChanging = false
        removeRouteBookEndpointAnnotations()
        routeBookReplayRulerView.configure(
            totalDistanceText: routeBookReplayTotalDistanceText(
                totalMeters: workout.distanceMeters
            ),
            totalDistanceMeters: workout.distanceMeters,
            elevationSamples: []
        )
        routeBookReplayRulerView.setProgress(0)
        routeBookReplayRulerView.setIndicatorVisible(false)

        let maximumElevationSampleCount = routeBookMaximumElevationSampleCount
        let maximumSlopeRenderingCoordinateCount = routeBookMaximumSlopeRenderingCoordinateCount
        let maximumSlopeSegmentCount = routeBookMaximumSlopeSegmentCount
        let slopeGeometrySimplificationToleranceMeters =
            routeBookSlopeGeometrySimplificationToleranceMeters
        routeBookPreparationQueue.async { [weak self] in
            let preparedRouteBook = Self.prepareRouteBook(
                for: workout,
                maximumElevationSampleCount: maximumElevationSampleCount,
                maximumSlopeRenderingCoordinateCount: maximumSlopeRenderingCoordinateCount,
                maximumSlopeSegmentCount: maximumSlopeSegmentCount,
                slopeGeometrySimplificationToleranceMeters:
                    slopeGeometrySimplificationToleranceMeters,
                cancellationToken: cancellationToken
            )
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isRouteBookModeActive,
                      self.routeBookPreparationID == preparationID,
                      self.routeBookPreparationCancellationToken === cancellationToken,
                      self.routeBookWorkout?.id == workout.id else {
                    return
                }
                self.routeBookPreparationID = nil
                self.routeBookPreparationCancellationToken = nil
                guard let preparedRouteBook else {
                    return
                }
                self.applyPreparedRouteBook(preparedRouteBook, for: workout)
            }
        }
    }

    private static func prepareRouteBook(
        for workout: TrackedWorkout,
        maximumElevationSampleCount: Int,
        maximumSlopeRenderingCoordinateCount: Int,
        maximumSlopeSegmentCount: Int,
        slopeGeometrySimplificationToleranceMeters: CLLocationDistance,
        cancellationToken: RouteSlopePreparationCancellationToken
    ) -> PreparedRouteBook? {
        guard !cancellationToken.isCancelled else {
            return nil
        }
        let routeCoordinates = workout.routeDetailCoordinates
        let segmentStartIndices = workout.routeDetailSegmentStartIndices
        guard routeCoordinates.count > 1 else {
            return nil
        }
        var sourceCoordinates: [CLLocationCoordinate2D] = []
        var replayAltitudes: [Double?] = []
        var slopeAltitudes: [Double?] = []
        var sourceDistances: [CLLocationDistance?] = []
        var sourceGradeRatios: [Double?] = []
        sourceCoordinates.reserveCapacity(routeCoordinates.count)
        replayAltitudes.reserveCapacity(routeCoordinates.count)
        slopeAltitudes.reserveCapacity(routeCoordinates.count)
        sourceDistances.reserveCapacity(routeCoordinates.count)
        sourceGradeRatios.reserveCapacity(routeCoordinates.count)
        for (index, routeCoordinate) in routeCoordinates.enumerated() {
            if index.isMultiple(of: 256), cancellationToken.isCancelled {
                return nil
            }
            sourceCoordinates.append(routeCoordinate.coordinate)
            replayAltitudes.append(routeCoordinate.altitudeMeters)
            sourceDistances.append(routeCoordinate.sourceDistanceMeters)
            sourceGradeRatios.append(routeCoordinate.gradeRatio)
            if let verticalAccuracy = routeCoordinate.verticalAccuracyMeters,
               (!verticalAccuracy.isFinite
                || verticalAccuracy < 0
                || verticalAccuracy > 15) {
                slopeAltitudes.append(nil)
            } else {
                slopeAltitudes.append(routeCoordinate.altitudeMeters)
            }
        }
        guard let coordinates = CoordinateTransformer.displayCoordinates(
            for: sourceCoordinates,
            isCancelled: { cancellationToken.isCancelled }
        ),
        let replayDistances = routeBookCumulativeDistances(
            for: coordinates,
            segmentStartIndices: segmentStartIndices,
            isCancelled: { cancellationToken.isCancelled }
        ),
        let elevationSamples = routeBookElevationSamples(
            distances: replayDistances,
            altitudes: replayAltitudes,
            seriesBreakIndices: segmentStartIndices,
            maximumCount: maximumElevationSampleCount,
            isCancelled: { cancellationToken.isCancelled }
        ),
        let slopeSegments = prepareRouteBookSlopeSegments(
            coordinates: coordinates,
            cumulativeDistances: replayDistances,
            altitudes: slopeAltitudes,
            sourceDistances: sourceDistances,
            sourceGradeRatios: sourceGradeRatios,
            segmentStartIndices: segmentStartIndices,
            maximumRenderingCoordinateCount: maximumSlopeRenderingCoordinateCount,
            maximumSegmentCount: maximumSlopeSegmentCount,
            simplificationToleranceMeters: slopeGeometrySimplificationToleranceMeters,
            cancellationToken: cancellationToken
        ) else {
            return nil
        }
        guard let viewportGeometry = RouteViewportDistanceResolver.prepareGeometry(
            coordinates: coordinates,
            cumulativeDistances: replayDistances,
            segmentStartIndices: segmentStartIndices,
            isCancelled: { cancellationToken.isCancelled }
        ),
        let displayGeometry = RouteViewportDistanceResolver.prepareGeometry(
            coordinates: coordinates,
            cumulativeDistances: replayDistances,
            segmentStartIndices: segmentStartIndices,
            maximumCount: 12_000,
            toleranceMeters: 4,
            allowsSinglePointRepresentatives: false,
            isCancelled: { cancellationToken.isCancelled }
        ),
        let matchingGeometry = prepareRouteBookMatchingGeometry(
            coordinates: coordinates,
            cumulativeDistances: replayDistances,
            segmentStartIndices: segmentStartIndices,
            maximumCount: 4_096,
            isCancelled: { cancellationToken.isCancelled }
        ),
        let boundingMapRect = RouteViewportDistanceResolver.boundingMapRect(
            for: coordinates,
            isCancelled: { cancellationToken.isCancelled }
        ) else {
            return nil
        }
        return PreparedRouteBook(
            coordinates: coordinates,
            boundingMapRect: boundingMapRect,
            replayDistances: replayDistances,
            replayAltitudes: replayAltitudes,
            segmentStartIndices: segmentStartIndices,
            elevationSamples: elevationSamples,
            slopeSegments: slopeSegments,
            viewportGeometry: viewportGeometry,
            displayGeometry: displayGeometry,
            matchingGeometry: matchingGeometry
        )
    }

    private nonisolated static func prepareRouteBookSlopeSegments(
        coordinates: [CLLocationCoordinate2D],
        cumulativeDistances: [CLLocationDistance],
        altitudes: [Double?],
        sourceDistances: [CLLocationDistance?],
        sourceGradeRatios: [Double?],
        segmentStartIndices: Set<Int>,
        maximumRenderingCoordinateCount: Int,
        maximumSegmentCount: Int,
        simplificationToleranceMeters: CLLocationDistance,
        cancellationToken: RouteSlopePreparationCancellationToken
    ) -> [PreparedRouteBookSlopeSegment]? {
        guard coordinates.count == cumulativeDistances.count,
              coordinates.count == altitudes.count,
              coordinates.count == sourceDistances.count,
              coordinates.count == sourceGradeRatios.count,
              maximumRenderingCoordinateCount > 1 else {
            return []
        }

        let segmentStarts = segmentStartIndices
            .filter { $0 > 0 && $0 < coordinates.count }
            .sorted()
        let boundaries = [0] + segmentStarts + [coordinates.count]
        let allSegmentRanges = zip(boundaries, boundaries.dropFirst())
            .enumerated()
            .compactMap { segmentIndex, bounds -> (
                segmentIndex: Int,
                lowerBound: Int,
                upperBound: Int
            )? in
                bounds.1 - bounds.0 > 1
                    ? (segmentIndex, bounds.0, bounds.1)
                    : nil
            }
        let segmentLimit = min(
            max(maximumSegmentCount, 1),
            max(maximumRenderingCoordinateCount / 2, 1)
        )
        var candidates: [(
            segmentIndex: Int,
            lowerBound: Int,
            upperBound: Int,
            totalDistance: CLLocationDistance,
            gradient: RouteSlopeGradient
        )] = []
        candidates.reserveCapacity(min(allSegmentRanges.count, segmentLimit * 2))
        for segmentRange in allSegmentRanges {
            if cancellationToken.isCancelled {
                return nil
            }
            let baseDistance = cumulativeDistances[segmentRange.lowerBound]
            let segmentDistances = cumulativeDistances[
                segmentRange.lowerBound..<segmentRange.upperBound
            ].map { $0 - baseDistance }
            guard let totalDistance = segmentDistances.last,
                  totalDistance >= 20,
                  let gradient = RouteSlopeGradient.make(
                      distances: segmentDistances,
                      altitudes: Array(
                          altitudes[segmentRange.lowerBound..<segmentRange.upperBound]
                      ),
                      sourceGradeRatios: Array(
                          sourceGradeRatios[
                              segmentRange.lowerBound..<segmentRange.upperBound
                          ]
                      ),
                      sourceCumulativeDistances: Array(
                          sourceDistances[
                              segmentRange.lowerBound..<segmentRange.upperBound
                          ]
                      ),
                      isCancelled: { cancellationToken.isCancelled }
                  ) else {
                continue
            }
            candidates.append((
                segmentIndex: segmentRange.segmentIndex,
                lowerBound: segmentRange.lowerBound,
                upperBound: segmentRange.upperBound,
                totalDistance: totalDistance,
                gradient: gradient
            ))
        }

        let selectedCandidates = candidates
            .sorted { lhs, rhs in
                if lhs.totalDistance != rhs.totalDistance {
                    return lhs.totalDistance > rhs.totalDistance
                }
                return lhs.lowerBound < rhs.lowerBound
            }
            .prefix(segmentLimit)
            .sorted { $0.lowerBound < $1.lowerBound }
        let totalPointCount = selectedCandidates.reduce(0) {
            $0 + ($1.upperBound - $1.lowerBound)
        }
        guard totalPointCount > 1 else {
            return []
        }

        var result: [PreparedRouteBookSlopeSegment] = []
        result.reserveCapacity(selectedCandidates.count)
        var remainingRenderingBudget = maximumRenderingCoordinateCount
        var remainingPointCount = totalPointCount
        for (segmentOffset, segmentRange) in selectedCandidates.enumerated() {
            if cancellationToken.isCancelled {
                return nil
            }
            let pointCount = segmentRange.upperBound - segmentRange.lowerBound
            let minimumRemainingCount = max(
                (selectedCandidates.count - segmentOffset - 1) * 2,
                0
            )
            let proportionalCount = Int(round(
                Double(remainingRenderingBudget) * Double(pointCount)
                    / Double(max(remainingPointCount, 1))
            ))
            let segmentMaximumCount = min(
                pointCount,
                max(
                    2,
                    min(
                        proportionalCount,
                        remainingRenderingBudget - minimumRemainingCount
                    )
                )
            )
            remainingRenderingBudget -= segmentMaximumCount
            remainingPointCount -= pointCount

            let baseDistance = cumulativeDistances[segmentRange.lowerBound]
            let segmentDistances = cumulativeDistances[
                segmentRange.lowerBound..<segmentRange.upperBound
            ].map { $0 - baseDistance }
            guard let geometry = RouteSlopeGeometryPreparer.prepare(
                coordinates: Array(
                    coordinates[segmentRange.lowerBound..<segmentRange.upperBound]
                ),
                cumulativeDistances: segmentDistances,
                toleranceMeters: simplificationToleranceMeters,
                maximumCount: segmentMaximumCount,
                cancellationToken: cancellationToken
            ) else {
                if cancellationToken.isCancelled {
                    return nil
                }
                continue
            }
            result.append(PreparedRouteBookSlopeSegment(
                segmentIndex: segmentRange.segmentIndex,
                coordinates: geometry.coordinates,
                sourceLocations: geometry.sourceLocations,
                gradient: segmentRange.gradient,
                totalDistance: segmentRange.totalDistance
            ))
        }
        return cancellationToken.isCancelled ? nil : result
    }

    private nonisolated static func prepareRouteBookMatchingGeometry(
        coordinates: [CLLocationCoordinate2D],
        cumulativeDistances: [CLLocationDistance],
        segmentStartIndices: Set<Int>,
        maximumCount: Int,
        isCancelled: @Sendable () -> Bool
    ) -> RouteBookMatchingGeometry? {
        guard coordinates.count == cumulativeDistances.count,
              coordinates.count > 1,
              maximumCount > 1,
              !isCancelled() else {
            return nil
        }

        let starts = segmentStartIndices
            .filter { $0 > 0 && $0 < coordinates.count }
            .sorted()
        let boundaries = [0] + starts + [coordinates.count]
        let allRanges = zip(boundaries, boundaries.dropFirst()).compactMap {
            lowerBound, upperBound -> Range<Int>? in
            lowerBound < upperBound ? lowerBound..<upperBound : nil
        }
        let maximumSegmentCount = max(maximumCount / 2, 1)
        let ranges: [Range<Int>]
        if allRanges.count <= maximumSegmentCount {
            ranges = allRanges
        } else {
            ranges = allRanges
                .sorted { lhs, rhs in
                    if lhs.count != rhs.count {
                        return lhs.count > rhs.count
                    }
                    return lhs.lowerBound < rhs.lowerBound
                }
                .prefix(maximumSegmentCount)
                .sorted { $0.lowerBound < $1.lowerBound }
        }

        var minimumCountSuffix = Array(repeating: 0, count: ranges.count + 1)
        for index in ranges.indices.reversed() {
            minimumCountSuffix[index] = minimumCountSuffix[index + 1]
                + (ranges[index].count > 1 ? 2 : 1)
        }
        var remainingBudget = maximumCount
        var remainingSourceCount = ranges.reduce(0) { $0 + $1.count }
        var sampledCoordinates: [CLLocationCoordinate2D] = []
        var sampledDistances: [CLLocationDistance] = []
        var sampledSourceIndices: [Int] = []
        var sampledSegmentStarts = Set<Int>()
        sampledCoordinates.reserveCapacity(min(maximumCount, coordinates.count))
        sampledDistances.reserveCapacity(min(maximumCount, coordinates.count))
        sampledSourceIndices.reserveCapacity(min(maximumCount, coordinates.count))

        for (segmentOffset, range) in ranges.enumerated() {
            if isCancelled() {
                return nil
            }
            if segmentOffset > 0, !sampledCoordinates.isEmpty {
                sampledSegmentStarts.insert(sampledCoordinates.count)
            }
            let minimumCount = range.count > 1 ? 2 : 1
            let remainingMinimumCount = minimumCountSuffix[segmentOffset + 1]
            let proportionalCount = Int(round(
                Double(remainingBudget) * Double(range.count)
                    / Double(max(remainingSourceCount, 1))
            ))
            let sampleCount = min(
                range.count,
                max(
                    minimumCount,
                    min(proportionalCount, remainingBudget - remainingMinimumCount)
                )
            )
            remainingBudget -= sampleCount
            remainingSourceCount -= range.count

            let indices: [Int]
            if sampleCount >= range.count {
                indices = Array(range)
            } else if sampleCount == 1 {
                indices = [range.lowerBound]
            } else {
                indices = (0..<sampleCount).map { position in
                    range.lowerBound + Int(round(
                        Double(range.count - 1) * Double(position)
                            / Double(sampleCount - 1)
                    ))
                }
            }
            for index in indices {
                sampledCoordinates.append(coordinates[index])
                sampledDistances.append(cumulativeDistances[index])
                sampledSourceIndices.append(index)
            }
        }

        guard sampledCoordinates.count == sampledDistances.count,
              sampledCoordinates.count == sampledSourceIndices.count,
              sampledCoordinates.count > 1,
              sampledCoordinates.count <= maximumCount,
              !isCancelled() else {
            return nil
        }
        return RouteBookMatchingGeometry(
            coordinates: sampledCoordinates,
            cumulativeDistances: sampledDistances,
            segmentStartIndices: sampledSegmentStarts,
            sourceIndices: sampledSourceIndices
        )
    }

    private func applyPreparedRouteBook(
        _ preparedRouteBook: PreparedRouteBook,
        for workout: TrackedWorkout
    ) {
        let replayDistance = preparedRouteBook.replayDistances.last
            ?? workout.distanceMeters
        routeBookReplayRulerView.configure(
            totalDistanceText: routeBookReplayTotalDistanceText(totalMeters: replayDistance),
            totalDistanceMeters: replayDistance,
            elevationSamples: preparedRouteBook.elevationSamples,
            segmentBoundaryDistanceRanges: RouteViewportDistanceResolver
                .segmentBoundaryDistanceRanges(
                    cumulativeDistances: preparedRouteBook.replayDistances,
                    segmentStartIndices: preparedRouteBook.segmentStartIndices
                )
        )
        routeBookReplayRulerView.setProgress(0)
        routeBookReplayRulerView.setIndicatorVisible(false)
        routeBookReplayCoordinates = preparedRouteBook.coordinates
        routeBookReplayDistances = preparedRouteBook.replayDistances
        routeBookReplayAltitudes = preparedRouteBook.replayAltitudes
        routeBookReplaySegmentStartIndices = preparedRouteBook.segmentStartIndices
        routeBookViewportGeometry = preparedRouteBook.viewportGeometry
        routeBookMatchingGeometry = preparedRouteBook.matchingGeometry
        routeBookMatchCache = nil
        removeRouteBookReplayAnnotation()
        configureRouteBookSlopeOverlays(
            preparedRouteBook.slopeSegments,
            displayGeometry: preparedRouteBook.displayGeometry
        )
        drawRouteBookRoute(preparedRouteBook, for: workout)
        updateRouteBookReplayRulerVisibleRange()
        if selectedRouteBookPanelDetent == .medium {
            updateRouteBookReplayProgressForCurrentLocation()
        }
    }

    private func updateRouteBookReplayRulerVisibleRange() {
        guard selectedRouteBookPanelDetent == .medium,
              routeBookReplayCoordinates.count == routeBookReplayDistances.count,
              let totalDistance = routeBookReplayDistances.last,
              totalDistance > 0,
              let routeBookViewportGeometry else {
            return
        }

        let preferredDistance: CLLocationDistance? = routeBookReplayAnnotation == nil
            ? routeBookLastFocusedDistance
            : CLLocationDistance(routeBookReplayRulerView.progress) * totalDistance
        let visibleContainerBounds = routeBookMapContainerView.bounds.inset(
            by: UIEdgeInsets(
                top: 150,
                left: 0,
                bottom: routeBookPanelContentHeight(for: selectedRouteBookPanelDetent),
                right: 0
            )
        )
        let visibleMapBounds = routeBookMapContainerView.convert(
            visibleContainerBounds,
            to: routeBookMapView
        )
        guard let focusedRange = RouteViewportDistanceResolver.focusedVisibleRange(
            coordinates: routeBookViewportGeometry.coordinates,
            mapPoints: routeBookViewportGeometry.mapPoints,
            cumulativeDistances: routeBookViewportGeometry.cumulativeDistances,
            mapView: routeBookMapView,
            visibleBounds: visibleMapBounds,
            segmentStartIndices: routeBookViewportGeometry.segmentStartIndices,
            segmentDistanceRanges: routeBookViewportGeometry.segmentDistanceRanges,
            segmentBoundingMapRects: routeBookViewportGeometry.segmentBoundingMapRects,
            preferredDistance: preferredDistance
        ) else {
            return
        }

        let visibleRange = focusedRange.visibleDistanceRange
        if let preferredDistance,
           visibleRange.contains(preferredDistance) {
            routeBookLastFocusedDistance = preferredDistance
        } else {
            routeBookLastFocusedDistance = (
                visibleRange.lowerBound + visibleRange.upperBound
            ) / 2
        }
        let contextRange = focusedRange.contextDistanceRange
        let span = visibleRange.upperBound - visibleRange.lowerBound
        let contextSpan = contextRange.upperBound - contextRange.lowerBound
        if span >= contextSpan * 0.9 {
            routeBookReplayRulerView.setVisibleDistanceRange(contextRange)
            return
        }

        let contextDistance = max(span * 0.04, min(contextSpan * 0.001, 20))
        let lowerBound = max(
            visibleRange.lowerBound - contextDistance,
            contextRange.lowerBound
        )
        let upperBound = min(
            visibleRange.upperBound + contextDistance,
            contextRange.upperBound
        )
        routeBookReplayRulerView.setVisibleDistanceRange(lowerBound...upperBound)
    }

    private func handleRouteBookMapRegionChangeForReplayRuler() {
        routeBookViewportUpdateWorkItem?.cancel()
        guard isRouteBookModeActive else {
            routeBookViewportUpdateWorkItem = nil
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRouteBookModeActive else {
                return
            }
            self.routeBookViewportUpdateWorkItem = nil
            self.isRouteBookMapRegionChanging = false
            self.restoreRouteBookDirectionIndicatorsAfterMapChange()
            if self.selectedRouteBookPanelDetent == .medium {
                self.updateRouteBookReplayRulerVisibleRange()
            }
        }
        routeBookViewportUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.08,
            execute: workItem
        )
    }

    private func restoreRouteBookDirectionIndicatorsAfterMapChange() {
        if !isRouteBookSlopeVisible {
            for routePolyline in routeBookDirectionIndicatorPolylines {
                guard let renderer = routeBookMapView.renderer(for: routePolyline)
                        as? RouteDirectionPolylineRenderer else {
                    continue
                }
                let budget = routeBookDirectionIndicatorBudgets[
                    ObjectIdentifier(routePolyline)
                ] ?? 0
                guard renderer.maximumIndicatorCount != budget else {
                    continue
                }
                renderer.maximumIndicatorCount = budget
                renderer.setNeedsDisplay()
            }
        }
        areRouteBookSlopeDirectionOverlaysSuspendedForMapChange = false
        if isRouteBookSlopeVisible {
            addRouteBookSlopeDirectionOverlayIfNeeded()
        }
    }

    private func handleRouteBookMapRegionWillChange() {
        isRouteBookMapRegionChanging = true
        routeBookViewportUpdateWorkItem?.cancel()
        routeBookViewportUpdateWorkItem = nil
        if isRouteBookSlopeVisible {
            let visibleOverlayIdentifiers = Set(
                routeBookMapView.overlays.map { ObjectIdentifier($0 as AnyObject) }
            )
            let visibleDirectionPolylines = routeBookSlopeDirectionPolylines.filter {
                visibleOverlayIdentifiers.contains(ObjectIdentifier($0))
            }
            if !visibleDirectionPolylines.isEmpty {
                areRouteBookSlopeDirectionOverlaysSuspendedForMapChange = true
                routeBookMapView.removeOverlays(visibleDirectionPolylines)
            }
            return
        }
        for routePolyline in routeBookDirectionIndicatorPolylines {
            guard let renderer = routeBookMapView.renderer(for: routePolyline)
                    as? RouteDirectionPolylineRenderer,
                  renderer.maximumIndicatorCount > 0 else {
                continue
            }
            renderer.maximumIndicatorCount = 0
        }
    }

    private func routeBookReplayTotalDistanceText(totalMeters: CLLocationDistance) -> String {
        let kilometers = max(totalMeters, 0) / 1000
        if kilometers >= 100 {
            return String(format: "%.0fkm", kilometers)
        }
        if kilometers >= 10 {
            return String(format: "%.1fkm", kilometers)
        }
        return String(format: "%.2fkm", kilometers)
    }

    private nonisolated static func routeBookCumulativeDistances(
        for coordinates: [CLLocationCoordinate2D],
        segmentStartIndices: Set<Int>,
        isCancelled: @Sendable () -> Bool
    ) -> [CLLocationDistance]? {
        guard !isCancelled() else {
            return nil
        }
        guard let firstCoordinate = coordinates.first else {
            return []
        }

        var distances: [CLLocationDistance] = [0]
        distances.reserveCapacity(coordinates.count)

        var totalDistance: CLLocationDistance = 0
        var previousLocation = CLLocation(latitude: firstCoordinate.latitude, longitude: firstCoordinate.longitude)

        for (offset, coordinate) in coordinates.dropFirst().enumerated() {
            if offset.isMultiple(of: 256), isCancelled() {
                return nil
            }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if segmentStartIndices.contains(offset + 1) {
                totalDistance += RouteViewportDistanceResolver.segmentBoundaryDistance
            } else {
                totalDistance += location.distance(from: previousLocation)
            }
            distances.append(totalDistance)
            previousLocation = location
        }

        return isCancelled() ? nil : distances
    }

    private nonisolated static func routeBookElevationSamples(
        distances: [CLLocationDistance],
        altitudes: [Double?],
        seriesBreakIndices: Set<Int>,
        maximumCount: Int,
        isCancelled: @Sendable () -> Bool
    ) -> [RouteElevationSample]? {
        guard distances.count == altitudes.count else {
            return []
        }

        var samples: [RouteElevationSample] = []
        samples.reserveCapacity(min(altitudes.count, maximumCount))
        var seriesIdentifier = 0
        var previousValidIndex: Int?
        for index in altitudes.indices {
            if index.isMultiple(of: 256), isCancelled() {
                return nil
            }
            guard let altitude = altitudes[index], altitude.isFinite else {
                continue
            }
            if let previousValidIndex,
               index != previousValidIndex + 1 || seriesBreakIndices.contains(index) {
                seriesIdentifier += 1
            }
            samples.append(RouteElevationSample(
                distanceMeters: distances[index],
                altitudeMeters: altitude,
                seriesIdentifier: seriesIdentifier
            ))
            previousValidIndex = index
        }

        return RouteElevationSampler.downsample(
            samples,
            maximumCount: maximumCount,
            isCancelled: isCancelled
        )
    }

    private func updateRouteBookReplayProgressForCurrentLocation() {
        guard let match = routeBookRouteMatchForCurrentLocation(),
              let replayState = routeBookReplayState(for: match) else {
            routeBookReplayRulerView.setIndicatorVisible(false)
            removeRouteBookReplayAnnotation()
            return
        }

        routeBookReplayRulerView.setIndicatorVisible(true)
        routeBookReplayRulerView.setProgress(match.progress)
        routeBookLastFocusedDistance = match.routeDistance
        updateRouteBookReplayAnnotation(with: replayState)
    }

    private func routeBookRouteMatchForCurrentLocation() -> RouteBookRouteMatch? {
        let isLocationAuthorized: Bool
        switch routeBookLocationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isLocationAuthorized = true
        case .notDetermined, .denied, .restricted:
            isLocationAuthorized = false
        @unknown default:
            isLocationAuthorized = false
        }

        guard isLocationAuthorized,
              routeBookReplayCoordinates.count == routeBookReplayDistances.count,
              routeBookReplayCoordinates.count > 1,
              let totalDistance = routeBookReplayDistances.last,
              totalDistance > 0,
              let location = routeBookCurrentLocation(),
              let maximumMatchDistance = routeBookMaximumMatchDistance(for: location) else {
            return nil
        }
        if let routeBookMatchCache,
           routeBookMatchCache.matches(location) {
            return routeBookMatchCache.match
        }

        let displayCoordinate = CoordinateTransformer.displayCoordinate(for: location.coordinate)
        guard CLLocationCoordinate2DIsValid(displayCoordinate) else {
            return nil
        }

        let userPoint = MKMapPoint(displayCoordinate)
        guard let coarseGeometry = routeBookMatchingGeometry else {
            return nil
        }
        guard let coarseProjection = nearestRouteBookProjection(
            to: userPoint,
            coordinates: coarseGeometry.coordinates,
            cumulativeDistances: coarseGeometry.cumulativeDistances,
            segmentStartIndices: coarseGeometry.segmentStartIndices,
            segmentIndexRange: nil
        ) else {
            return nil
        }

        let firstSourceIndex = coarseGeometry
            .sourceIndices[coarseProjection.segmentIndex]
        let lastSourceIndex = coarseGeometry
            .sourceIndices[coarseProjection.segmentIndex + 1]
        let firstCoordinateIndex = max(min(firstSourceIndex, lastSourceIndex) - 1, 0)
        let localSegmentUpperBound = min(
            max(max(firstSourceIndex, lastSourceIndex) + 1, firstCoordinateIndex),
            routeBookReplayCoordinates.count - 1
        )
        guard let exactProjection = nearestRouteBookProjection(
            to: userPoint,
            coordinates: routeBookReplayCoordinates,
            cumulativeDistances: routeBookReplayDistances,
            segmentStartIndices: routeBookReplaySegmentStartIndices,
            segmentIndexRange: firstCoordinateIndex..<localSegmentUpperBound
        ) else {
            return nil
        }

        let distanceToRoute = userPoint.distance(to: exactProjection.projectedPoint)
        guard distanceToRoute <= maximumMatchDistance else {
            routeBookMatchCache = RouteBookMatchCache(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                match: nil
            )
            return nil
        }

        let match = RouteBookRouteMatch(
            progress: CGFloat(min(max(exactProjection.routeDistance / totalDistance, 0), 1)),
            coordinate: displayCoordinate,
            routeDistance: exactProjection.routeDistance,
            segmentIndex: exactProjection.segmentIndex,
            segmentProjection: exactProjection.segmentProjection
        )
        routeBookMatchCache = RouteBookMatchCache(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            match: match
        )
        return match
    }

    private func nearestRouteBookProjection(
        to userPoint: MKMapPoint,
        coordinates: [CLLocationCoordinate2D],
        cumulativeDistances: [CLLocationDistance],
        segmentStartIndices: Set<Int>,
        segmentIndexRange: Range<Int>?
    ) -> RouteBookProjection? {
        guard coordinates.count == cumulativeDistances.count,
              coordinates.count > 1 else {
            return nil
        }

        let validRange = 0..<(coordinates.count - 1)
        let requestedRange = segmentIndexRange ?? validRange
        let lowerBound = max(requestedRange.lowerBound, validRange.lowerBound)
        let upperBound = min(requestedRange.upperBound, validRange.upperBound)
        guard lowerBound < upperBound else {
            return nil
        }

        var nearestProjection: RouteBookProjection?
        for index in lowerBound..<upperBound {
            guard !segmentStartIndices.contains(index + 1) else {
                continue
            }
            let startPoint = MKMapPoint(coordinates[index])
            let endPoint = MKMapPoint(coordinates[index + 1])
            let deltaX = endPoint.x - startPoint.x
            let deltaY = endPoint.y - startPoint.y
            let segmentLengthSquared = deltaX * deltaX + deltaY * deltaY
            let projection: Double
            if segmentLengthSquared > 0 {
                let userDeltaX = userPoint.x - startPoint.x
                let userDeltaY = userPoint.y - startPoint.y
                projection = min(
                    max(
                        (userDeltaX * deltaX + userDeltaY * deltaY)
                            / segmentLengthSquared,
                        0
                    ),
                    1
                )
            } else {
                projection = 0
            }

            let projectedPoint = MKMapPoint(
                x: startPoint.x + deltaX * projection,
                y: startPoint.y + deltaY * projection
            )
            let distanceX = userPoint.x - projectedPoint.x
            let distanceY = userPoint.y - projectedPoint.y
            let distanceSquared = distanceX * distanceX + distanceY * distanceY
            guard distanceSquared < (nearestProjection?.distanceSquared ?? .greatestFiniteMagnitude) else {
                continue
            }

            let segmentRouteDistance = cumulativeDistances[index + 1]
                - cumulativeDistances[index]
            nearestProjection = RouteBookProjection(
                distanceSquared: distanceSquared,
                projectedPoint: projectedPoint,
                routeDistance: cumulativeDistances[index]
                    + segmentRouteDistance * projection,
                segmentIndex: index,
                segmentProjection: projection
            )
        }
        return nearestProjection
    }

    private func routeBookReplayDistanceLowerBound(
        _ targetDistance: CLLocationDistance
    ) -> Int {
        var lowerBound = 0
        var upperBound = routeBookReplayDistances.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if routeBookReplayDistances[middle] < targetDistance {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func routeBookReplayDistanceUpperBound(
        _ targetDistance: CLLocationDistance
    ) -> Int {
        var lowerBound = 0
        var upperBound = routeBookReplayDistances.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if routeBookReplayDistances[middle] <= targetDistance {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func routeBookMaximumMatchDistance(for location: CLLocation) -> CLLocationDistance? {
        let locationAge = abs(location.timestamp.timeIntervalSinceNow)
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= routeBookMaximumLocationAccuracy,
              locationAge <= routeBookMaximumLocationAge else {
            return nil
        }

        return routeBookBaseMatchDistance + min(location.horizontalAccuracy, 50)
    }

    private func routeBookCurrentLocation() -> CLLocation? {
        routeBookLastLocation ?? routeBookMapView.userLocation.location ?? routeBookLocationManager.location
    }

    private func updateRouteBookReplayProgressIfPanelIsExpanded() {
        guard selectedRouteBookPanelDetent == .medium else {
            return
        }

        updateRouteBookReplayProgressForCurrentLocation()
    }

    @objc private func handleRouteBookReplayProgressChanged(_ sender: WorkoutRouteReplayRulerView) {
        guard let replayState = routeBookReplayState(for: sender.progress) else {
            return
        }

        routeBookLastFocusedDistance = replayState.distanceMeters
        sender.setIndicatorVisible(true)
        updateRouteBookReplayAnnotation(with: replayState)
    }

    private func updateRouteBookReplayAnnotation(with replayState: ReplayState) {
        let statusText = routeBookReplayStatusText(for: replayState)
        if let routeBookReplayAnnotation {
            routeBookReplayAnnotation.coordinate = replayState.coordinate
            routeBookReplayAnnotation.statusText = statusText
            routeBookReplayAnnotation.isFacingLeft = replayState.isFacingLeft
            if let annotationView = routeBookMapView.view(for: routeBookReplayAnnotation) as? RouteReplayAnnotationView {
                annotationView.configure(
                    emoji: routeBookReplayAnnotation.emoji,
                    statusText: statusText,
                    isFacingLeft: replayState.isFacingLeft
                )
                annotationView.superview?.bringSubviewToFront(annotationView)
            }
        } else {
            let annotation = RouteReplayAnnotation(
                coordinate: replayState.coordinate,
                emoji: "📍",
                statusText: statusText,
                isFacingLeft: replayState.isFacingLeft
            )
            routeBookReplayAnnotation = annotation
            routeBookMapView.addAnnotation(annotation)
            if let annotationView = routeBookMapView.view(for: annotation) {
                annotationView.superview?.bringSubviewToFront(annotationView)
            }
        }
    }

    private func routeBookReplayState(for match: RouteBookRouteMatch) -> ReplayState? {
        let nextIndex = match.segmentIndex + 1
        guard routeBookReplayCoordinates.indices.contains(match.segmentIndex),
              routeBookReplayCoordinates.indices.contains(nextIndex) else {
            return nil
        }

        let startCoordinate = routeBookReplayCoordinates[match.segmentIndex]
        let endCoordinate = routeBookReplayCoordinates[nextIndex]
        let altitude: Double?
        let startAltitude = routeBookReplayAltitude(at: match.segmentIndex)
        let endAltitude = routeBookReplayAltitude(at: nextIndex)
        if let startAltitude, let endAltitude {
            altitude = startAltitude + (endAltitude - startAltitude) * match.segmentProjection
        } else {
            altitude = match.segmentProjection < 0.5 ? startAltitude : endAltitude
        }

        return ReplayState(
            coordinate: match.coordinate,
            distanceMeters: match.routeDistance,
            altitudeMeters: altitude,
            heartRateBeatsPerMinute: nil,
            powerWatts: nil,
            temperatureCelsius: nil,
            isFacingLeft: endCoordinate.longitude - startCoordinate.longitude < 0
        )
    }

    private func routeBookReplayState(for progress: CGFloat) -> ReplayState? {
        guard routeBookReplayCoordinates.count == routeBookReplayDistances.count,
              let totalDistance = routeBookReplayDistances.last,
              totalDistance > 0 else {
            return routeBookReplayState(at: 0)
        }

        let targetDistance = min(max(CLLocationDistance(progress), 0), 1) * totalDistance
        let upperIndex = routeBookReplayDistanceLowerBound(targetDistance)
        guard upperIndex > 0 else {
            return routeBookReplayState(at: 0)
        }
        guard upperIndex < routeBookReplayCoordinates.count else {
            return routeBookReplayState(at: routeBookReplayCoordinates.count - 1)
        }
        let lowerIndex = upperIndex - 1
        if routeBookReplaySegmentStartIndices.contains(upperIndex) {
            let lowerDelta = targetDistance - routeBookReplayDistances[lowerIndex]
            let upperDelta = routeBookReplayDistances[upperIndex] - targetDistance
            return routeBookReplayState(at: lowerDelta <= upperDelta ? lowerIndex : upperIndex)
        }

        let distanceSpan = routeBookReplayDistances[upperIndex]
            - routeBookReplayDistances[lowerIndex]
        guard distanceSpan > 0 else {
            return routeBookReplayState(at: upperIndex)
        }
        let interpolation = min(
            max((targetDistance - routeBookReplayDistances[lowerIndex]) / distanceSpan, 0),
            1
        )
        let lowerCoordinate = routeBookReplayCoordinates[lowerIndex]
        let upperCoordinate = routeBookReplayCoordinates[upperIndex]
        let lowerAltitude = routeBookReplayAltitude(at: lowerIndex)
        let upperAltitude = routeBookReplayAltitude(at: upperIndex)
        let altitude: Double?
        if let lowerAltitude, let upperAltitude {
            altitude = lowerAltitude + (upperAltitude - lowerAltitude) * interpolation
        } else {
            altitude = interpolation < 0.5 ? lowerAltitude : upperAltitude
        }
        return ReplayState(
            coordinate: CLLocationCoordinate2D(
                latitude: lowerCoordinate.latitude
                    + (upperCoordinate.latitude - lowerCoordinate.latitude) * interpolation,
                longitude: lowerCoordinate.longitude
                    + (upperCoordinate.longitude - lowerCoordinate.longitude) * interpolation
            ),
            distanceMeters: targetDistance,
            altitudeMeters: altitude,
            heartRateBeatsPerMinute: nil,
            powerWatts: nil,
            temperatureCelsius: nil,
            isFacingLeft: upperCoordinate.longitude - lowerCoordinate.longitude < 0
        )
    }

    private func routeBookReplayState(at index: Int) -> ReplayState? {
        guard routeBookReplayCoordinates.indices.contains(index),
              routeBookReplayDistances.indices.contains(index) else {
            return nil
        }
        return ReplayState(
            coordinate: routeBookReplayCoordinates[index],
            distanceMeters: routeBookReplayDistances[index],
            altitudeMeters: routeBookReplayAltitude(at: index),
            heartRateBeatsPerMinute: nil,
            powerWatts: nil,
            temperatureCelsius: nil,
            isFacingLeft: routeBookReplayFacingLeft(at: index)
        )
    }

    private func routeBookReplayAltitude(at index: Int) -> Double? {
        guard index >= 0, index < routeBookReplayAltitudes.count else {
            return nil
        }

        return routeBookReplayAltitudes[index]
    }

    private func routeBookReplayFacingLeft(at index: Int) -> Bool {
        guard routeBookReplayCoordinates.count > 1 else {
            return true
        }

        let previousIndex = routeBookReplaySegmentStartIndices.contains(index)
            ? index
            : max(index - 1, 0)
        let nextIndex = routeBookReplaySegmentStartIndices.contains(index + 1)
            ? index
            : min(index + 1, routeBookReplayCoordinates.count - 1)
        guard previousIndex != nextIndex else {
            return true
        }

        let previousCoordinate = routeBookReplayCoordinates[previousIndex]
        let nextCoordinate = routeBookReplayCoordinates[nextIndex]
        return nextCoordinate.longitude - previousCoordinate.longitude < 0
    }

    private func routeBookReplayStatusText(for state: ReplayState) -> String {
        let distanceText: String
        if state.distanceMeters >= 1000 {
            distanceText = String(format: "%.2f km", state.distanceMeters / 1000)
        } else {
            distanceText = String(format: "%.0f m", max(state.distanceMeters, 0))
        }

        let altitudeText = state.altitudeMeters.map { "\(Int(round($0))) m" } ?? "-- m"
        return "\(distanceText) · \(altitudeText)"
    }

    private func removeRouteBookReplayAnnotation() {
        guard let routeBookReplayAnnotation else {
            return
        }

        routeBookMapView.removeAnnotation(routeBookReplayAnnotation)
        self.routeBookReplayAnnotation = nil
    }

    private func drawRouteBookRoute(
        _ preparedRouteBook: PreparedRouteBook,
        for workout: TrackedWorkout
    ) {
        if !routeBookDisplayPolylines.isEmpty {
            routeBookMapView.removeOverlays(routeBookDisplayPolylines)
        }
        removeRouteBookEndpointAnnotations()

        routeBookBoundingMapRect = preparedRouteBook.boundingMapRect
        let displayGeometry = preparedRouteBook.displayGeometry
        routeBookDisplayPolylines = RouteViewportDistanceResolver.displayPolylines(
            coordinates: displayGeometry.coordinates,
            segmentStartIndices: displayGeometry.segmentStartIndices
        )
        configureRouteBookDirectionIndicatorSelection()
        routeBookMapView.addOverlays(routeBookDisplayPolylines, level: .aboveLabels)
        let startCoordinate = routeBookDisplayEndpointCoordinate(
            workout.routeCollectionMergeStartCoordinate
        ) ?? preparedRouteBook.coordinates[0]
        let endCoordinate = routeBookDisplayEndpointCoordinate(
            workout.routeCollectionMergeEndCoordinate
        ) ?? preparedRouteBook.coordinates[preparedRouteBook.coordinates.count - 1]
        routeBookEndpointAnnotations = [
            RouteEndpointAnnotation(coordinate: startCoordinate, kind: .start),
            RouteEndpointAnnotation(coordinate: endCoordinate, kind: .end)
        ]
        routeBookMapView.addAnnotations(routeBookEndpointAnnotations)
        resetRouteBookMapHeading(animated: false)
        routeBookMapView.setVisibleMapRect(
            preparedRouteBook.boundingMapRect,
            edgePadding: UIEdgeInsets(
                top: 150,
                left: 44,
                bottom: routeBookPanelContentHeight(for: .medium) + 44 + AppMapContainerView.defaultBottomLogoAvoidanceOffset,
                right: 44
            ),
            animated: false
        )
    }

    private func configureRouteBookSlopeOverlays(
        _ slopeSegments: [PreparedRouteBookSlopeSegment],
        displayGeometry: RouteViewportDistanceResolver.PreparedGeometry
    ) {
        if !routeBookSlopePolylines.isEmpty {
            routeBookMapView.removeOverlays(routeBookSlopePolylines)
        }
        if !routeBookSlopeDirectionPolylines.isEmpty {
            routeBookMapView.removeOverlays(routeBookSlopeDirectionPolylines)
        }
        routeBookSlopePolylines = []
        routeBookSlopeGradients = [:]
        routeBookSlopeDirectionPolylines = []
        routeBookSlopeDirectionPolylineIdentifiers = []
        areRouteBookSlopeDirectionOverlaysSuspendedForMapChange = false
        isRouteBookSlopeVisible = false

        var remainingChunkCount = routeBookMaximumSlopeOverlayChunkCount
        var renderedSlopeSegmentIndices = Set<Int>()
        for (index, slopeSegment) in slopeSegments.enumerated() {
            guard remainingChunkCount > 0 else {
                break
            }
            let remainingSegmentCount = slopeSegments.count - index
            let segmentChunkLimit = max(
                1,
                remainingChunkCount / max(remainingSegmentCount, 1)
            )
            let chunks = RouteSlopeOverlayFactory.makeChunks(
                coordinates: slopeSegment.coordinates,
                sourceLocations: slopeSegment.sourceLocations,
                gradient: slopeSegment.gradient,
                totalDistance: slopeSegment.totalDistance,
                preferredChunkDistance: routeBookPreferredSlopeOverlayChunkDistance,
                maximumChunkCount: segmentChunkLimit
            )
            guard !chunks.isEmpty else {
                continue
            }
            renderedSlopeSegmentIndices.insert(slopeSegment.segmentIndex)
            for chunk in chunks {
                routeBookSlopePolylines.append(chunk.polyline)
                routeBookSlopeGradients[ObjectIdentifier(chunk.polyline)] = chunk.gradient
            }
            remainingChunkCount -= chunks.count
            routeBookSlopeDirectionPolylines.append(MKPolyline(
                coordinates: slopeSegment.coordinates,
                count: slopeSegment.coordinates.count
            ))
        }

        if !routeBookSlopePolylines.isEmpty {
            let displaySegmentCount = displayGeometry.segmentStartIndices.count + 1
            let displaySourceSegmentIndices = displayGeometry.sourceSegmentIndices.count
                    == displaySegmentCount
                ? displayGeometry.sourceSegmentIndices
                : Array(0..<displaySegmentCount)
            let uncoveredDisplaySegmentIndices = Set(
                displaySourceSegmentIndices.enumerated().compactMap {
                    renderedSlopeSegmentIndices.contains($0.element) ? nil : $0.offset
                }
            )
            let uncoveredPolylines = RouteViewportDistanceResolver.displayPolylines(
                coordinates: displayGeometry.coordinates,
                segmentStartIndices: displayGeometry.segmentStartIndices,
                includedSegmentIndices: uncoveredDisplaySegmentIndices
            )
            routeBookSlopePolylines.insert(contentsOf: uncoveredPolylines, at: 0)
            for uncoveredPolyline in uncoveredPolylines {
                routeBookSlopeGradients[ObjectIdentifier(uncoveredPolyline)] = .unavailable
            }
        } else {
            routeBookSlopeGradients = [:]
            routeBookSlopeDirectionPolylines = []
        }
        routeBookSlopeDirectionPolylineIdentifiers = Set(
            routeBookSlopeDirectionPolylines.map(ObjectIdentifier.init)
        )
        updateRouteBookSlopeVisibilityButtonAppearance()
    }

    private func configureRouteBookDirectionIndicatorSelection() {
        let maximumIndicatorCount = 80
        let selectedPolylineCount = min(
            routeBookDisplayPolylines.count,
            maximumIndicatorCount
        )
        guard selectedPolylineCount > 0 else {
            routeBookDirectionIndicatorPolylines = []
            routeBookDirectionIndicatorBudgets = [:]
            return
        }

        let selectedIndices: [Int]
        if selectedPolylineCount == 1 {
            selectedIndices = [0]
        } else {
            selectedIndices = (0..<selectedPolylineCount).map { offset in
                Int(round(
                    Double(routeBookDisplayPolylines.count - 1)
                        * Double(offset)
                        / Double(selectedPolylineCount - 1)
                ))
            }
        }

        routeBookDirectionIndicatorPolylines = selectedIndices.map {
            routeBookDisplayPolylines[$0]
        }
        let baseBudget = maximumIndicatorCount / selectedPolylineCount
        let remainder = maximumIndicatorCount % selectedPolylineCount
        routeBookDirectionIndicatorBudgets = Dictionary(
            uniqueKeysWithValues: routeBookDirectionIndicatorPolylines
                .enumerated()
                .map { offset, polyline in
                    (
                        ObjectIdentifier(polyline),
                        baseBudget + (offset < remainder ? 1 : 0)
                    )
                }
        )
    }

    private func routeBookDisplayEndpointCoordinate(
        _ coordinate: CLLocationCoordinate2D?
    ) -> CLLocationCoordinate2D? {
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }
        return CoordinateTransformer.displayCoordinate(for: coordinate)
    }

    private func removeRouteBookEndpointAnnotations() {
        guard !routeBookEndpointAnnotations.isEmpty else {
            return
        }
        routeBookMapView.removeAnnotations(routeBookEndpointAnnotations)
        routeBookEndpointAnnotations.removeAll()
    }

    private func requestRouteBookLocationAuthorizationIfNeeded() {
        switch routeBookLocationManager.authorizationStatus {
        case .notDetermined:
            routeBookLocationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            routeBookMapView.showsUserLocation = true
            requestTemporaryPreciseLocationIfNeeded()
            startRouteBookLocationAndHeadingUpdates()
        case .denied, .restricted:
            routeBookMapView.showsUserLocation = false
            stopRouteBookLocationAndHeadingUpdates()
            break
        @unknown default:
            break
        }

        updateRouteBookLocateButtonState()
    }

    private func requestTemporaryPreciseLocationIfNeeded() {
        guard routeBookLocationManager.accuracyAuthorization == .reducedAccuracy else {
            return
        }

        routeBookLocationManager.requestTemporaryFullAccuracyAuthorization(
            withPurposeKey: "RouteBookNavigation"
        )
    }

    @objc private func handleRouteBookLocateButtonTap() {
        switch routeBookLocationManager.authorizationStatus {
        case .notDetermined:
            shouldCenterRouteBookOnNextLocation = true
            routeBookLocationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            routeBookMapView.showsUserLocation = true
            requestTemporaryPreciseLocationIfNeeded()
            startRouteBookLocationAndHeadingUpdates()
            if !centerRouteBookMapOnUser(animated: true) {
                shouldCenterRouteBookOnNextLocation = true
                routeBookLocationManager.requestLocation()
            }
        case .denied, .restricted:
            presentRouteBookLocationSettingsAlert()
        @unknown default:
            break
        }

        updateRouteBookLocateButtonState()
    }

    private func updateRouteBookLocateButtonState() {
        let isAuthorized: Bool
        switch routeBookLocationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
        case .notDetermined, .denied, .restricted:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }

        var configuration = routeBookLocateButton.configuration ?? .filled()
        configuration.image = UIImage(
            systemName: isAuthorized ? "location.fill" : "location.slash.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        routeBookLocateButton.configuration = configuration
    }

    @discardableResult
    private func centerRouteBookMapOnUser(animated: Bool) -> Bool {
        let location = routeBookLastLocation ?? routeBookMapView.userLocation.location ?? routeBookLocationManager.location
        guard let coordinate = location?.coordinate,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return false
        }

        routeBookMapView.setRegion(
            MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 800,
                longitudinalMeters: 800
            ),
            animated: animated
        )
        resetRouteBookMapHeading(animated: animated)
        return true
    }

    private func resetRouteBookMapHeading(animated: Bool) {
        guard routeBookMapView.camera.heading != 0 else {
            return
        }

        let camera = routeBookMapView.camera
        camera.heading = 0
        routeBookMapView.setCamera(camera, animated: animated)
    }

    private func startRouteBookLocationAndHeadingUpdates() {
        routeBookLocationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            routeBookLocationManager.startUpdatingHeading()
        }
        updateRouteBookUserLocationHeadingView()
    }

    private func stopRouteBookLocationAndHeadingUpdates() {
        routeBookLocationManager.stopUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            routeBookLocationManager.stopUpdatingHeading()
        }
    }

    private func updateRouteBookUserLocationHeadingView() {
        (routeBookMapView.view(for: routeBookMapView.userLocation) as? RouteBookUserLocationAnnotationView)?
            .configure(headingDegrees: routeBookLastHeadingDegrees)
    }

    private func presentRouteBookLocationSettingsAlert() {
        let alertController = UIAlertController(
            title: AppLocalization.text(.routeBookLocationPermissionRequiredTitle),
            message: AppLocalization.text(.routeBookLocationPermissionRequiredMessage),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(
            title: AppLocalization.text(.cancel),
            style: .cancel
        ))
        alertController.addAction(UIAlertAction(
            title: AppLocalization.text(.openSettings),
            style: .default
        ) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                return
            }

            UIApplication.shared.open(url)
        })
        routeBookModalPresentationHost.present(alertController, animated: true)
    }

    private func presentRouteBookExitAlert() {
        let alertController = UIAlertController(
            title: AppLocalization.text(.routeBookExit),
            message: AppLocalization.text(.routeBookExitMessage),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(
            title: AppLocalization.text(.cancel),
            style: .cancel
        ))
        alertController.addAction(UIAlertAction(
            title: AppLocalization.text(.exit),
            style: .destructive
        ) { [weak self] _ in
            self?.exitRouteBookMode()
        })
        routeBookModalPresentationHost.present(alertController, animated: true)
    }

    private func exitRouteBookMode() {
        isRouteBookModeActive = false
        routeBookViewportUpdateWorkItem?.cancel()
        routeBookViewportUpdateWorkItem = nil
        routeBookPreparationCancellationToken?.cancel()
        routeBookPreparationCancellationToken = nil
        routeBookPreparationID = nil
        routeBookWorkout = nil
        RouteBookMode.clearActiveWorkout()
        shouldCenterRouteBookOnNextLocation = false
        routeBookLastLocation = nil
        routeBookMatchCache = nil
        routeBookLastHeadingDegrees = nil
        routeBookHeadingDisplayDegrees = nil
        removeRouteBookReplayAnnotation()
        removeRouteBookEndpointAnnotations()
        stopRouteBookLocationAndHeadingUpdates()
        routeBookMapView.setUserTrackingMode(.none, animated: false)
        routeBookMapView.showsUserLocation = false
        if !routeBookDisplayPolylines.isEmpty {
            routeBookMapView.removeOverlays(routeBookDisplayPolylines)
        }
        if !routeBookSlopePolylines.isEmpty {
            routeBookMapView.removeOverlays(routeBookSlopePolylines)
        }
        if !routeBookSlopeDirectionPolylines.isEmpty {
            routeBookMapView.removeOverlays(routeBookSlopeDirectionPolylines)
        }
        routeBookBoundingMapRect = nil
        routeBookDisplayPolylines = []
        routeBookDirectionIndicatorPolylines = []
        routeBookDirectionIndicatorBudgets = [:]
        routeBookSlopePolylines = []
        routeBookSlopeGradients = [:]
        routeBookSlopeDirectionPolylines = []
        routeBookSlopeDirectionPolylineIdentifiers = []
        areRouteBookSlopeDirectionOverlaysSuspendedForMapChange = false
        isRouteBookSlopeVisible = false
        updateRouteBookSlopeVisibilityButtonAppearance()
        routeBookLastFocusedDistance = nil
        isRouteBookMapRegionChanging = false
        updateRouteBookPanelText()

        routeBookMapContainerView.isHidden = true
        applyRouteBookInterfaceState()
        updateHeaderReadAuthorizationState()
        updateEmptyDataSourceVisibility()
        updateFullScreenInsets(force: true)
    }

    private func applyRouteBookInterfaceState() {
        guard isViewLoaded, collectionView != nil else {
            return
        }

        routeBookMapContainerView.isHidden = !isRouteBookModeActive
        routeBookLocateButton.isHidden = !isRouteBookModeActive
        routeBookMapStyleButton.isHidden = !isRouteBookModeActive
        routeBookSlopeVisibilityButton.isHidden = !isRouteBookModeActive
        setRouteBookScaleViewVisible(isRouteBookModeActive)
        let hidesRouteGrid = isRouteBookModeActive || isSimulatingHomeEmptyData
        routeGridView.isHidden = hidesRouteGrid
        collectionView.isHidden = hidesRouteGrid
        updateDemoModeEntryVisibility()
        headerView.backgroundColor = isRouteBookModeActive ? .clear : AppColors.solidBackground
        headerBlurView.isHidden = true
        updateRouteBookHeaderColors()
        setNeedsStatusBarAppearanceUpdate()

        if isRouteBookModeActive {
            setScrollDateIndicatorVisible(false, animated: false)
            emptyDataSourceView.isHidden = true
            view.bringSubviewToFront(headerView)
            view.bringSubviewToFront(routeBookScaleView)
            view.bringSubviewToFront(routeBookMapStyleButton)
            view.bringSubviewToFront(routeBookSlopeVisibilityButton)
            view.bringSubviewToFront(routeBookLocateButton)
            presentRouteBookPanelSheetIfNeeded()
        } else {
            dismissRouteBookPanelSheetIfNeeded(animated: false)
            view.bringSubviewToFront(headerView)
            view.bringSubviewToFront(scrollDateIndicatorView)
            view.bringSubviewToFront(demoModeEntryButton)
            updateEmptyDataSourceVisibility()
        }

        updateRouteCollectionBadgeVisibility()
    }

    private func updateRouteBookHeaderColors() {
        if isRouteBookModeActive {
            titleLabel.textColor = .black
            titleAccentLabel.textColor = AppColors.movinnGreen
            moreButton.tintColor = .black
        } else {
            titleLabel.textColor = .label
            titleAccentLabel.textColor = AppColors.movinnGreen
            moreButton.tintColor = .label
        }
    }

    private func setRouteBookScaleViewVisible(_ isVisible: Bool) {
        routeBookScaleView.layer.removeAllAnimations()
        routeBookScaleView.scaleVisibility = isVisible ? .visible : .hidden
        routeBookScaleView.isHidden = !isVisible
        routeBookScaleView.alpha = isVisible ? 1 : 0
    }
}

extension ViewController: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === routeBookPanelSheetViewController else {
            return
        }

        hasPresentedRouteBookPanelSheet = false
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ sheetPresentationController: UISheetPresentationController
    ) {
        guard sheetPresentationController.presentedViewController === routeBookPanelSheetViewController else {
            return
        }

        let detent: RouteBookPanelDetent = sheetPresentationController.selectedDetentIdentifier == Self.routeBookMediumPanelDetentIdentifier
            ? .medium
            : .minimum
        applyRouteBookPanelDetent(detent, animated: true)
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

extension ViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        guard mapView === routeBookMapView,
              isRouteBookModeActive else {
            return
        }
        handleRouteBookMapRegionWillChange()
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard mapView === routeBookMapView,
              isRouteBookModeActive else {
            return
        }

        handleRouteBookMapRegionChangeForReplayRuler()
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard mapView === routeBookMapView else {
            return nil
        }

        if let replayAnnotation = annotation as? RouteReplayAnnotation {
            let identifier = RouteReplayAnnotationView.reuseIdentifier
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? RouteReplayAnnotationView
                ?? RouteReplayAnnotationView(annotation: replayAnnotation, reuseIdentifier: identifier)
            annotationView.annotation = replayAnnotation
            annotationView.configure(
                emoji: replayAnnotation.emoji,
                statusText: replayAnnotation.statusText,
                isFacingLeft: replayAnnotation.isFacingLeft
            )
            annotationView.superview?.bringSubviewToFront(annotationView)
            return annotationView
        }

        if let endpointAnnotation = annotation as? RouteEndpointAnnotation {
            let identifier = RouteEndpointAnnotationView.reuseIdentifier
            let annotationView = mapView.dequeueReusableAnnotationView(
                withIdentifier: identifier
            ) as? RouteEndpointAnnotationView ?? RouteEndpointAnnotationView(
                annotation: endpointAnnotation,
                reuseIdentifier: identifier
            )
            annotationView.annotation = endpointAnnotation
            annotationView.configure(kind: endpointAnnotation.kind)
            return annotationView
        }

        guard annotation is MKUserLocation else {
            return nil
        }

        let annotationView = mapView.dequeueReusableAnnotationView(
            withIdentifier: RouteBookUserLocationAnnotationView.reuseIdentifier
        ) as? RouteBookUserLocationAnnotationView ?? RouteBookUserLocationAnnotationView(
            annotation: annotation,
            reuseIdentifier: RouteBookUserLocationAnnotationView.reuseIdentifier
        )
        annotationView.annotation = annotation
        annotationView.configure(headingDegrees: routeBookLastHeadingDegrees)
        return annotationView
    }

    func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        guard mapView === routeBookMapView else {
            return
        }

        views
            .filter { $0.annotation is RouteReplayAnnotation }
            .forEach { $0.superview?.bringSubviewToFront($0) }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let renderer = AppMapStyle.renderer(for: overlay) {
            return renderer
        }

        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }

        let polylineIdentifier = ObjectIdentifier(polyline)
        if routeBookSlopeDirectionPolylineIdentifiers.contains(polylineIdentifier) {
            let renderer = RouteDirectionPolylineRenderer(polyline: polyline)
            renderer.drawsRouteStroke = false
            renderer.strokeColor = .clear
            renderer.directionIndicatorColor = routeBookRouteStrokeColor
            renderer.directionIndicatorSpacing = 180
            renderer.maximumIndicatorCount = isRouteBookMapRegionChanging
                ? 0
                : min(40, max(4, 48 / max(routeBookSlopeDirectionPolylines.count, 1)))
            return renderer
        }

        if let gradient = routeBookSlopeGradients[polylineIdentifier] {
            return AppMapStyle.makeSlopeRenderer(
                for: polyline,
                gradient: gradient,
                matchingNativeLineWidth: AppMapStyle.slopeReferenceRouteLineWidth
            )
        }

        let renderer = RouteDirectionPolylineRenderer(polyline: polyline)
        renderer.strokeColor = routeBookRouteStrokeColor
        renderer.directionIndicatorColor = routeBookRouteStrokeColor
        renderer.lineWidth = AppMapStyle.routeLineWidth
        renderer.lineJoin = .round
        renderer.lineCap = .round
        renderer.maximumIndicatorCount = isRouteBookMapRegionChanging
            ? 0
            : routeBookDirectionIndicatorBudgets[polylineIdentifier] ?? 0
        return renderer
    }

    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        guard mapView === routeBookMapView,
              isRouteBookModeActive else {
            return
        }

        if let location = userLocation.location {
            routeBookLastLocation = location
            updateRouteBookUserLocationHeadingView()
            updateRouteBookReplayProgressIfPanelIsExpanded()
        }

        if shouldCenterRouteBookOnNextLocation {
            shouldCenterRouteBookOnNextLocation = !centerRouteBookMapOnUser(animated: true)
        }
    }
}

extension ViewController: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === routeBookLocationManager, isRouteBookModeActive else {
            return
        }

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestTemporaryPreciseLocationIfNeeded()
            routeBookMapView.showsUserLocation = true
            startRouteBookLocationAndHeadingUpdates()
            if shouldCenterRouteBookOnNextLocation {
                shouldCenterRouteBookOnNextLocation = !centerRouteBookMapOnUser(animated: true)
                if shouldCenterRouteBookOnNextLocation {
                    manager.requestLocation()
                }
            }
        case .denied, .restricted:
            shouldCenterRouteBookOnNextLocation = false
            routeBookMapView.showsUserLocation = false
            stopRouteBookLocationAndHeadingUpdates()
        case .notDetermined:
            break
        @unknown default:
            break
        }

        updateRouteBookLocateButtonState()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === routeBookLocationManager,
              isRouteBookModeActive else {
            return
        }

        if let location = locations.last {
            routeBookLastLocation = location
            updateRouteBookUserLocationHeadingView()
            updateRouteBookReplayProgressIfPanelIsExpanded()
        }

        if shouldCenterRouteBookOnNextLocation {
            shouldCenterRouteBookOnNextLocation = !centerRouteBookMapOnUser(animated: true)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard manager === routeBookLocationManager,
              isRouteBookModeActive else {
            return
        }

        guard newHeading.headingAccuracy >= 0 else {
            return
        }

        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        guard heading >= 0 else {
            return
        }

        routeBookLastHeadingDegrees = smoothedRouteBookHeading(from: heading)
        updateRouteBookUserLocationHeadingView()
    }

    private func smoothedRouteBookHeading(from heading: CLLocationDirection) -> CLLocationDirection {
        let normalizedHeading = Self.normalizedHeading(heading)
        guard let currentHeading = routeBookHeadingDisplayDegrees else {
            routeBookHeadingDisplayDegrees = normalizedHeading
            return normalizedHeading
        }

        let delta = Self.shortestHeadingDelta(from: currentHeading, to: normalizedHeading)
        if abs(delta) < 1.4 {
            return currentHeading
        }

        let smoothedHeading = Self.normalizedHeading(currentHeading + delta * 0.32)
        routeBookHeadingDisplayDegrees = smoothedHeading
        return smoothedHeading
    }

    private static func normalizedHeading(_ heading: CLLocationDirection) -> CLLocationDirection {
        var normalizedHeading = heading.truncatingRemainder(dividingBy: 360)
        if normalizedHeading < 0 {
            normalizedHeading += 360
        }
        return normalizedHeading
    }

    private static func shortestHeadingDelta(
        from startHeading: CLLocationDirection,
        to endHeading: CLLocationDirection
    ) -> CLLocationDirection {
        var delta = normalizedHeading(endHeading) - normalizedHeading(startHeading)
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        return delta
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === routeBookLocationManager else {
            return
        }

        shouldCenterRouteBookOnNextLocation = false
        PTrackLog.synchronization.debug("PTrack RouteBook: location update failed: \(error)")
    }
}

private final class RouteBookPanelSheetViewController: UIViewController {
    var onViewDidLayout: ((CGFloat) -> Void)?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onViewDidLayout?(view.bounds.height)
    }
}

private final class RouteBookUserLocationAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "RouteBookUserLocationAnnotationView"

    private enum Metrics {
        static let size: CGFloat = 50
        static let markerSize: CGFloat = 44
    }

    private let markerView = RouteBookUserLocationMarkerView()
    private var headingDegrees: CLLocationDirection?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutMarkerView()
        applyHeadingTransform()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        configure(headingDegrees: nil)
    }

    func configure(headingDegrees: CLLocationDirection?) {
        self.headingDegrees = headingDegrees
        markerView.showsHeading = headingDegrees != nil
        applyHeadingTransform()
    }

    private func configureView() {
        frame = CGRect(x: 0, y: 0, width: Metrics.size, height: Metrics.size)
        bounds = CGRect(x: 0, y: 0, width: Metrics.size, height: Metrics.size)
        centerOffset = .zero
        canShowCallout = false
        isUserInteractionEnabled = false
        displayPriority = .required
        collisionMode = .none
        layer.masksToBounds = false

        markerView.backgroundColor = .clear
        markerView.isUserInteractionEnabled = false
        markerView.layer.shadowColor = UIColor.black.cgColor
        markerView.layer.shadowOpacity = 0.16
        markerView.layer.shadowRadius = 4
        markerView.layer.shadowOffset = .zero

        addSubview(markerView)
        layoutMarkerView()
    }

    private func layoutMarkerView() {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        markerView.bounds = CGRect(x: 0, y: 0, width: Metrics.markerSize, height: Metrics.markerSize)
        markerView.center = center
    }

    private func applyHeadingTransform() {
        if let headingDegrees {
            markerView.transform = CGAffineTransform(rotationAngle: CGFloat(headingDegrees * .pi / 180))
        } else {
            markerView.transform = .identity
        }
    }
}

private final class RouteBookUserLocationMarkerView: UIView {
    var showsHeading = false {
        didSet {
            guard oldValue != showsHeading else {
                return
            }

            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let blue = UIColor.systemBlue
        let outline = AppColors.solidBackground

        if showsHeading {
            drawHeadingArrow(center: center, fillColor: blue, outlineColor: outline)
        }

        let outerRadius: CGFloat = 10
        let innerRadius: CGFloat = 7
        context.saveGState()
        outline.setFill()
        UIBezierPath(
            ovalIn: CGRect(
                x: center.x - outerRadius,
                y: center.y - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            )
        ).fill()
        blue.setFill()
        UIBezierPath(
            ovalIn: CGRect(
                x: center.x - innerRadius,
                y: center.y - innerRadius,
                width: innerRadius * 2,
                height: innerRadius * 2
            )
        ).fill()
        context.restoreGState()
    }

    private func drawHeadingArrow(center: CGPoint, fillColor: UIColor, outlineColor: UIColor) {
        let outlinePath = UIBezierPath()
        outlinePath.move(to: CGPoint(x: center.x, y: center.y - 21))
        outlinePath.addLine(to: CGPoint(x: center.x + 8.5, y: center.y - 12))
        outlinePath.addLine(to: CGPoint(x: center.x - 8.5, y: center.y - 12))
        outlinePath.close()

        outlineColor.setFill()
        outlinePath.fill()

        let arrowPath = UIBezierPath()
        arrowPath.move(to: CGPoint(x: center.x, y: center.y - 17.5))
        arrowPath.addLine(to: CGPoint(x: center.x + 5.5, y: center.y - 11.8))
        arrowPath.addLine(to: CGPoint(x: center.x - 5.5, y: center.y - 11.8))
        arrowPath.close()

        fillColor.setFill()
        arrowPath.fill()
    }
}

private enum HomeDataSourceEmptyMode {
    case authorization
    case loading
    case noData
}

private final class HomeDataSourceEmptyView: UIView {
    var onAppleHealthTap: (() -> Void)?
    var onStravaTap: (() -> Void)?
    var onAppleFitnessTap: (() -> Void)?

    private var mode: HomeDataSourceEmptyMode = .authorization
    private var isAppleHealthAuthorized = false
    private let stackView = UIStackView()
    private let noDataStackView = UIStackView()
    private let messageLabel = UILabel()
    private let appleFitnessButtonContainer = UIView()
    private let appleFitnessButton = HomeAppleFitnessButton()
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
        appleFitnessButton.configure(title: AppLocalization.text(.appleFitnessDownloadCTA))
        privacyLabel.attributedText = privacyStatementAttributedText(
            AppLocalization.text(.movinnLocalDataPrivacyStatement)
        )
        updateMessageText()
    }

    func setMode(_ mode: HomeDataSourceEmptyMode) {
        guard self.mode != mode else {
            return
        }

        self.mode = mode
        applyMode()
    }

    func updateAuthorizationState(appleHealth state: HealthWorkoutStore.AuthorizationState) {
        isAppleHealthAuthorized = state == .authorized
        switch state {
        case .authorized:
            appleHealthCard.setStatusIndicatorColor(AppColors.movinnGreen)
        case .notDetermined, .needsAttention:
            appleHealthCard.setStatusIndicatorColor(nil)
        }
        updateAppleFitnessButtonVisibility()
    }

    private func updateMessageText() {
        switch mode {
        case .authorization:
            messageLabel.text = nil
        case .loading:
            messageLabel.text = AppLocalization.text(.homeDataLoadingMessage)
        case .noData:
            messageLabel.text = AppLocalization.text(.homeNoWorkoutDataMessage)
        }
    }

    private func applyMode() {
        stackView.isHidden = mode != .authorization
        noDataStackView.isHidden = mode == .authorization
        updateAppleFitnessButtonVisibility()
        updateMessageText()
    }

    private func updateAppleFitnessButtonVisibility() {
        let shouldShowButton = mode == .noData && isAppleHealthAuthorized
        appleFitnessButtonContainer.isHidden = !shouldShowButton
        isUserInteractionEnabled = mode == .authorization || shouldShowButton
    }

    private func privacyStatementAttributedText(_ text: String) -> NSAttributedString {
        let font = privacyLabel.font ?? .systemFont(ofSize: 12, weight: .medium)
        let bulletPrefixWidth = "- ".size(withAttributes: [.font: font]).width
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.headIndent = ceil(bulletPrefixWidth)
        paragraphStyle.paragraphSpacing = 3
        paragraphStyle.lineBreakMode = .byWordWrapping

        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: privacyLabel.textColor ?? UIColor.secondaryLabel,
                .paragraphStyle: paragraphStyle
            ]
        )
    }

    private func configureViews() {
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12

        noDataStackView.axis = .vertical
        noDataStackView.alignment = .fill
        noDataStackView.spacing = 16
        noDataStackView.isHidden = true

        privacyLabel.textColor = .secondaryLabel
        privacyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        privacyLabel.numberOfLines = 0
        privacyLabel.textAlignment = .left

        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        appleHealthCard.addAction(UIAction { [weak self] _ in
            self?.onAppleHealthTap?()
        }, for: .touchUpInside)
        stravaCard.addAction(UIAction { [weak self] _ in
            self?.onStravaTap?()
        }, for: .touchUpInside)
        appleFitnessButton.addAction(UIAction { [weak self] _ in
            self?.onAppleFitnessTap?()
        }, for: .touchUpInside)

        addSubview(stackView)
        addSubview(noDataStackView)
        appleFitnessButtonContainer.addSubview(appleFitnessButton)
        stackView.addArrangedSubview(appleHealthCard)
        stackView.addArrangedSubview(stravaCard)
        stackView.setCustomSpacing(16, after: stravaCard)
        stackView.addArrangedSubview(privacyLabel)
        noDataStackView.addArrangedSubview(messageLabel)
        noDataStackView.addArrangedSubview(appleFitnessButtonContainer)

        stackView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview()
        }

        noDataStackView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
        }

        appleFitnessButtonContainer.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(44)
        }

        appleFitnessButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(12)
            make.trailing.lessThanOrEqualToSuperview().inset(12)
        }

        appleHealthCard.snp.makeConstraints { make in
            make.height.equalTo(76)
        }
        stravaCard.snp.makeConstraints { make in
            make.height.equalTo(76)
        }
    }
}

private final class HomeAppleFitnessButton: UIControl {
    private let capsuleBackgroundView = UIView()
    private let contentStackView = UIStackView()
    private let iconBackgroundView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14) {
                self.alpha = self.isHighlighted ? 0.7 : 1
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.985, y: 0.985)
                    : .identity
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        capsuleBackgroundView.layer.cornerRadius = capsuleBackgroundView.bounds.height / 2
    }

    func configure(title: String) {
        titleLabel.text = title
        accessibilityLabel = title
    }

    private func configureViews() {
        backgroundColor = .clear

        isAccessibilityElement = true
        accessibilityTraits = .button

        capsuleBackgroundView.backgroundColor = AppColors.cardBackground
        capsuleBackgroundView.layer.cornerCurve = .continuous
        capsuleBackgroundView.layer.masksToBounds = true
        capsuleBackgroundView.isUserInteractionEnabled = false

        contentStackView.axis = .horizontal
        contentStackView.alignment = .center
        contentStackView.spacing = 8
        contentStackView.isUserInteractionEnabled = false

        iconBackgroundView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        iconBackgroundView.layer.cornerRadius = 6
        iconBackgroundView.layer.cornerCurve = .continuous
        iconBackgroundView.layer.masksToBounds = true

        iconView.image = UIImage(named: "apple_fitness")?.withRenderingMode(.alwaysOriginal)
        iconView.contentMode = .scaleAspectFit

        titleLabel.textColor = .label
        titleLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 13, weight: .semibold)
        )
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .left
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        addSubview(capsuleBackgroundView)
        capsuleBackgroundView.addSubview(contentStackView)
        iconBackgroundView.addSubview(iconView)
        contentStackView.addArrangedSubview(iconBackgroundView)
        contentStackView.addArrangedSubview(titleLabel)

        capsuleBackgroundView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(3)
            make.leading.trailing.equalToSuperview()
            make.height.greaterThanOrEqualTo(38)
        }
        contentStackView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(12)
            make.trailing.equalToSuperview().inset(13)
            make.top.bottom.equalToSuperview().inset(7)
        }
        iconBackgroundView.snp.makeConstraints { make in
            make.size.equalTo(24)
        }
        iconView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(2.5)
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
    private let statusIndicatorView = UIView()

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

    func setStatusIndicatorColor(_ color: UIColor?) {
        statusIndicatorView.backgroundColor = color
        statusIndicatorView.isHidden = color == nil
    }

    private func configureViews() {
        layer.cornerRadius = 12
        layer.masksToBounds = true
        backgroundColor = style == .strava ? AppColors.stravaOrange : AppColors.cardBackground

        iconView.contentMode = .scaleAspectFit
        iconView.image = UIImage(named: "apple_health")?.withRenderingMode(.alwaysOriginal)
        iconView.isHidden = style != .appleHealth

        brandImageView.contentMode = .scaleAspectFit
        brandImageView.image = UIImage(named: "strava")?.withRenderingMode(.alwaysTemplate)
        brandImageView.tintColor = .white
        brandImageView.isHidden = style != .strava

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = style == .strava ? .white : AppColors.solidForeground
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.78
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isHidden = style == .strava

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = style == .strava ? UIColor.white.withAlphaComponent(0.88) : .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.lineBreakMode = .byTruncatingTail

        statusIndicatorView.isHidden = true
        statusIndicatorView.layer.cornerRadius = 4
        statusIndicatorView.layer.masksToBounds = true
        statusIndicatorView.layer.borderWidth = 1
        updateStatusIndicatorBorderColor()

        textStackView.axis = .vertical
        textStackView.alignment = .leading
        textStackView.spacing = 4
        textStackView.isUserInteractionEnabled = false

        addSubview(iconView)
        addSubview(brandImageView)
        addSubview(textStackView)
        addSubview(statusIndicatorView)
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

        statusIndicatorView.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(8)
            make.size.equalTo(8)
        }

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: Self, _) in
            cell.updateStatusIndicatorBorderColor()
        }
    }

    private func updateStatusIndicatorBorderColor() {
        statusIndicatorView.layer.borderColor = AppColors.statusIndicatorBorderColor(for: traitCollection)
    }
}

private extension TrackedWorkout {
    func isSamePhysicalWorkout(as other: TrackedWorkout) -> Bool {
        let hasDirectStravaAndHealthKitOrigins =
            (isDirectStravaSource && other.isHealthKitSource)
            || (isHealthKitSource && other.isDirectStravaSource)
        guard hasDirectStravaAndHealthKitOrigins else {
            return false
        }

        if let stravaActivityID,
           let otherStravaActivityID = other.stravaActivityID,
           stravaActivityID == otherStravaActivityID {
            return true
        }

        guard activityType.isCompatibleForSourceConflict(with: other.activityType) else {
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
