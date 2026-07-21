//
//  WorkoutRouteDetailViewController.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/13.
//

import MapKit
import HealthKit
import SnapKit
import UIKit

final class WorkoutRouteDetailViewController: UIViewController {
    enum PresentationMode {
        case workout
        case routeCollection
    }

    private enum PanelDetent: CaseIterable {
        case minimum
        case medium
    }

    private struct PreparedSlopeSegment {
        let segmentIndex: Int
        let coordinates: [CLLocationCoordinate2D]
        let sourceLocations: [Double]
        let gradient: RouteSlopeGradient
        let totalDistance: CLLocationDistance
    }

    private struct PreparedSlopeProfileSegment {
        let baseDistance: CLLocationDistance
        let endDistance: CLLocationDistance
        let analysis: RouteSlopeAnalysis
    }

    private struct PreparedSlopeData {
        let renderingSegments: [PreparedSlopeSegment]
        let profileSegments: [PreparedSlopeProfileSegment]
        let steepestUphill: RouteSlopePeak?
    }

    private struct PreparedRoute {
        let coordinates: [CLLocationCoordinate2D]
        let viewportGeometry: RouteViewportDistanceResolver.PreparedGeometry
        let displayGeometry: RouteViewportDistanceResolver.PreparedGeometry
        let slopeSegments: [PreparedSlopeSegment]
        let routeCoordinates: [RouteCoordinate]
        let boundingMapRect: MKMapRect
        let startCoordinate: CLLocationCoordinate2D
        let endCoordinate: CLLocationCoordinate2D
        let replayDistances: [CLLocationDistance]
        let replayAltitudes: [Double?]
        let replayHeartRates: [Double?]
        let replayPowers: [Double?]
        let replayTemperatures: [Double?]
        let replayGradeRatios: [Double?]
        let replaySegmentStartIndices: Set<Int>
        let elevationSamples: [RouteElevationSample]
        let globalPeakSamples: ElevationProfileView.PeakSamples
        let totalDistanceMeters: CLLocationDistance
    }

    let workout: TrackedWorkout
    private let presentationMode: PresentationMode
    private let providedMergeSourceWorkouts: [TrackedWorkout]?
    private let isDemoMode: Bool
    private let mediaStore = RouteMediaStore()
    private let mapContainerView = AppMapContainerView()
    private var mapView: MKMapView { mapContainerView.mapView }
    private let mapToneOverlay = AppMapStyle.makeToneOverlay()
    private let routePreparationQueue = DispatchQueue(label: "studio.pj.PTrack.route-detail-prepare", qos: .userInitiated)
    private var routePreparationCancellationToken: RouteSlopePreparationCancellationToken?
    private let routeMergeSourceLoadQueue = DispatchQueue(label: "studio.pj.PTrack.route-merge-source-load", qos: .userInitiated)
    private let gpxExportQueue = DispatchQueue(label: "studio.pj.PTrack.gpx-export", qos: .userInitiated)
    private let routeLoadingView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let routeLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private let routeLoadingLabel = UILabel()
    private let gpxExportLoadingView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let gpxExportLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private let gpxExportLoadingLabel = UILabel()
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let panelSheetViewController = UIViewController()
    private let panelView = UIVisualEffectView(effect: WorkoutRouteDetailViewController.makePanelGlassEffect())
    private let handleTouchView = UIView()
    private let mapControlStackView = UIStackView()
    private let routeSlopeVisibilityButton = UIButton(type: .system)
    private let routeSlopeVisibilityIconView = UIImageView()
    private let routeMediaVisibilityButton = UIButton(type: .system)
    private let routeMediaVisibilityIconView = UIImageView()
    private let iconView = UIImageView()
    private let navigationTitleStackView = UIStackView()
    private let navigationTitleLabel = UILabel()
    private let navigationSubtitleLabel = UILabel()
    private let titleStackView = UIStackView()
    private let titleLabel = UILabel()
    private let dataSourceLabel = UILabel()
    private let metricsStackView = UIStackView()
    private let distanceLabel = UILabel()
    private let durationLabel = UILabel()
    private let detailStackView = UIStackView()
    private let replayRulerView = WorkoutRouteReplayRulerView()
    private let calorieRiceView = WorkoutRouteCalorieRiceView()
    private var primaryContentTopConstraint: Constraint?
    private var mapControlStackViewBottomConstraint: Constraint?
    private var selectedPanelDetent: PanelDetent = .minimum
    private var hasFittedRoute = false
    private var hasPresentedPanelSheet = false
    private var suppressPanelSheetPresentation = false
    var routeMediaItems: [RouteMediaItem] = []
    private var replayCoordinates: [CLLocationCoordinate2D] = []
    private var replayDistances: [CLLocationDistance] = []
    private var replayAltitudes: [Double?] = []
    private var replayHeartRates: [Double?] = []
    private var replayPowers: [Double?] = []
    private var replayTemperatures: [Double?] = []
    private var replayGradeRatios: [Double?] = []
    private var replaySegmentStartIndices = Set<Int>()
    private var replayViewportGeometry: RouteViewportDistanceResolver.PreparedGeometry?
    private var replayViewportUpdateWorkItem: DispatchWorkItem?
    private var lastFocusedRouteDistance: CLLocationDistance?
    private var replayAnnotation: RouteReplayAnnotation?
    private var routeBoundingMapRect: MKMapRect?
    private var routeDisplayPolylines: [MKPolyline] = []
    private var routeDisplayIndicatorPolylines: [MKPolyline] = []
    private var routeDisplayIndicatorBudgets: [ObjectIdentifier: Int] = [:]
    private var routeSlopePolylines: [MKPolyline] = []
    private var routeSlopeGradients: [ObjectIdentifier: RouteSlopeGradient] = [:]
    private var routeSlopeDirectionPolylines: [MKPolyline] = []
    private var routeSlopeDirectionPolylineIdentifiers = Set<ObjectIdentifier>()
    private var areSlopeDirectionOverlaysSuspendedForMapChange = false
    private var isMapRegionChanging = false
    private var routeSlopeGradient: RouteSlopeGradient?
    private var isRouteSlopeVisible = false
    private var selectedMapStyle = AppMapDisplayStyleStore.shared.routeDetailStyle()
    private var resolvedNavigationTitle: String?
    private var lastObservedPhotoAuthorizationState: PhotoLibraryAuthorizationState?
    private var hasDisplayedRouteMediaAnnotations = false
    private var hasStartedRouteLoading = false
    private var hasStartedDeferredDetailLoading = false
    private var isExportingGPX = false
    private var hasPreparedForPermanentDismissal = false

    private let minimumPanelHeight: CGFloat = 68
    private let detailContentTopSpacing: CGFloat = 24
    private let replayRulerViewHeight: CGFloat = 98
    private let calorieRiceViewHeight: CGFloat = 88
    private let calorieRiceTopSpacing: CGFloat = 12
    private let mediumPanelBottomPadding: CGFloat = 18
    private let panelHandleTouchHeight: CGFloat = 32
    private let mapControlPanelSpacing: CGFloat = 14
    private let mapControlButtonSpacing: CGFloat = 10
    private let primaryContentSize: CGFloat = 28
    private let expandedPrimaryContentTop: CGFloat = 33
    private let minimumPrimaryContentScale: CGFloat = 0.88
    private let navigationBackgroundHeight: CGFloat = 124
    private let mapBottomExtension = AppMapContainerView.defaultBottomLogoAvoidanceOffset
    private let maximumElevationSampleCount = 24_000
    private let maximumDisplayCoordinateCount = 12_000
    private let maximumSlopeRenderingCoordinateCount = 1_200
    private let maximumSlopeSegmentCount = 8
    private let slopeGeometrySimplificationToleranceMeters: CLLocationDistance = 4
    private let preferredSlopeOverlayChunkDistance: CLLocationDistance = 15_000
    private let maximumSlopeOverlayChunkCount = 8
    private static let minimumPanelDetentIdentifier = UISheetPresentationController.Detent.Identifier(
        "routeDetailMinimum"
    )
    private static let mediumPanelDetentIdentifier = UISheetPresentationController.Detent.Identifier(
        "routeDetailMedium"
    )

    private var panelCaloriesKilocalories: Double? {
        guard let calories = workout.displayEnergyBurnedKilocalories, calories > 0 else {
            return nil
        }

        return calories
    }

    private var panelCaloriesIsEstimated: Bool {
        workout.isDisplayEnergyBurnedEstimated
    }

    init(
        workout: TrackedWorkout,
        presentationMode: PresentationMode = .workout,
        mergeSourceWorkouts: [TrackedWorkout]? = nil,
        isDemoMode: Bool = false
    ) {
        self.workout = workout
        self.presentationMode = presentationMode
        providedMergeSourceWorkouts = mergeSourceWorkouts
        self.isDemoMode = isDemoMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makePanelGlassEffect() -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            effect.tintColor = AppColors.background(alpha: 0.06)
            return effect
        }

        return UIBlurEffect(style: .systemThinMaterial)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureNavigationItem()
        registerLanguageObserver()
        registerTraitChangeHandler()
        configureMapView()
        configureNavigationBackgroundView()
        configureMapControlButtons()
        configureRouteLoadingView()
        configurePanelView()
        configureGPXExportLoadingView()
        if presentationMode == .routeCollection {
            resolvedNavigationTitle = workout.title
            updateNavigationLocationTitle(workout.title)
        }
    }

    deinit {
        prepareForPermanentDismissal()
        NotificationCenter.default.removeObserver(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppAppearanceStore.shared.preferredStatusBarStyle(for: traitCollection)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        configureDefaultNavigationBar()
        if presentationMode == .workout, !isDemoMode {
            refreshMoreMenuForPhotoAuthorizationState()
            applyRouteMediaVisibilityPreference()
        } else {
            navigationItem.rightBarButtonItem = makeMoreBarButtonItem()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if suppressPanelSheetPresentation {
            suppressPanelSheetPresentation = false
        } else {
            presentPanelSheetIfNeeded()
        }
        startDeferredDetailLoadingIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isPermanentlyLeaving {
            prepareForPermanentDismissal()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        fitRouteIfNeeded()
    }

    private var isPermanentlyLeaving: Bool {
        isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true
    }

    private func prepareForPermanentDismissal() {
        guard !hasPreparedForPermanentDismissal else {
            return
        }

        hasPreparedForPermanentDismissal = true
        routePreparationCancellationToken?.cancel()
        routePreparationCancellationToken = nil
        replayViewportUpdateWorkItem?.cancel()
        replayViewportUpdateWorkItem = nil
        isExportingGPX = false
        routeLoadingView.layer.removeAllAnimations()
        gpxExportLoadingView.layer.removeAllAnimations()
        routeLoadingIndicator.stopAnimating()
        gpxExportLoadingIndicator.stopAnimating()
        replayRulerView.removeTarget(self, action: nil, for: .allEvents)
        panelSheetViewController.sheetPresentationController?.delegate = nil
        mapView.delegate = nil
        if !mapView.overlays.isEmpty {
            mapView.removeOverlays(mapView.overlays)
        }
        if !mapView.annotations.isEmpty {
            mapView.removeAnnotations(mapView.annotations)
        }
        routeMediaItems.removeAll(keepingCapacity: false)
        replayCoordinates.removeAll(keepingCapacity: false)
        replayDistances.removeAll(keepingCapacity: false)
        replayAltitudes.removeAll(keepingCapacity: false)
        replayHeartRates.removeAll(keepingCapacity: false)
        replayPowers.removeAll(keepingCapacity: false)
        replayTemperatures.removeAll(keepingCapacity: false)
        replayGradeRatios.removeAll(keepingCapacity: false)
        replaySegmentStartIndices.removeAll(keepingCapacity: false)
        replayViewportGeometry = nil
        lastFocusedRouteDistance = nil
        routeBoundingMapRect = nil
        routeDisplayPolylines.removeAll(keepingCapacity: false)
        routeDisplayIndicatorPolylines.removeAll(keepingCapacity: false)
        routeDisplayIndicatorBudgets.removeAll(keepingCapacity: false)
        routeSlopePolylines.removeAll(keepingCapacity: false)
        routeSlopeGradients.removeAll(keepingCapacity: false)
        routeSlopeDirectionPolylines.removeAll(keepingCapacity: false)
        routeSlopeDirectionPolylineIdentifiers.removeAll(keepingCapacity: false)
        areSlopeDirectionOverlaysSuspendedForMapChange = false
        isMapRegionChanging = false
        routeSlopeGradient = nil
        replayAnnotation = nil
        mapView.layer.removeAllAnimations()
        mapContainerView.layer.removeAllAnimations()
        AppMapContainerView.retainForMetalDrain(mapContainerView)
    }

    private func configureNavigationItem() {
        title = nil
        navigationItem.titleView = makeNavigationTitleView()
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
        navigationItem.rightBarButtonItem = makeMoreBarButtonItem()
        if let resolvedNavigationTitle {
            updateNavigationLocationTitle(resolvedNavigationTitle)
        } else {
            updateNavigationLocationTitle(AppLocalization.text(.queryingLocation))
        }

        updatePanelText()

        if let caloriesKilocalories = panelCaloriesKilocalories {
            calorieRiceView.configure(
                caloriesKilocalories: caloriesKilocalories,
                isEstimated: panelCaloriesIsEstimated
            )
        }
        routeSlopeVisibilityButton.accessibilityLabel = AppLocalization.text(.routeSlope)
        updateRouteSlopeVisibilityButtonAppearance()
        routeMediaVisibilityButton.accessibilityLabel = AppLocalization.text(.photoMatching)
        routeLoadingLabel.text = AppLocalization.text(.routeLoading)
        gpxExportLoadingLabel.text = AppLocalization.text(.gpxExporting)
    }

    private func makeMoreBarButtonItem() -> UIBarButtonItem {
        UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            menu: makeMoreMenu()
        )
    }

    private func makeMoreMenu() -> UIMenu {
        let openStartAction = UIAction(
            title: AppLocalization.text(.openStart),
            image: UIImage(systemName: "location")
        ) { [weak self] _ in
            self?.openEndpointInMaps(kind: .start)
        }

        let openEndAction = UIAction(
            title: AppLocalization.text(.openEnd),
            image: UIImage(systemName: "mappin.and.ellipse")
        ) { [weak self] _ in
            self?.openEndpointInMaps(kind: .end)
        }

        let routeBookAction = UIAction(
            title: AppLocalization.text(.routeBook),
            image: UIImage(systemName: "map")
        ) { [weak self] _ in
            self?.startRouteBookMode()
        }

        let startNavigationMenu = UIMenu(
            title: AppLocalization.text(.navigation),
            image: UIImage(systemName: "location.north.line"),
            children: [
                openStartAction,
                openEndAction,
                routeBookAction
            ]
        )

        let exportGPXAction = UIAction(
            title: AppLocalization.text(.exportGPX),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.exportGPX()
        }
        exportGPXAction.attributes = isExportingGPX ? [.disabled] : []

        let mergeRouteAction = UIAction(
            title: AppLocalization.text(.routeMerge),
            image: UIImage(systemName: "arrow.trianglehead.merge") ?? UIImage(systemName: "arrow.merge")
        ) { [weak self] _ in
            self?.presentRouteMergeSelection()
        }

        let shareAction = UIAction(
            title: AppLocalization.text(.share),
            image: UIImage(systemName: "square.and.arrow.up.on.square")
        ) { [weak self] _ in
            self?.showRouteShare()
        }

        let photoMatchingAction = UIAction(
            title: AppLocalization.text(.photoMatching),
            image: UIImage(systemName: "photo.on.rectangle")
        ) { [weak self] _ in
            self?.presentPhotoLibrarySettingsAlert()
        }

        let mapStyleActions = AppMapDisplayStyle.menuCases.map { style in
            UIAction(
                title: style.title,
                state: style == selectedMapStyle ? .on : .off
            ) { [weak self] _ in
                self?.applyMapStyle(style)
            }
        }

        if isDemoMode {
            return UIMenu(
                title: "",
                children: [
                    UIMenu(
                        title: AppLocalization.text(.mapStyle),
                        image: UIImage(systemName: "map"),
                        children: mapStyleActions
                    )
                ]
            )
        }

        guard presentationMode == .workout else {
            return UIMenu(
                title: "",
                children: [startNavigationMenu]
            )
        }

        var menuChildren: [UIMenuElement] = [
            shareAction
        ]
        if PhotoLibraryAuthorizationManager.authorizationState == .needsAttention {
            menuChildren.append(photoMatchingAction)
        }
        menuChildren.append(startNavigationMenu)
        menuChildren.append(UIMenu(
            title: AppLocalization.text(.mapStyle),
            image: UIImage(systemName: "map"),
            children: mapStyleActions
        ))
        var toolActions: [UIMenuElement] = []
        if !workout.isMergedRouteCollectionSource {
            toolActions.append(mergeRouteAction)
        }
        toolActions.append(exportGPXAction)

        menuChildren.append(UIMenu(
            title: AppLocalization.text(.tools),
            image: UIImage(systemName: "wrench.and.screwdriver"),
            children: toolActions
        ))

        return UIMenu(
            title: "",
            children: menuChildren
        )
    }

    private func presentRouteMergeSelection() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await ProSubscriptionManager.shared.ensureAccessResolved()
            guard ProSubscriptionManager.shared.isProUser else {
                dismissPanelSheetForNavigation { [weak self] in
                    self?.presentProPaywall { [weak self] in
                        self?.presentRouteMergeSelectionUnlocked()
                    }
                }
                return
            }

            dismissPanelSheetForNavigation { [weak self] in
                self?.presentRouteMergeSelectionUnlocked()
            }
        }
    }

    private func presentRouteMergeSelectionUnlocked() {
        let initialMergeSourceWorkouts = providedMergeSourceWorkouts?.isEmpty == false
            ? providedMergeSourceWorkouts
            : nil
        let selectionViewController = RouteMergeSelectionViewController(
            workouts: initialMergeSourceWorkouts,
            currentWorkout: workout
        )
        let navigationController = UINavigationController(rootViewController: selectionViewController)
        selectionViewController.onMergeCompleted = { [weak self, weak navigationController] _ in
            guard let self else {
                return
            }

            navigationController?.dismiss(animated: true) {
                self.presentRouteMergeCompletedAlert()
            }
        }

        navigationController.modalPresentationStyle = .pageSheet
        if let sheetPresentationController = navigationController.sheetPresentationController {
            sheetPresentationController.detents = [.large()]
            sheetPresentationController.selectedDetentIdentifier = .large
            sheetPresentationController.prefersGrabberVisible = true
            sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = true
            sheetPresentationController.preferredCornerRadius = 28
        }
        modalPresentationHost.present(navigationController, animated: true) { [weak self, weak selectionViewController] in
            guard initialMergeSourceWorkouts == nil else {
                return
            }

            self?.loadRouteMergeSourceWorkouts(
                onBatch: { workouts in
                    selectionViewController?.appendSourceWorkouts(workouts)
                },
                completion: {
                    selectionViewController?.finishLoadingSourceWorkouts()
                }
            )
        }
    }

    private func loadRouteMergeSourceWorkouts(
        onBatch: @escaping ([TrackedWorkout]) -> Void,
        completion: @escaping () -> Void
    ) {
        if let providedMergeSourceWorkouts, !providedMergeSourceWorkouts.isEmpty {
            onBatch(providedMergeSourceWorkouts)
            completion()
            return
        }

        routeMergeSourceLoadQueue.async { [weak self] in
            let cacheStore = WorkoutCacheStore()
            cacheStore.loadProgressively(
                batchSize: 32,
                shouldContinue: { [weak self] in
                    self?.hasPreparedForPermanentDismissal == false
                },
                onBatch: { workouts in
                    DispatchQueue.main.async {
                        onBatch(workouts)
                    }
                }
            )
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    private func presentRouteMergeCompletedAlert() {
        let alertController = UIAlertController(
            title: AppLocalization.text(.routeMergeCompletedTitle),
            message: AppLocalization.text(.routeMergeCompletedMessage),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.cancel), style: .cancel))
        alertController.addAction(UIAlertAction(
            title: AppLocalization.text(.routeMergeViewRoutes),
            style: .default
        ) { [weak self] _ in
            self?.showRouteCollection()
        })
        modalPresentationHost.present(alertController, animated: true)
    }

    private func showRouteCollection() {
        dismissPanelSheetForNavigation { [weak self] in
            let routeCollectionViewController = RouteCollectionViewController()
            self?.navigationController?.pushViewController(routeCollectionViewController, animated: true)
        }
    }

    private func showRouteShare() {
        dismissPanelSheetForNavigation { [weak self] in
            guard let self else {
                return
            }

            let shareViewController = WorkoutRouteShareViewController(
                workout: self.workout,
                initialMediaItems: self.routeMediaItems
            )
            self.navigationController?.pushViewController(shareViewController, animated: true)
        }
    }

    func showRouteMediaBrowser(at index: Int) {
        guard routeMediaItems.indices.contains(index) else {
            return
        }

        let mediaItems = routeMediaItems
        hidePanelSheetForImmediateNavigation { [weak self] in
            let browser = RouteMediaBrowserViewController(mediaItems: mediaItems, initialIndex: index)
            self?.navigationController?.pushViewController(browser, animated: true)
        }
    }

    private func refreshMoreMenuForPhotoAuthorizationState(reloadMediaIfAuthorizationJustGranted: Bool = true) {
        guard presentationMode == .workout, !isDemoMode else {
            navigationItem.rightBarButtonItem = makeMoreBarButtonItem()
            return
        }

        let currentState = PhotoLibraryAuthorizationManager.authorizationState
        navigationItem.rightBarButtonItem = makeMoreBarButtonItem()

        if reloadMediaIfAuthorizationJustGranted,
           lastObservedPhotoAuthorizationState != .authorized,
           currentState == .authorized,
           routeMediaItems.isEmpty {
            loadRouteMedia()
        }
        lastObservedPhotoAuthorizationState = currentState
        applyRouteMediaVisibilityPreference()
    }

    private func presentPhotoLibrarySettingsAlert() {
        let alertController = UIAlertController(
            title: AppLocalization.text(.photoLibraryFullAccessRequiredTitle),
            message: AppLocalization.text(.photoLibraryFullAccessRequiredMessage),
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
        modalPresentationHost.present(alertController, animated: true)
    }

    private func makeNavigationTitleView() -> UIView {
        navigationTitleStackView.axis = .vertical
        navigationTitleStackView.alignment = .center
        navigationTitleStackView.spacing = 1
        navigationTitleStackView.isLayoutMarginsRelativeArrangement = false
        navigationTitleStackView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        navigationTitleStackView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        navigationTitleLabel.attributedText = navigationTitleText(AppLocalization.text(.queryingLocation))
        navigationTitleLabel.textAlignment = .center
        navigationTitleLabel.lineBreakMode = .byTruncatingTail
        navigationTitleLabel.adjustsFontSizeToFitWidth = true
        navigationTitleLabel.minimumScaleFactor = 0.82
        navigationTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        navigationTitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        navigationSubtitleLabel.text = navigationWorkoutDateText()
        navigationSubtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        navigationSubtitleLabel.textColor = .secondaryLabel
        navigationSubtitleLabel.textAlignment = .center
        navigationSubtitleLabel.lineBreakMode = .byTruncatingTail
        navigationSubtitleLabel.adjustsFontSizeToFitWidth = true
        navigationSubtitleLabel.minimumScaleFactor = 0.86
        navigationSubtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        navigationSubtitleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        navigationTitleStackView.addArrangedSubview(navigationTitleLabel)
        navigationTitleStackView.addArrangedSubview(navigationSubtitleLabel)
        navigationTitleStackView.sizeToFit()
        return navigationTitleStackView
    }

    private func navigationTitleText(_ titleText: String) -> NSAttributedString {
        NSAttributedString(
            string: titleText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: UIColor.label
            ]
        )
    }

    private func loadRouteLocationTitle() {
        let resolver = WorkoutRouteLocationResolver.shared
        if let cachedLocation = resolver.cachedResolvedLocation(for: workout) {
            let title = navigationDisplayTitle(for: cachedLocation)
            resolvedNavigationTitle = title
            updateNavigationLocationTitle(title)
            return
        }

        resolver.resolveLocation(for: workout) { [weak self] location in
            guard let self else {
                return
            }

            let title = location.map(navigationDisplayTitle(for:)) ?? AppLocalization.text(.unknownLocation)
            resolvedNavigationTitle = title
            updateNavigationLocationTitle(title)
        }
    }

    private func updateNavigationLocationTitle(_ title: String) {
        navigationTitleLabel.attributedText = navigationTitleText(title)
        navigationSubtitleLabel.text = navigationWorkoutDateText()
        navigationTitleStackView.sizeToFit()
    }

    private func navigationWorkoutDateText() -> String {
        workout.navigationDateText
    }

    private func navigationDisplayTitle(for location: WorkoutRouteResolvedLocation) -> String {
        let cityName = (location.locality ?? location.subAdministrativeArea ?? location.administrativeArea)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let placeName = location.title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let cityName, !cityName.isEmpty else {
            return placeName
        }

        let placeNameWithoutCity: String
        if placeName.hasPrefix(cityName) {
            placeNameWithoutCity = String(placeName.dropFirst(cityName.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            placeNameWithoutCity = placeName
        }

        guard !placeNameWithoutCity.isEmpty else {
            return cityName
        }

        return "\(cityName) \(placeNameWithoutCity)"
    }

    private func configureDefaultNavigationBar() {
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

    private func configureMapView() {
        mapView.delegate = self
        AppMapStyle.apply(selectedMapStyle, to: mapView)
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false

        view.addSubview(mapContainerView)

        mapContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        AppMapStyle.setToneOverlay(
            mapToneOverlay,
            visible: selectedMapStyle == .appDefault,
            on: mapView
        )
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

    private func configureMapControlButtons() {
        mapControlStackView.axis = .vertical
        mapControlStackView.alignment = .fill
        mapControlStackView.distribution = .fill
        mapControlStackView.spacing = mapControlButtonSpacing

        routeSlopeVisibilityButton.overrideUserInterfaceStyle = .light
        routeSlopeVisibilityButton.accessibilityLabel = AppLocalization.text(.routeSlope)
        routeSlopeVisibilityIconView.overrideUserInterfaceStyle = .light
        routeSlopeVisibilityIconView.isUserInteractionEnabled = false
        routeSlopeVisibilityIconView.contentMode = .scaleAspectFit
        routeSlopeVisibilityIconView.image = UIImage(
            systemName: "mountain.2.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )?.withRenderingMode(.alwaysTemplate)
        routeSlopeVisibilityIconView.layer.zPosition = 1
        routeSlopeVisibilityButton.addTarget(
            self,
            action: #selector(handleRouteSlopeVisibilityButtonTap),
            for: .touchUpInside
        )
        applyMapControlButtonShadow(to: routeSlopeVisibilityButton)
        updateRouteSlopeVisibilityButtonAppearance()

        routeMediaVisibilityButton.isHidden = presentationMode != .workout || isDemoMode
        routeMediaVisibilityButton.overrideUserInterfaceStyle = .light
        routeMediaVisibilityButton.accessibilityLabel = AppLocalization.text(.photoMatching)
        routeMediaVisibilityIconView.overrideUserInterfaceStyle = .light
        routeMediaVisibilityIconView.isUserInteractionEnabled = false
        routeMediaVisibilityIconView.contentMode = .scaleAspectFit
        routeMediaVisibilityIconView.image = UIImage(
            systemName: "photo.on.rectangle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )?.withRenderingMode(.alwaysTemplate)
        routeMediaVisibilityIconView.layer.zPosition = 1
        routeMediaVisibilityButton.addTarget(
            self,
            action: #selector(handleRouteMediaVisibilityButtonTap),
            for: .touchUpInside
        )
        applyMapControlButtonShadow(to: routeMediaVisibilityButton)
        updateRouteMediaVisibilityButtonAppearance()

        view.addSubview(mapControlStackView)
        mapControlStackView.addArrangedSubview(routeSlopeVisibilityButton)
        mapControlStackView.addArrangedSubview(routeMediaVisibilityButton)
        routeSlopeVisibilityButton.addSubview(routeSlopeVisibilityIconView)
        routeMediaVisibilityButton.addSubview(routeMediaVisibilityIconView)

        mapControlStackView.snp.makeConstraints { make in
            make.trailing.equalTo(view.safeAreaLayoutGuide.snp.trailing).inset(18)
            mapControlStackViewBottomConstraint = make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
                .inset(mapControlStackViewBottomInset)
                .constraint
            make.width.equalTo(48)
        }

        routeSlopeVisibilityButton.snp.makeConstraints { make in
            make.height.equalTo(48).priority(.high)
        }

        routeMediaVisibilityButton.snp.makeConstraints { make in
            make.height.equalTo(48).priority(.high)
        }

        routeSlopeVisibilityIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(22)
        }

        routeMediaVisibilityIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(22)
        }
    }

    private func applyMapControlButtonShadow(to button: UIButton) {
        button.layer.shadowColor = UIColor.black.cgColor
        if #available(iOS 26.0, *) {
            button.layer.shadowOpacity = 0
            button.layer.shadowRadius = 0
            button.layer.shadowOffset = .zero
        } else {
            button.layer.shadowOpacity = 0.14
            button.layer.shadowRadius = 12
            button.layer.shadowOffset = CGSize(width: 0, height: 4)
        }
    }

    private func updateRouteSlopeVisibilityButtonAppearance() {
        let isAvailable = routeSlopeGradient != nil
        routeSlopeVisibilityButton.isEnabled = isAvailable
        // Keep the glass/filled background neutral, matching the photo button.
        routeSlopeVisibilityButton.isSelected = false
        if isRouteSlopeVisible {
            routeSlopeVisibilityButton.accessibilityTraits.insert(.selected)
        } else {
            routeSlopeVisibilityButton.accessibilityTraits.remove(.selected)
        }
        let foregroundColor: UIColor
        if isRouteSlopeVisible {
            foregroundColor = AppColors.movinnGreen
        } else {
            foregroundColor = UIColor.black.withAlphaComponent(isAvailable ? 0.42 : 0.22)
        }
        let resolvedForegroundColor = foregroundColor.resolvedColor(with: traitCollection)
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .filled()
            configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.92)
        }
        configuration.image = nil
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        routeSlopeVisibilityButton.configuration = configuration
        routeSlopeVisibilityButton.tintColor = resolvedForegroundColor
        routeSlopeVisibilityIconView.tintColor = resolvedForegroundColor
        routeSlopeVisibilityButton.accessibilityValue = nil
        routeSlopeVisibilityButton.accessibilityHint = isAvailable
            ? AppLocalization.text(isRouteSlopeVisible ? .disable : .enable)
            : nil
    }

    private func updateRouteMediaVisibilityButtonAppearance() {
        let isVisible = canDisplayRouteMediaAnnotations
        let foregroundColor = routeMediaVisibilityButtonForegroundColor(isVisible: isVisible)
        let resolvedForegroundColor = foregroundColor.resolvedColor(with: traitCollection)
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .filled()
            configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(0.92)
        }
        configuration.image = nil
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        routeMediaVisibilityButton.configuration = configuration
        routeMediaVisibilityButton.tintColor = resolvedForegroundColor
        routeMediaVisibilityIconView.tintColor = resolvedForegroundColor
        routeMediaVisibilityButton.accessibilityValue = AppLocalization.text(isVisible ? .enable : .disable)
    }

    private func routeMediaVisibilityButtonForegroundColor(isVisible: Bool) -> UIColor {
        if isVisible {
            return AppColors.movinnGreen
        }

        return UIColor.black.withAlphaComponent(0.42)
    }

    private var mapControlStackViewBottomInset: CGFloat {
        panelHeight(for: selectedPanelDetent) + mapControlPanelSpacing
    }

    @objc private func handleRouteSlopeVisibilityButtonTap() {
        guard routeSlopeGradient != nil else {
            return
        }

        if isRouteSlopeVisible {
            setRouteSlopeVisible(false)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await ProSubscriptionManager.shared.ensureAccessResolved()
            guard ProSubscriptionManager.shared.isProUser else {
                modalPresentationHost.presentProPaywall { [weak self] in
                    self?.setRouteSlopeVisible(true)
                }
                return
            }

            setRouteSlopeVisible(true)
        }
    }

    private func setRouteSlopeVisible(_ isVisible: Bool) {
        guard routeSlopeGradient != nil,
              isRouteSlopeVisible != isVisible else {
            return
        }

        isRouteSlopeVisible = isVisible
        replaceRouteOverlaysForSlopeVisibility()
        updateRouteSlopeVisibilityButtonAppearance()
        if isRouteSlopeVisible {
            showRouteSlopeColorHint()
        }
    }

    private func showRouteSlopeColorHint() {
        guard let window = view.window,
              RouteSlopeColorHintStore.consumeShouldShow() else {
            return
        }

        let message = AppLocalization.text(.routeSlopeColorHint)
        Toast.show(
            message,
            in: window,
            duration: 2.4,
            bottomInset: mapControlStackViewBottomInset
        )
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    @objc private func handleRouteMediaVisibilityButtonTap() {
        switch PhotoLibraryAuthorizationManager.authorizationState {
        case .authorized:
            RouteMediaVisibilityPreference.isEnabled.toggle()
            if RouteMediaVisibilityPreference.isEnabled, routeMediaItems.isEmpty {
                loadRouteMedia()
            }
            applyRouteMediaVisibilityPreference()
        case .notDetermined:
            loadRouteMedia()
        case .needsAttention:
            applyRouteMediaVisibilityPreference()
            presentPhotoLibrarySettingsAlert()
        }
    }

    private func configureRouteLoadingView() {
        routeLoadingView.isHidden = true
        routeLoadingView.alpha = 0
        routeLoadingView.layer.cornerRadius = 16
        routeLoadingView.layer.cornerCurve = .continuous
        routeLoadingView.layer.masksToBounds = true

        routeLoadingIndicator.hidesWhenStopped = true

        routeLoadingLabel.text = AppLocalization.text(.routeLoading)
        routeLoadingLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        routeLoadingLabel.textAlignment = .center
        updateLoadingViewColors()

        view.addSubview(routeLoadingView)
        routeLoadingView.contentView.addSubview(routeLoadingIndicator)
        routeLoadingView.contentView.addSubview(routeLoadingLabel)

        routeLoadingView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(view.safeAreaLayoutGuide.snp.centerY).offset(-46)
            make.width.greaterThanOrEqualTo(132)
            make.height.equalTo(72)
        }

        routeLoadingIndicator.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(13)
        }

        routeLoadingLabel.snp.makeConstraints { make in
            make.top.equalTo(routeLoadingIndicator.snp.bottom).offset(7)
            make.leading.trailing.equalToSuperview().inset(14)
        }
    }

    private func configureGPXExportLoadingView() {
        gpxExportLoadingView.isHidden = true
        gpxExportLoadingView.alpha = 0
        gpxExportLoadingView.layer.cornerRadius = 16
        gpxExportLoadingView.layer.cornerCurve = .continuous
        gpxExportLoadingView.layer.masksToBounds = true

        gpxExportLoadingIndicator.hidesWhenStopped = true

        gpxExportLoadingLabel.text = AppLocalization.text(.gpxExporting)
        gpxExportLoadingLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        gpxExportLoadingLabel.textAlignment = .center
        updateLoadingViewColors()

        view.addSubview(gpxExportLoadingView)
        gpxExportLoadingView.contentView.addSubview(gpxExportLoadingIndicator)
        gpxExportLoadingView.contentView.addSubview(gpxExportLoadingLabel)

        gpxExportLoadingView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(view.safeAreaLayoutGuide.snp.centerY).offset(-46)
            make.width.greaterThanOrEqualTo(132)
            make.height.equalTo(72)
        }

        gpxExportLoadingIndicator.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(13)
        }

        gpxExportLoadingLabel.snp.makeConstraints { make in
            make.top.equalTo(gpxExportLoadingIndicator.snp.bottom).offset(7)
            make.leading.trailing.equalToSuperview().inset(14)
        }
    }

    private func setRouteLoadingVisible(_ isVisible: Bool) {
        routeLoadingView.layer.removeAllAnimations()

        if isVisible {
            routeLoadingView.isHidden = false
            routeLoadingIndicator.startAnimating()
            UIView.animate(withDuration: 0.18) {
                self.routeLoadingView.alpha = 1
            }
        } else {
            UIView.animate(
                withDuration: 0.18,
                animations: {
                    self.routeLoadingView.alpha = 0
                },
                completion: { _ in
                    self.routeLoadingIndicator.stopAnimating()
                    self.routeLoadingView.isHidden = true
                }
            )
        }
    }

    private func setGPXExportLoadingVisible(_ isVisible: Bool) {
        gpxExportLoadingView.layer.removeAllAnimations()

        if isVisible {
            view.bringSubviewToFront(gpxExportLoadingView)
            gpxExportLoadingView.isHidden = false
            gpxExportLoadingIndicator.startAnimating()
            UIView.animate(withDuration: 0.18) {
                self.gpxExportLoadingView.alpha = 1
            }
        } else {
            UIView.animate(
                withDuration: 0.18,
                animations: {
                    self.gpxExportLoadingView.alpha = 0
                },
                completion: { _ in
                    self.gpxExportLoadingIndicator.stopAnimating()
                    self.gpxExportLoadingView.isHidden = true
                }
            )
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
            viewController.updateLoadingViewColors()
            viewController.updatePanelAppearanceColors()
            viewController.updateRouteSlopeVisibilityButtonAppearance()
            viewController.updateRouteMediaVisibilityButtonAppearance()
            viewController.setNeedsStatusBarAppearanceUpdate()
        }
    }

    private func updateLoadingViewColors() {
        routeLoadingView.effect = UIBlurEffect(style: .systemThinMaterial)
        gpxExportLoadingView.effect = UIBlurEffect(style: .systemThinMaterial)
        routeLoadingView.contentView.backgroundColor = AppColors.background(alpha: 0.16)
        gpxExportLoadingView.contentView.backgroundColor = AppColors.background(alpha: 0.16)
        routeLoadingLabel.textColor = AppColors.foreground(alpha: 0.72)
        gpxExportLoadingLabel.textColor = AppColors.foreground(alpha: 0.72)
    }

    private func applyMapStyle(_ style: AppMapDisplayStyle) {
        guard style != selectedMapStyle else {
            return
        }

        selectedMapStyle = style
        AppMapDisplayStyleStore.shared.setRouteDetailStyle(style)
        AppMapStyle.apply(style, to: mapView)
        AppMapStyle.setToneOverlay(mapToneOverlay, visible: style == .appDefault, on: mapView)
        refreshRouteOverlayStrokeColor()
        navigationItem.rightBarButtonItem = makeMoreBarButtonItem()
    }

    private enum RouteEndpoint {
        case start
        case end

        var notFoundTextKey: AppTextKey {
            switch self {
            case .start:
                return .startNotFound
            case .end:
                return .endNotFound
            }
        }

        var titleTextKey: AppTextKey {
            switch self {
            case .start:
                return .workoutStart
            case .end:
                return .workoutEnd
            }
        }
    }

    private func openEndpointInMaps(kind: RouteEndpoint) {
        let coordinates = workout.routeDetailDisplayCoordinates
        let fallbackCoordinates = workout.routeDetailCoordinates.map(\.coordinate)
        let coordinate: CLLocationCoordinate2D?
        switch kind {
        case .start:
            coordinate = Self.displayEndpointCoordinate(workout.routeCollectionMergeStartCoordinate)
                ?? coordinates.first
                ?? fallbackCoordinates.first
        case .end:
            coordinate = Self.displayEndpointCoordinate(workout.routeCollectionMergeEndCoordinate)
                ?? coordinates.last
                ?? fallbackCoordinates.last
        }

        guard let coordinate else {
            showAlert(title: AppLocalization.text(kind.notFoundTextKey))
            return
        }

        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = AppLocalization.text(kind.titleTextKey)

        let launchOptions: [String: Any] = [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(
                mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        ]

        guard mapItem.openInMaps(launchOptions: launchOptions) else {
            showAlert(title: AppLocalization.text(.systemMapsNotFound))
            return
        }
    }

    private func startRouteBookMode() {
        let selectedWorkout = workout
        dismissPanelSheetForNavigation { [weak self] in
            guard let self else {
                return
            }

            self.navigationController?.popToRootViewController(animated: true)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: RouteBookMode.didSelectWorkoutNotification,
                    object: self,
                    userInfo: [RouteBookMode.workoutUserInfoKey: selectedWorkout]
                )
            }
        }
    }

    private func exportGPX() {
        guard !isExportingGPX else {
            return
        }

        isExportingGPX = true
        navigationItem.rightBarButtonItem = makeMoreBarButtonItem()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.beginGPXExport()
        }
    }

    private func beginGPXExport() {
        guard isExportingGPX else {
            return
        }

        setGPXExportLoadingVisible(true)

        let routeName = AppLocalization.text(.gpxExportRouteName)
        let coordinates = workout.routeDetailCoordinates
        let segmentStartIndices = workout.routeDetailSegmentStartIndices
        let fileName = GPXRouteExporter.suggestedFileName(routeName: routeName)

        gpxExportQueue.async { [weak self, routeName, coordinates, segmentStartIndices, fileName] in
            let result: Result<URL, Error>
            do {
                let data = try GPXRouteExporter.data(
                    routeName: routeName,
                    coordinates: coordinates,
                    segmentStartIndices: segmentStartIndices
                )
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try data.write(to: fileURL, options: .atomic)
                result = .success(fileURL)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                guard let self,
                      !self.hasPreparedForPermanentDismissal else {
                    if case let .success(fileURL) = result {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                    return
                }

                self.isExportingGPX = false
                self.navigationItem.rightBarButtonItem = self.makeMoreBarButtonItem()
                self.setGPXExportLoadingVisible(false)
                self.handleGPXExportResult(result)
            }
        }
    }

    private func handleGPXExportResult(_ result: Result<URL, Error>) {
        switch result {
        case let .success(fileURL):
            let activityViewController = UIActivityViewController(
                activityItems: [fileURL],
                applicationActivities: nil
            )
            activityViewController.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
            activityViewController.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: fileURL)
            }
            modalPresentationHost.present(activityViewController, animated: true)
        case let .failure(error):
            showAlert(title: AppLocalization.text(.gpxExportFailed), message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String? = nil) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .default))
        modalPresentationHost.present(alertController, animated: true)
    }

    private func configurePanelView() {
        let caloriesKilocalories = panelCaloriesKilocalories
        let isRouteCollectionPanel = presentationMode == .routeCollection

        panelSheetViewController.view.backgroundColor = .clear
        panelSheetViewController.view.isOpaque = false
        panelSheetViewController.modalPresentationStyle = .pageSheet
        panelSheetViewController.isModalInPresentation = true

        panelView.backgroundColor = .clear
        panelView.layer.cornerRadius = 0
        panelView.layer.masksToBounds = true
        panelView.layer.borderWidth = 0
        if #available(iOS 26.0, *) {
            panelView.contentView.backgroundColor = .clear
        } else {
            panelView.contentView.backgroundColor = AppColors.background(alpha: 0.08)
        }

        iconView.image = UIImage(systemName: workout.symbolName)
        iconView.tintColor = AppColors.foreground(alpha: 0.9)
        iconView.contentMode = .scaleAspectFit
        iconView.isHidden = isRouteCollectionPanel
        titleStackView.isHidden = isRouteCollectionPanel

        updatePanelText()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = AppColors.foreground(alpha: 0.92)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        dataSourceLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        dataSourceLabel.textColor = UIColor.secondaryLabel
        dataSourceLabel.numberOfLines = 1
        dataSourceLabel.lineBreakMode = .byTruncatingTail

        titleStackView.axis = .vertical
        titleStackView.alignment = .leading
        titleStackView.spacing = 1

        let distanceFont = UIFont.preferredFont(forTextStyle: .headline)
        let durationFont = UIFont.systemFont(
            ofSize: max(distanceFont.pointSize - 3, 11),
            weight: .semibold
        )

        metricsStackView.axis = isRouteCollectionPanel ? .horizontal : .vertical
        metricsStackView.alignment = isRouteCollectionPanel ? .center : .trailing
        metricsStackView.distribution = .fill
        metricsStackView.spacing = isRouteCollectionPanel ? 12 : 2

        distanceLabel.font = distanceFont
        distanceLabel.textColor = AppColors.foreground(alpha: 0.92)
        distanceLabel.textAlignment = .right
        distanceLabel.adjustsFontSizeToFitWidth = true
        distanceLabel.minimumScaleFactor = 0.78
        distanceLabel.numberOfLines = 1

        durationLabel.font = durationFont
        durationLabel.textColor = UIColor.secondaryLabel
        durationLabel.textAlignment = .right
        durationLabel.adjustsFontSizeToFitWidth = true
        durationLabel.minimumScaleFactor = 0.78
        durationLabel.numberOfLines = 1

        detailStackView.axis = .vertical
        detailStackView.spacing = caloriesKilocalories == nil ? 0 : calorieRiceTopSpacing
        detailStackView.alpha = 1

        replayRulerView.configure(
            totalDistanceText: replayTotalDistanceText(totalMeters: workout.distanceMeters),
            totalDistanceMeters: workout.distanceMeters
        )
        replayRulerView.addTarget(self, action: #selector(handleReplayProgressChanged(_:)), for: .valueChanged)

        detailStackView.addArrangedSubview(replayRulerView)
        if let caloriesKilocalories {
            calorieRiceView.configure(
                caloriesKilocalories: caloriesKilocalories,
                isEstimated: panelCaloriesIsEstimated
            )
            detailStackView.addArrangedSubview(calorieRiceView)
        }

        panelSheetViewController.view.addSubview(panelView)
        panelView.contentView.addSubview(handleTouchView)
        panelView.contentView.addSubview(iconView)
        panelView.contentView.addSubview(titleStackView)
        panelView.contentView.addSubview(metricsStackView)
        panelView.contentView.addSubview(detailStackView)
        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(dataSourceLabel)
        if isRouteCollectionPanel {
            let metricsSpacerView = UIView()
            metricsSpacerView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            metricsSpacerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            distanceLabel.setContentHuggingPriority(.required, for: .horizontal)
            metricsStackView.addArrangedSubview(distanceLabel)
            metricsStackView.addArrangedSubview(metricsSpacerView)
        } else {
            metricsStackView.addArrangedSubview(distanceLabel)
            metricsStackView.addArrangedSubview(durationLabel)
        }

        panelView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        handleTouchView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(panelHandleTouchHeight)
        }

        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            primaryContentTopConstraint = make.top.equalTo(handleTouchView.snp.bottom)
                .offset(primaryContentTopOffset(for: panelHeight(for: .minimum)))
                .constraint
            make.size.equalTo(presentationMode == .routeCollection ? 0 : primaryContentSize)
        }

        titleStackView.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(isRouteCollectionPanel ? 0 : 10)
            make.centerY.equalTo(iconView)
            if isRouteCollectionPanel {
                make.trailing.lessThanOrEqualToSuperview().inset(18)
            } else {
                make.trailing.lessThanOrEqualTo(metricsStackView.snp.leading).offset(-12)
            }
        }

        metricsStackView.snp.makeConstraints { make in
            if isRouteCollectionPanel {
                make.leading.equalToSuperview().offset(18)
            }
            make.trailing.equalToSuperview().inset(18)
            make.centerY.equalTo(iconView)
        }

        detailStackView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(18)
            make.top.equalTo(iconView.snp.bottom).offset(detailContentTopSpacing)
        }

        replayRulerView.snp.makeConstraints { make in
            make.height.equalTo(replayRulerViewHeight)
        }

        if caloriesKilocalories != nil {
            calorieRiceView.snp.makeConstraints { make in
                make.height.equalTo(calorieRiceViewHeight)
            }
        }

        applyPanelSheetDetent(.minimum, animated: false)
    }

    private func updatePanelAppearanceColors() {
        if #available(iOS 26.0, *) {
            panelView.contentView.backgroundColor = .clear
        } else {
            panelView.contentView.backgroundColor = AppColors.background(alpha: 0.08)
        }
        iconView.tintColor = AppColors.foreground(alpha: 0.9)
        titleLabel.textColor = AppColors.foreground(alpha: 0.92)
        distanceLabel.textColor = AppColors.foreground(alpha: 0.92)
    }

    private func presentPanelSheetIfNeeded() {
        guard !hasPresentedPanelSheet,
              presentedViewController == nil,
              view.window != nil else {
            return
        }

        if let sheetPresentationController = panelSheetViewController.sheetPresentationController {
            sheetPresentationController.detents = [
                .custom(identifier: Self.minimumPanelDetentIdentifier) { [weak self] _ in
                    self?.panelHeight(for: .minimum) ?? 68
                },
                .custom(identifier: Self.mediumPanelDetentIdentifier) { [weak self] _ in
                    self?.panelHeight(for: .medium) ?? 200
                }
            ]
            sheetPresentationController.selectedDetentIdentifier = Self.minimumPanelDetentIdentifier
            sheetPresentationController.largestUndimmedDetentIdentifier = Self.mediumPanelDetentIdentifier
            sheetPresentationController.prefersGrabberVisible = true
            sheetPresentationController.prefersScrollingExpandsWhenScrolledToEdge = false
            sheetPresentationController.preferredCornerRadius = 28
            sheetPresentationController.delegate = self
        }

        hasPresentedPanelSheet = true
        present(panelSheetViewController, animated: false)
    }

    private var modalPresentationHost: UIViewController {
        if presentedViewController === panelSheetViewController {
            return panelSheetViewController
        }

        return self
    }

    private func dismissPanelSheetForNavigation(_ completion: @escaping () -> Void) {
        guard presentedViewController === panelSheetViewController else {
            suppressPanelSheetPresentation = false
            completion()
            return
        }

        suppressPanelSheetPresentation = true
        hasPresentedPanelSheet = false
        panelSheetViewController.dismiss(animated: true) { [weak self] in
            self?.suppressPanelSheetPresentation = false
            completion()
        }
    }

    private func hidePanelSheetForImmediateNavigation(_ navigate: @escaping () -> Void) {
        guard presentedViewController === panelSheetViewController else {
            suppressPanelSheetPresentation = false
            navigate()
            return
        }

        suppressPanelSheetPresentation = true
        hasPresentedPanelSheet = false
        panelSheetViewController.dismiss(animated: false) { [weak self] in
            self?.suppressPanelSheetPresentation = false
            navigate()
        }
    }

    private func startDeferredDetailLoadingIfNeeded() {
        guard !hasStartedDeferredDetailLoading else {
            return
        }

        hasStartedDeferredDetailLoading = true
        startRouteLoadingIfNeeded()
        if presentationMode == .workout {
            loadRouteLocationTitle()
            if !isDemoMode {
                loadRouteMedia()
            }
        }
    }

    private func startRouteLoadingIfNeeded() {
        guard !hasStartedRouteLoading else {
            return
        }

        hasStartedRouteLoading = true
        setRouteLoadingVisible(true)

        let workout = workout
        let maximumElevationSampleCount = self.maximumElevationSampleCount
        let maximumDisplayCoordinateCount = self.maximumDisplayCoordinateCount
        let maximumSlopeRenderingCoordinateCount = self.maximumSlopeRenderingCoordinateCount
        let maximumSlopeSegmentCount = self.maximumSlopeSegmentCount
        let slopeSimplificationTolerance = slopeGeometrySimplificationToleranceMeters
        let cancellationToken = RouteSlopePreparationCancellationToken()
        routePreparationCancellationToken?.cancel()
        routePreparationCancellationToken = cancellationToken
        routePreparationQueue.async { [weak self] in
            let preparedRoute = Self.prepareRoute(
                for: workout,
                maximumElevationSampleCount: maximumElevationSampleCount,
                maximumDisplayCoordinateCount: maximumDisplayCoordinateCount,
                maximumSlopeRenderingCoordinateCount: maximumSlopeRenderingCoordinateCount,
                maximumSlopeSegmentCount: maximumSlopeSegmentCount,
                slopeGeometrySimplificationToleranceMeters: slopeSimplificationTolerance,
                cancellationToken: cancellationToken
            )
            guard !cancellationToken.isCancelled else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.routePreparationCancellationToken === cancellationToken,
                      !self.hasPreparedForPermanentDismissal else {
                    return
                }
                self.routePreparationCancellationToken = nil

                guard let preparedRoute else {
                    self.setRouteLoadingVisible(false)
                    return
                }

                self.applyPreparedRoute(preparedRoute)
            }
        }
    }

    private static func prepareRoute(
        for workout: TrackedWorkout,
        maximumElevationSampleCount: Int,
        maximumDisplayCoordinateCount: Int,
        maximumSlopeRenderingCoordinateCount: Int,
        maximumSlopeSegmentCount: Int,
        slopeGeometrySimplificationToleranceMeters: CLLocationDistance,
        cancellationToken: RouteSlopePreparationCancellationToken
    ) -> PreparedRoute? {
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
        var replayHeartRates: [Double?] = []
        var replayPowers: [Double?] = []
        var replayTemperatures: [Double?] = []
        var slopeAltitudes: [Double?] = []
        var sourceDistances: [CLLocationDistance?] = []
        var sourceGradeRatios: [Double?] = []
        sourceCoordinates.reserveCapacity(routeCoordinates.count)
        replayAltitudes.reserveCapacity(routeCoordinates.count)
        replayHeartRates.reserveCapacity(routeCoordinates.count)
        replayPowers.reserveCapacity(routeCoordinates.count)
        replayTemperatures.reserveCapacity(routeCoordinates.count)
        slopeAltitudes.reserveCapacity(routeCoordinates.count)
        sourceDistances.reserveCapacity(routeCoordinates.count)
        sourceGradeRatios.reserveCapacity(routeCoordinates.count)
        for (index, routeCoordinate) in routeCoordinates.enumerated() {
            if index.isMultiple(of: 256), cancellationToken.isCancelled {
                return nil
            }

            sourceCoordinates.append(routeCoordinate.coordinate)
            replayAltitudes.append(routeCoordinate.altitudeMeters)
            replayHeartRates.append(routeCoordinate.heartRateBeatsPerMinute)
            replayPowers.append(routeCoordinate.powerWatts)
            replayTemperatures.append(routeCoordinate.temperatureCelsius)
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
        let replayDistances = cumulativeDistances(
            for: coordinates,
            segmentStartIndices: segmentStartIndices,
            cancellationToken: cancellationToken
        ) else {
            return nil
        }

        let measuredDistance = replayDistances.last ?? workout.distanceMeters
        let totalDistanceMeters = workout.distanceMeters > 0 ? workout.distanceMeters : measuredDistance
        guard let slopeData = preparedSlopeData(
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
        ),
        let replayGradeRatios = replayGradeRatios(
            for: replayDistances,
            profileSegments: slopeData.profileSegments,
            cancellationToken: cancellationToken
        ) else {
            return nil
        }
        guard let elevationSamples = routeElevationSamples(
            distances: replayDistances,
            altitudes: replayAltitudes,
            heartRates: replayHeartRates,
            powers: replayPowers,
            temperatures: replayTemperatures,
            seriesBreakIndices: segmentStartIndices,
            maximumCount: maximumElevationSampleCount,
            isCancelled: { cancellationToken.isCancelled }
        ) else {
            return nil
        }
        guard let globalPeakSamples = routeElevationGlobalPeakSamples(
            distances: replayDistances,
            altitudes: replayAltitudes,
            heartRates: replayHeartRates,
            powers: replayPowers,
            temperatures: replayTemperatures,
            steepestUphill: slopeData.steepestUphill,
            seriesBreakIndices: segmentStartIndices,
            elevationSamples: elevationSamples,
            isCancelled: { cancellationToken.isCancelled }
        ) else {
            return nil
        }

        guard let viewportGeometry = RouteViewportDistanceResolver.prepareGeometry(
            coordinates: coordinates,
            cumulativeDistances: replayDistances,
            segmentStartIndices: segmentStartIndices,
            isCancelled: { cancellationToken.isCancelled }
        ) else {
            return nil
        }
        guard let displayGeometry = RouteViewportDistanceResolver.prepareGeometry(
            coordinates: coordinates,
            cumulativeDistances: replayDistances,
            segmentStartIndices: segmentStartIndices,
            maximumCount: max(maximumDisplayCoordinateCount, 4_096),
            toleranceMeters: slopeGeometrySimplificationToleranceMeters,
            allowsSinglePointRepresentatives: false,
            isCancelled: { cancellationToken.isCancelled }
        ) else {
            return nil
        }
        guard let boundingMapRect = RouteViewportDistanceResolver.boundingMapRect(
            for: coordinates,
            isCancelled: { cancellationToken.isCancelled }
        ) else {
            return nil
        }
        guard !cancellationToken.isCancelled else {
            return nil
        }

        return PreparedRoute(
            coordinates: coordinates,
            viewportGeometry: viewportGeometry,
            displayGeometry: displayGeometry,
            slopeSegments: slopeData.renderingSegments,
            routeCoordinates: routeCoordinates,
            boundingMapRect: boundingMapRect,
            startCoordinate: displayEndpointCoordinate(workout.routeCollectionMergeStartCoordinate)
                ?? coordinates[0],
            endCoordinate: displayEndpointCoordinate(workout.routeCollectionMergeEndCoordinate)
                ?? coordinates[coordinates.count - 1],
            replayDistances: replayDistances,
            replayAltitudes: replayAltitudes,
            replayHeartRates: replayHeartRates,
            replayPowers: replayPowers,
            replayTemperatures: replayTemperatures,
            replayGradeRatios: replayGradeRatios,
            replaySegmentStartIndices: segmentStartIndices,
            elevationSamples: elevationSamples,
            globalPeakSamples: globalPeakSamples,
            totalDistanceMeters: totalDistanceMeters
        )
    }

    private static func preparedSlopeData(
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
    ) -> PreparedSlopeData? {
        guard coordinates.count == cumulativeDistances.count,
              coordinates.count == altitudes.count,
              coordinates.count == sourceDistances.count,
              coordinates.count == sourceGradeRatios.count,
              maximumRenderingCoordinateCount > 1 else {
            return PreparedSlopeData(
                renderingSegments: [],
                profileSegments: [],
                steepestUphill: nil
            )
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
                guard bounds.1 - bounds.0 > 1 else {
                    return nil
                }
                return (segmentIndex, bounds.0, bounds.1)
            }
        let maximumSlopeSegmentCount = min(
            max(maximumSegmentCount, 1),
            max(maximumRenderingCoordinateCount / 2, 1)
        )
        var validCandidates: [(
            segmentIndex: Int,
            lowerBound: Int,
            upperBound: Int,
            totalDistance: CLLocationDistance,
            gradient: RouteSlopeGradient
        )] = []
        validCandidates.reserveCapacity(
            min(allSegmentRanges.count, maximumSlopeSegmentCount * 2)
        )
        var profileSegments: [PreparedSlopeProfileSegment] = []
        profileSegments.reserveCapacity(allSegmentRanges.count)
        var steepestUphill: RouteSlopePeak?
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
                  let analysis = RouteSlopeGradient.analyze(
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
            profileSegments.append(PreparedSlopeProfileSegment(
                baseDistance: baseDistance,
                endDistance: baseDistance + totalDistance,
                analysis: analysis
            ))
            if let localPeak = analysis.steepestUphill {
                let globalPeak = RouteSlopePeak(
                    distanceMeters: baseDistance + localPeak.distanceMeters,
                    altitudeMeters: localPeak.altitudeMeters,
                    gradeRatio: localPeak.gradeRatio
                )
                if steepestUphill == nil
                    || globalPeak.gradeRatio > (steepestUphill?.gradeRatio
                        ?? -.greatestFiniteMagnitude) {
                    steepestUphill = globalPeak
                }
            }
            validCandidates.append((
                segmentIndex: segmentRange.segmentIndex,
                lowerBound: segmentRange.lowerBound,
                upperBound: segmentRange.upperBound,
                totalDistance: totalDistance,
                gradient: analysis.gradient
            ))
        }
        let selectedCandidates = validCandidates
            .sorted { lhs, rhs in
                if lhs.totalDistance != rhs.totalDistance {
                    return lhs.totalDistance > rhs.totalDistance
                }
                return lhs.segmentIndex < rhs.segmentIndex
            }
            .prefix(maximumSlopeSegmentCount)
            .sorted { $0.segmentIndex < $1.segmentIndex }
        let totalPointCount = selectedCandidates.reduce(0) {
            $0 + ($1.upperBound - $1.lowerBound)
        }
        guard totalPointCount > 1 else {
            return PreparedSlopeData(
                renderingSegments: [],
                profileSegments: profileSegments,
                steepestUphill: steepestUphill
            )
        }

        var result: [PreparedSlopeSegment] = []
        result.reserveCapacity(selectedCandidates.count)
        var remainingRenderingBudget = maximumRenderingCoordinateCount
        var remainingPointCount = totalPointCount
        for (segmentOffset, segmentRange) in selectedCandidates.enumerated() {
            if cancellationToken.isCancelled {
                return nil
            }
            let lowerBound = segmentRange.lowerBound
            let upperBound = segmentRange.upperBound
            let baseDistance = cumulativeDistances[lowerBound]
            let segmentDistances = cumulativeDistances[lowerBound..<upperBound].map {
                $0 - baseDistance
            }

            let pointCount = upperBound - lowerBound
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
            guard let geometry = RouteSlopeGeometryPreparer.prepare(
                coordinates: Array(coordinates[lowerBound..<upperBound]),
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
            result.append(PreparedSlopeSegment(
                segmentIndex: segmentRange.segmentIndex,
                coordinates: geometry.coordinates,
                sourceLocations: geometry.sourceLocations,
                gradient: segmentRange.gradient,
                totalDistance: segmentRange.totalDistance
            ))
        }
        guard !cancellationToken.isCancelled else {
            return nil
        }
        return PreparedSlopeData(
            renderingSegments: result,
            profileSegments: profileSegments,
            steepestUphill: steepestUphill
        )
    }

    private static func replayGradeRatios(
        for distances: [CLLocationDistance],
        profileSegments: [PreparedSlopeProfileSegment],
        cancellationToken: RouteSlopePreparationCancellationToken
    ) -> [Double?]? {
        var gradeRatios = Array<Double?>(repeating: nil, count: distances.count)
        var profileIndex = 0
        let tolerance = 0.000_001
        for index in distances.indices {
            if index.isMultiple(of: 256), cancellationToken.isCancelled {
                return nil
            }
            let distance = distances[index]
            while profileIndex < profileSegments.count,
                  distance > profileSegments[profileIndex].endDistance + tolerance {
                profileIndex += 1
            }
            guard profileIndex < profileSegments.count else {
                break
            }
            let profile = profileSegments[profileIndex]
            guard distance >= profile.baseDistance - tolerance,
                  distance <= profile.endDistance + tolerance else {
                continue
            }
            let localDistance = min(
                max(distance - profile.baseDistance, 0),
                profile.endDistance - profile.baseDistance
            )
            gradeRatios[index] = profile.analysis.gradeRatio(at: localDistance)
        }
        return cancellationToken.isCancelled ? nil : gradeRatios
    }

    private func applyPreparedRoute(_ preparedRoute: PreparedRoute) {
        guard !hasPreparedForPermanentDismissal else {
            return
        }

        configureReplayRoute(with: preparedRoute)

        routeBoundingMapRect = preparedRoute.boundingMapRect
        let displayGeometry = preparedRoute.displayGeometry
        routeDisplayPolylines = RouteViewportDistanceResolver.displayPolylines(
            coordinates: displayGeometry.coordinates,
            segmentStartIndices: displayGeometry.segmentStartIndices
        )
        configureRouteDisplayOverlayCaches()
        routeSlopeGradient = nil
        routeSlopePolylines.removeAll(keepingCapacity: true)
        routeSlopeGradients.removeAll(keepingCapacity: true)
        routeSlopeDirectionPolylines.removeAll(keepingCapacity: true)
        routeSlopeDirectionPolylineIdentifiers.removeAll(keepingCapacity: true)
        // Keep MapKit renderer count bounded: preparation already limits the
        // selected slope segments, and each selected segment receives at least
        // one chunk from this fixed budget.
        var remainingChunkCount = maximumSlopeOverlayChunkCount
        var renderedSlopeSegmentIndices = Set<Int>()
        for (index, slopeSegment) in preparedRoute.slopeSegments.enumerated() {
            guard remainingChunkCount > 0 else {
                break
            }
            let remainingSegmentCount = preparedRoute.slopeSegments.count - index
            let segmentChunkLimit = max(
                1,
                remainingChunkCount / max(remainingSegmentCount, 1)
            )
            let chunks = RouteSlopeOverlayFactory.makeChunks(
                coordinates: slopeSegment.coordinates,
                sourceLocations: slopeSegment.sourceLocations,
                gradient: slopeSegment.gradient,
                totalDistance: slopeSegment.totalDistance,
                preferredChunkDistance: preferredSlopeOverlayChunkDistance,
                maximumChunkCount: segmentChunkLimit
            )
            guard !chunks.isEmpty else {
                continue
            }
            routeSlopeGradient = routeSlopeGradient ?? slopeSegment.gradient
            renderedSlopeSegmentIndices.insert(slopeSegment.segmentIndex)
            for chunk in chunks {
                routeSlopePolylines.append(chunk.polyline)
                routeSlopeGradients[ObjectIdentifier(chunk.polyline)] = chunk.gradient
            }
            remainingChunkCount -= chunks.count
            routeSlopeDirectionPolylines.append(MKPolyline(
                coordinates: slopeSegment.coordinates,
                count: slopeSegment.coordinates.count
            ))
        }
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
        if !routeSlopePolylines.isEmpty {
            routeSlopePolylines.insert(contentsOf: uncoveredPolylines, at: 0)
            for uncoveredPolyline in uncoveredPolylines {
                routeSlopeGradients[ObjectIdentifier(uncoveredPolyline)] = .unavailable
            }
        }
        routeSlopeDirectionPolylineIdentifiers = Set(
            routeSlopeDirectionPolylines.map(ObjectIdentifier.init)
        )
        if routeSlopePolylines.isEmpty {
            routeSlopeGradient = nil
            routeSlopeDirectionPolylines.removeAll(keepingCapacity: true)
            routeSlopeDirectionPolylineIdentifiers.removeAll(keepingCapacity: true)
        }
        isRouteSlopeVisible = false
        updateRouteSlopeVisibilityButtonAppearance()
        hasFittedRoute = false
        mapView.addOverlays(routeDisplayPolylines, level: .aboveLabels)
        addRouteSlopeDirectionOverlayIfNeeded()

        mapView.addAnnotations([
            RouteEndpointAnnotation(coordinate: preparedRoute.startCoordinate, kind: .start),
            RouteEndpointAnnotation(coordinate: preparedRoute.endCoordinate, kind: .end)
        ])

        setRouteLoadingVisible(false)
        fitRouteIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !self.hasPreparedForPermanentDismissal else {
                return
            }
            self.displayRouteMediaIfRouteReady()
        }
    }

    private func fitRouteIfNeeded() {
        guard !hasFittedRoute, let routeBoundingMapRect else {
            return
        }

        hasFittedRoute = true
        mapView.setVisibleMapRect(
            routeBoundingMapRect,
            edgePadding: UIEdgeInsets(
                top: 96,
                left: 32,
                bottom: routeFitBottomPadding,
                right: 32
            ),
            animated: false
        )
    }

    private var routeFitBottomPadding: CGFloat {
        panelHeight(for: .medium) + 28 + mapBottomExtension
    }

    private var canDisplayRouteMediaAnnotations: Bool {
        presentationMode == .workout
            && !isDemoMode
            && RouteMediaVisibilityPreference.isEnabled
            && PhotoLibraryAuthorizationManager.authorizationState == .authorized
    }

    private var mapRouteStrokeColor: UIColor {
        selectedMapStyle == .dark ? .white : .black
    }

    private func configureRouteDisplayOverlayCaches() {
        routeDisplayIndicatorPolylines.removeAll(keepingCapacity: true)
        routeDisplayIndicatorBudgets.removeAll(keepingCapacity: true)
        guard !routeDisplayPolylines.isEmpty else {
            return
        }

        let maximumPolylineCount = 80
        let selectedIndices: [Int]
        if routeDisplayPolylines.count <= maximumPolylineCount {
            selectedIndices = Array(routeDisplayPolylines.indices)
        } else {
            selectedIndices = (0..<maximumPolylineCount).map { offset in
                Int(round(
                    Double(routeDisplayPolylines.count - 1) * Double(offset)
                        / Double(maximumPolylineCount - 1)
                ))
            }
        }
        let perPolylineBudget = max(80 / max(selectedIndices.count, 1), 1)
        routeDisplayIndicatorPolylines.reserveCapacity(selectedIndices.count)
        routeDisplayIndicatorBudgets.reserveCapacity(selectedIndices.count)
        for index in selectedIndices {
            let polyline = routeDisplayPolylines[index]
            routeDisplayIndicatorPolylines.append(polyline)
            routeDisplayIndicatorBudgets[ObjectIdentifier(polyline)] = perPolylineBudget
        }
    }

    func routeOverlayRenderer(for overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }
        return routeOverlayRenderer(for: polyline)
    }

    func routeOverlayRenderer(for polyline: MKPolyline) -> MKOverlayRenderer {
        let polylineIdentifier = ObjectIdentifier(polyline)
        if routeSlopeDirectionPolylineIdentifiers.contains(polylineIdentifier) {
            let renderer = makeRouteDirectionRenderer(for: polyline)
            renderer.drawsRouteStroke = false
            renderer.strokeColor = .clear
            renderer.directionIndicatorColor = .black
            renderer.directionIndicatorSpacing = 180
            renderer.maximumIndicatorCount = min(
                40,
                max(4, 48 / max(routeSlopeDirectionPolylines.count, 1))
            )
            return renderer
        }

        if let routeSlopeGradient = routeSlopeGradients[polylineIdentifier] {
            return AppMapStyle.makeSlopeRenderer(
                for: polyline,
                gradient: routeSlopeGradient,
                matchingNativeLineWidth: AppMapStyle.slopeReferenceRouteLineWidth
            )
        }

        let renderer = makeRouteDirectionRenderer(for: polyline)
        renderer.strokeColor = mapRouteStrokeColor
        renderer.directionIndicatorColor = .black
        renderer.maximumIndicatorCount = isMapRegionChanging
            ? 0
            : (routeDisplayIndicatorBudgets[polylineIdentifier] ?? 0)
        return renderer
    }

    private func makeRouteDirectionRenderer(
        for polyline: MKPolyline
    ) -> RouteDirectionPolylineRenderer {
        let renderer = RouteDirectionPolylineRenderer(polyline: polyline)
        renderer.lineWidth = AppMapStyle.routeLineWidth
        renderer.directionIndicatorLength = 14.5
        renderer.directionIndicatorWidth = 17
        renderer.directionIndicatorStrokeWidth = 3.4
        renderer.lineJoin = .round
        renderer.lineCap = .round
        return renderer
    }

    private func replaceRouteOverlaysForSlopeVisibility() {
        guard routeBoundingMapRect != nil else {
            return
        }

        let visibleOverlayIdentifiers = Set(
            mapView.overlays.map { ObjectIdentifier($0 as AnyObject) }
        )
        let visibleDirectionPolylines = routeSlopeDirectionPolylines.filter { directionPolyline in
            visibleOverlayIdentifiers.contains(ObjectIdentifier(directionPolyline))
        }
        if !visibleDirectionPolylines.isEmpty {
            mapView.removeOverlays(visibleDirectionPolylines)
        }
        let visibleRoutePolylines = routeDisplayPolylines.filter { routePolyline in
            visibleOverlayIdentifiers.contains(ObjectIdentifier(routePolyline))
        }
        if !visibleRoutePolylines.isEmpty {
            mapView.removeOverlays(visibleRoutePolylines)
        }
        let visibleSlopePolylines = routeSlopePolylines.filter { slopePolyline in
            visibleOverlayIdentifiers.contains(ObjectIdentifier(slopePolyline))
        }
        if !visibleSlopePolylines.isEmpty {
            mapView.removeOverlays(visibleSlopePolylines)
        }
        if isRouteSlopeVisible,
           !routeSlopePolylines.isEmpty {
            mapView.addOverlays(routeSlopePolylines, level: .aboveLabels)
            addRouteSlopeDirectionOverlayIfNeeded()
        } else {
            mapView.addOverlays(routeDisplayPolylines, level: .aboveLabels)
        }
    }

    private func addRouteSlopeDirectionOverlayIfNeeded() {
        guard isRouteSlopeVisible,
              !areSlopeDirectionOverlaysSuspendedForMapChange,
              !isMapRegionChanging else {
            return
        }
        let visibleOverlayIdentifiers = Set(
            mapView.overlays.map { ObjectIdentifier($0 as AnyObject) }
        )
        let missingDirectionPolylines = routeSlopeDirectionPolylines.filter { directionPolyline in
            !visibleOverlayIdentifiers.contains(ObjectIdentifier(directionPolyline))
        }
        if !missingDirectionPolylines.isEmpty {
            mapView.addOverlays(missingDirectionPolylines, level: .aboveLabels)
        }
    }

    private func refreshRouteOverlayStrokeColor() {
        if isRouteSlopeVisible {
            return
        }

        for routePolyline in routeDisplayPolylines {
            if let renderer = mapView.renderer(for: routePolyline) as? MKPolylineRenderer {
                renderer.strokeColor = mapRouteStrokeColor
                renderer.setNeedsDisplay()
            }
        }
    }

    private func loadRouteMedia() {
        mediaStore.loadMedia(for: workout) { [weak self] result in
            guard let self,
                  !self.hasPreparedForPermanentDismissal else {
                return
            }

            switch result {
            case .success(let mediaItems):
                Task { @MainActor [weak self] in
                    guard let self,
                          !self.hasPreparedForPermanentDismissal else {
                        return
                    }
                    self.removeRouteMediaAnnotations()
                    self.routeMediaItems = mediaItems
                    self.displayRouteMediaIfRouteReady()
                    self.refreshMoreMenuForPhotoAuthorizationState(reloadMediaIfAuthorizationJustGranted: false)
                }
            case .failure(let error):
                print("PTrack Photos: failed to load route media: \(error)")
                self.applyRouteMediaVisibilityPreference()
                self.refreshMoreMenuForPhotoAuthorizationState(reloadMediaIfAuthorizationJustGranted: false)
            }
        }
    }

    private func applyRouteMediaVisibilityPreference() {
        guard presentationMode == .workout else {
            return
        }

        if canDisplayRouteMediaAnnotations {
            displayRouteMediaIfRouteReady()
        } else {
            removeRouteMediaAnnotations()
        }
        updateRouteMediaVisibilityButtonAppearance()
    }

    private func displayRouteMediaIfRouteReady() {
        guard !hasPreparedForPermanentDismissal else {
            return
        }

        guard routeBoundingMapRect != nil,
              canDisplayRouteMediaAnnotations,
              !hasDisplayedRouteMediaAnnotations,
              !routeMediaItems.isEmpty else {
            return
        }

        hasDisplayedRouteMediaAnnotations = true
        mapView.addAnnotations(routeMediaItems.map(RouteMediaAnnotation.init))
        updateRouteMediaVisibilityButtonAppearance()
    }

    private func removeRouteMediaAnnotations() {
        let mediaAnnotations = mapView.annotations.compactMap { $0 as? RouteMediaAnnotation }
        guard !mediaAnnotations.isEmpty || hasDisplayedRouteMediaAnnotations else {
            updateRouteMediaVisibilityButtonAppearance()
            return
        }

        hasDisplayedRouteMediaAnnotations = false
        if !mediaAnnotations.isEmpty {
            mapView.removeAnnotations(mediaAnnotations)
        }
        updateRouteMediaVisibilityButtonAppearance()
    }

    private func panelHeight(for detent: PanelDetent) -> CGFloat {
        switch detent {
        case .minimum:
            return minimumPanelHeight
        case .medium:
            return mediumPanelContentHeight()
        }
    }

    private func mediumPanelContentHeight() -> CGFloat {
        let detailStackBottom = expandedPrimaryContentBottomY()
            + detailContentTopSpacing
            + replayRulerViewHeight
            + mediumPanelCalorieContentHeight()
        return detailStackBottom + mediumPanelBottomPadding
    }

    private func expandedPrimaryContentBottomY() -> CGFloat {
        if presentationMode == .routeCollection {
            return expandedPrimaryContentTop + primaryContentSize / 2
        }

        return expandedPrimaryContentTop + primaryContentSize
    }

    private func mediumPanelCalorieContentHeight() -> CGFloat {
        guard panelCaloriesKilocalories != nil else {
            return 0
        }

        return calorieRiceTopSpacing + calorieRiceViewHeight
    }

    private func panelDetailProgress(for height: CGFloat) -> CGFloat {
        let minimumHeight = panelHeight(for: .minimum)
        let mediumHeight = panelHeight(for: .medium)
        guard mediumHeight > minimumHeight else {
            return 1
        }

        return (height - minimumHeight) / (mediumHeight - minimumHeight)
    }

    private func primaryContentTopOffset(for height: CGFloat) -> CGFloat {
        let progress = min(max(panelDetailProgress(for: height), 0), 1)

        if presentationMode == .routeCollection {
            let minimumPrimaryContentCenterY = minimumPanelHeight / 2
            let expandedPrimaryContentCenterY = expandedPrimaryContentTop + primaryContentSize / 2
            let centerY = minimumPrimaryContentCenterY
                + (expandedPrimaryContentCenterY - minimumPrimaryContentCenterY) * progress
            return centerY - panelHandleTouchHeight
        }

        let minimumPrimaryContentTop = (minimumPanelHeight - primaryContentSize) / 2
        let top = minimumPrimaryContentTop + (expandedPrimaryContentTop - minimumPrimaryContentTop) * progress
        return top - panelHandleTouchHeight
    }

    private func updatePrimaryContentScale(for height: CGFloat) {
        let progress = min(max(panelDetailProgress(for: height), 0), 1)
        let scale = minimumPrimaryContentScale + (1 - minimumPrimaryContentScale) * progress
        let transform = CGAffineTransform(scaleX: scale, y: scale)

        iconView.transform = transform
        titleStackView.transform = transform
        metricsStackView.transform = transform
    }

    private func applyPanelSheetDetent(_ detent: PanelDetent, animated: Bool) {
        selectedPanelDetent = detent
        calorieRiceView.setImpactFeedbackEnabled(false)

        if detent == .minimum {
            removeReplayAnnotation()
            replayRulerView.setProgress(0)
        }

        let height = panelHeight(for: detent)
        primaryContentTopConstraint?.update(offset: primaryContentTopOffset(for: height))
        if animated, detent == .medium {
            // Resolve the profile against the target sheet inset before the
            // custom content animation starts, rather than jumping at its end.
            updateReplayRulerVisibleRange()
        }

        let changes = {
            self.detailStackView.alpha = 1
            self.updatePrimaryContentScale(for: height)
            self.panelSheetViewController.view.layoutIfNeeded()
            self.mapControlStackViewBottomConstraint?.update(
                inset: height + self.mapControlPanelSpacing
            )
            self.view.layoutIfNeeded()
        }

        guard animated else {
            changes()
            handlePanelDetentTransitionCompleted(for: detent)
            return
        }

        UIView.animate(
            withDuration: 0.36,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.7,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: changes,
            completion: { [weak self] _ in
                self?.handlePanelDetentTransitionCompleted(for: detent)
            }
        )
    }

    private func handlePanelDetentTransitionCompleted(for detent: PanelDetent) {
        guard selectedPanelDetent == detent else {
            return
        }
        updateReplayRulerVisibleRange()

        guard detent == .medium,
              panelCaloriesKilocalories != nil else {
            return
        }

        calorieRiceView.restartRiceFallAnimation()
        calorieRiceView.setImpactFeedbackEnabled(true)
    }

    @objc private func handleReplayProgressChanged(_ sender: WorkoutRouteReplayRulerView) {
        guard let replayState = replayState(for: sender.progress) else {
            return
        }
        if let totalDistance = replayDistances.last,
           totalDistance.isFinite,
           totalDistance > 0 {
            lastFocusedRouteDistance = CLLocationDistance(sender.progress) * totalDistance
        }

        let statusText = replayStatusText(for: replayState)

        if let replayAnnotation {
            replayAnnotation.coordinate = replayState.coordinate
            replayAnnotation.statusText = statusText
            replayAnnotation.isFacingLeft = replayState.isFacingLeft
            if let annotationView = mapView.view(for: replayAnnotation) as? RouteReplayAnnotationView {
                annotationView.configure(
                    emoji: replayAnnotation.emoji,
                    statusText: statusText,
                    isFacingLeft: replayState.isFacingLeft
                )
                annotationView.superview?.bringSubviewToFront(annotationView)
            }
        } else {
            let annotation = RouteReplayAnnotation(
                coordinate: replayState.coordinate,
                emoji: replayEmoji,
                statusText: statusText,
                isFacingLeft: replayState.isFacingLeft
            )
            replayAnnotation = annotation
            mapView.addAnnotation(annotation)
            if let annotationView = mapView.view(for: annotation) {
                annotationView.superview?.bringSubviewToFront(annotationView)
            }
        }
    }

    private func configureReplayRoute(with preparedRoute: PreparedRoute) {
        replayCoordinates = preparedRoute.coordinates
        replayDistances = preparedRoute.replayDistances
        replayAltitudes = preparedRoute.replayAltitudes
        replayHeartRates = preparedRoute.replayHeartRates
        replayPowers = preparedRoute.replayPowers
        replayTemperatures = preparedRoute.replayTemperatures
        replayGradeRatios = preparedRoute.replayGradeRatios
        replaySegmentStartIndices = preparedRoute.replaySegmentStartIndices
        replayViewportGeometry = preparedRoute.viewportGeometry

        let replayDistance = preparedRoute.replayDistances.last
            ?? preparedRoute.totalDistanceMeters
        replayRulerView.configure(
            totalDistanceText: replayTotalDistanceText(totalMeters: replayDistance),
            totalDistanceMeters: replayDistance,
            elevationSamples: preparedRoute.elevationSamples,
            globalPeakSamples: preparedRoute.globalPeakSamples,
            segmentBoundaryDistanceRanges: RouteViewportDistanceResolver
                .segmentBoundaryDistanceRanges(
                    cumulativeDistances: preparedRoute.replayDistances,
                    segmentStartIndices: preparedRoute.replaySegmentStartIndices
                )
        )
    }

    func updateReplayRulerVisibleRange() {
        guard selectedPanelDetent == .medium,
              replayCoordinates.count == replayDistances.count,
              let totalDistance = replayDistances.last,
              totalDistance > 0,
              let replayViewportGeometry else {
            return
        }

        let annotationDistance: CLLocationDistance? = replayAnnotation == nil
            ? nil
            : CLLocationDistance(replayRulerView.progress) * totalDistance
        let preferredDistance = lastFocusedRouteDistance ?? annotationDistance
        let visibleContainerBounds = mapContainerView.bounds.inset(
            by: UIEdgeInsets(
                top: 96,
                left: 0,
                bottom: panelHeight(for: selectedPanelDetent),
                right: 0
            )
        )
        let visibleMapBounds = mapContainerView.convert(
            visibleContainerBounds,
            to: mapView
        )
        guard let focusedRange = RouteViewportDistanceResolver.focusedVisibleRange(
            coordinates: replayViewportGeometry.coordinates,
            mapPoints: replayViewportGeometry.mapPoints,
            cumulativeDistances: replayViewportGeometry.cumulativeDistances,
            mapView: mapView,
            visibleBounds: visibleMapBounds,
            segmentStartIndices: replayViewportGeometry.segmentStartIndices,
            segmentDistanceRanges: replayViewportGeometry.segmentDistanceRanges,
            segmentBoundingMapRects: replayViewportGeometry.segmentBoundingMapRects,
            preferredDistance: preferredDistance
        ) else {
            return
        }

        let focusedDistanceRange = focusedRange.visibleDistanceRange
        if let preferredDistance,
           focusedDistanceRange.contains(preferredDistance) {
            lastFocusedRouteDistance = preferredDistance
        } else {
            lastFocusedRouteDistance = focusedDistanceRange.lowerBound
                + (focusedDistanceRange.upperBound - focusedDistanceRange.lowerBound) / 2
        }

        replayRulerView.setVisibleDistanceRange(
            replayRulerRangeWithContext(
                focusedRange.visibleDistanceRange,
                contextRange: focusedRange.contextDistanceRange
            )
        )
    }

    func handleMapRegionWillChangeForReplayRuler() {
        isMapRegionChanging = true
        replayViewportUpdateWorkItem?.cancel()
        replayViewportUpdateWorkItem = nil
        for routePolyline in routeDisplayIndicatorPolylines {
            (mapView.renderer(for: routePolyline) as? RouteDirectionPolylineRenderer)?
                .maximumIndicatorCount = 0
        }
        guard isRouteSlopeVisible else {
            return
        }
        let visibleOverlayIdentifiers = Set(
            mapView.overlays.map { ObjectIdentifier($0 as AnyObject) }
        )
        let visibleDirectionPolylines = routeSlopeDirectionPolylines.filter {
            directionPolyline in
            visibleOverlayIdentifiers.contains(ObjectIdentifier(directionPolyline))
        }
        if !visibleDirectionPolylines.isEmpty {
            areSlopeDirectionOverlaysSuspendedForMapChange = true
            mapView.removeOverlays(visibleDirectionPolylines)
        }
    }

    func handleMapRegionChangeForReplayRuler() {
        replayViewportUpdateWorkItem?.cancel()
        guard !hasPreparedForPermanentDismissal else {
            replayViewportUpdateWorkItem = nil
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.hasPreparedForPermanentDismissal else {
                return
            }
            self.replayViewportUpdateWorkItem = nil
            self.isMapRegionChanging = false
            self.restoreRouteDirectionIndicatorsAfterMapChange()
            if self.selectedPanelDetent == .medium {
                self.updateReplayRulerVisibleRange()
            }
        }
        replayViewportUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.08,
            execute: workItem
        )
    }

    private func restoreRouteDirectionIndicatorsAfterMapChange() {
        if !isRouteSlopeVisible {
            for routePolyline in routeDisplayIndicatorPolylines {
                guard let renderer = mapView.renderer(for: routePolyline)
                        as? RouteDirectionPolylineRenderer,
                      let indicatorBudget = routeDisplayIndicatorBudgets[
                          ObjectIdentifier(routePolyline)
                      ],
                      indicatorBudget > 0 else {
                    continue
                }
                if renderer.maximumIndicatorCount != indicatorBudget {
                    renderer.maximumIndicatorCount = indicatorBudget
                    renderer.setNeedsDisplay()
                }
            }
        }
        areSlopeDirectionOverlaysSuspendedForMapChange = false
        if isRouteSlopeVisible {
            addRouteSlopeDirectionOverlayIfNeeded()
        }
    }

    private func replayRulerRangeWithContext(
        _ range: ClosedRange<CLLocationDistance>,
        contextRange: ClosedRange<CLLocationDistance>
    ) -> ClosedRange<CLLocationDistance> {
        let span = range.upperBound - range.lowerBound
        let contextSpan = contextRange.upperBound - contextRange.lowerBound
        guard span < contextSpan * 0.9 else {
            return contextRange
        }

        let contextDistance = max(span * 0.04, min(contextSpan * 0.001, 20))
        let lowerBound = max(range.lowerBound - contextDistance, contextRange.lowerBound)
        let upperBound = min(range.upperBound + contextDistance, contextRange.upperBound)
        return lowerBound...upperBound
    }

    private static func cumulativeDistances(
        for coordinates: [CLLocationCoordinate2D],
        segmentStartIndices: Set<Int>,
        cancellationToken: RouteSlopePreparationCancellationToken
    ) -> [CLLocationDistance]? {
        guard let firstCoordinate = coordinates.first else {
            return []
        }

        var distances: [CLLocationDistance] = [0]
        distances.reserveCapacity(coordinates.count)

        var totalDistance: CLLocationDistance = 0
        var previousLocation = CLLocation(latitude: firstCoordinate.latitude, longitude: firstCoordinate.longitude)

        for (offset, coordinate) in coordinates.dropFirst().enumerated() {
            if offset.isMultiple(of: 256), cancellationToken.isCancelled {
                return nil
            }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let coordinateIndex = offset + 1
            if segmentStartIndices.contains(coordinateIndex) {
                totalDistance += RouteViewportDistanceResolver.segmentBoundaryDistance
            } else {
                totalDistance += location.distance(from: previousLocation)
            }
            distances.append(totalDistance)
            previousLocation = location
        }

        guard !cancellationToken.isCancelled else {
            return nil
        }
        return distances
    }

    private static func displayEndpointCoordinate(_ coordinate: CLLocationCoordinate2D?) -> CLLocationCoordinate2D? {
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else {
            return nil
        }

        return CoordinateTransformer.displayCoordinate(for: coordinate)
    }

    private func replayState(for progress: CGFloat) -> ReplayState? {
        guard replayCoordinates.count == replayDistances.count,
              let totalDistance = replayDistances.last,
              totalDistance > 0 else {
            return replayState(at: 0)
        }

        let targetDistance = min(max(CLLocationDistance(progress), 0), 1) * totalDistance
        let upperIndex = replayCoordinateIndex(atOrAfter: targetDistance)
        guard upperIndex > 0 else {
            return replayState(at: 0)
        }
        guard upperIndex < replayCoordinates.count else {
            return replayState(at: replayCoordinates.count - 1)
        }
        let lowerIndex = upperIndex - 1
        if replaySegmentStartIndices.contains(upperIndex) {
            let lowerDelta = targetDistance - replayDistances[lowerIndex]
            let upperDelta = replayDistances[upperIndex] - targetDistance
            return replayState(at: lowerDelta <= upperDelta ? lowerIndex : upperIndex)
        }

        let distanceSpan = replayDistances[upperIndex] - replayDistances[lowerIndex]
        guard distanceSpan > 0 else {
            return replayState(at: upperIndex)
        }
        let interpolation = min(
            max((targetDistance - replayDistances[lowerIndex]) / distanceSpan, 0),
            1
        )
        let lowerCoordinate = replayCoordinates[lowerIndex]
        let upperCoordinate = replayCoordinates[upperIndex]
        return ReplayState(
            coordinate: CLLocationCoordinate2D(
                latitude: lowerCoordinate.latitude
                    + (upperCoordinate.latitude - lowerCoordinate.latitude) * interpolation,
                longitude: lowerCoordinate.longitude
                    + (upperCoordinate.longitude - lowerCoordinate.longitude) * interpolation
            ),
            distanceMeters: targetDistance,
            altitudeMeters: interpolatedReplayValue(
                replayAltitude(at: lowerIndex),
                replayAltitude(at: upperIndex),
                progress: interpolation
            ),
            heartRateBeatsPerMinute: interpolatedReplayValue(
                replayHeartRate(at: lowerIndex),
                replayHeartRate(at: upperIndex),
                progress: interpolation
            ),
            powerWatts: interpolatedReplayValue(
                replayPower(at: lowerIndex),
                replayPower(at: upperIndex),
                progress: interpolation
            ),
            temperatureCelsius: interpolatedReplayValue(
                replayTemperature(at: lowerIndex),
                replayTemperature(at: upperIndex),
                progress: interpolation
            ),
            gradeRatio: interpolatedReplayValue(
                replayGradeRatio(at: lowerIndex),
                replayGradeRatio(at: upperIndex),
                progress: interpolation
            ),
            isFacingLeft: upperCoordinate.longitude - lowerCoordinate.longitude < 0
        )
    }

    private func replayState(at index: Int) -> ReplayState? {
        guard replayCoordinates.indices.contains(index),
              replayDistances.indices.contains(index) else {
            return nil
        }
        return ReplayState(
            coordinate: replayCoordinates[index],
            distanceMeters: replayDistances[index],
            altitudeMeters: replayAltitude(at: index),
            heartRateBeatsPerMinute: replayHeartRate(at: index),
            powerWatts: replayPower(at: index),
            temperatureCelsius: replayTemperature(at: index),
            gradeRatio: replayGradeRatio(at: index),
            isFacingLeft: replayFacingLeft(at: index)
        )
    }

    private func replayCoordinateIndex(
        atOrAfter targetDistance: CLLocationDistance
    ) -> Int {
        var lowerBound = 0
        var upperBound = replayDistances.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if replayDistances[middle] < targetDistance {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func replayGradeRatio(at index: Int) -> Double? {
        guard replayGradeRatios.indices.contains(index) else {
            return nil
        }
        return replayGradeRatios[index]
    }

    private func interpolatedReplayValue(
        _ lowerValue: Double?,
        _ upperValue: Double?,
        progress: Double
    ) -> Double? {
        switch (lowerValue, upperValue) {
        case let (lowerValue?, upperValue?):
            return lowerValue + (upperValue - lowerValue) * progress
        case let (lowerValue?, nil):
            return progress < 0.5 ? lowerValue : nil
        case let (nil, upperValue?):
            return progress < 0.5 ? nil : upperValue
        case (nil, nil):
            return nil
        }
    }

    private func removeReplayAnnotation() {
        guard let replayAnnotation else {
            return
        }

        mapView.removeAnnotation(replayAnnotation)
        self.replayAnnotation = nil
    }

    private func replayAltitude(at index: Int) -> Double? {
        guard index >= 0, index < replayAltitudes.count else {
            return nil
        }
        return replayAltitudes[index]
    }

    private func replayHeartRate(at index: Int) -> Double? {
        guard index >= 0, index < replayHeartRates.count else {
            return nil
        }
        return replayHeartRates[index]
    }

    private func replayPower(at index: Int) -> Double? {
        guard index >= 0, index < replayPowers.count else {
            return nil
        }
        return replayPowers[index]
    }

    private func replayTemperature(at index: Int) -> Double? {
        guard index >= 0, index < replayTemperatures.count else {
            return nil
        }
        return replayTemperatures[index]
    }

    private func replayFacingLeft(at index: Int) -> Bool {
        guard replayCoordinates.count > 1 else {
            return true
        }

        let previousIndex = replaySegmentStartIndices.contains(index)
            ? index
            : max(index - 1, 0)
        let nextIndex = replaySegmentStartIndices.contains(index + 1)
            ? index
            : min(index + 1, replayCoordinates.count - 1)
        guard previousIndex != nextIndex else {
            return true
        }

        let previousCoordinate = replayCoordinates[previousIndex]
        let nextCoordinate = replayCoordinates[nextIndex]
        let longitudeDelta = nextCoordinate.longitude - previousCoordinate.longitude
        return longitudeDelta < 0
    }

    private static func routeElevationSamples(
        distances: [CLLocationDistance],
        altitudes: [Double?],
        heartRates: [Double?],
        powers: [Double?],
        temperatures: [Double?],
        seriesBreakIndices: Set<Int>,
        maximumCount: Int,
        isCancelled: @Sendable () -> Bool
    ) -> [RouteElevationSample]? {
        guard distances.count == altitudes.count,
              !isCancelled() else {
            return nil
        }

        let hasHeartRates = heartRates.count == distances.count
        let hasPowers = powers.count == distances.count
        let hasTemperatures = temperatures.count == distances.count
        var samples: [RouteElevationSample] = []
        samples.reserveCapacity(min(altitudes.count, maximumCount * 2))
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
                heartRateBeatsPerMinute: hasHeartRates ? heartRates[index] : nil,
                powerWatts: hasPowers ? powers[index] : nil,
                temperatureCelsius: hasTemperatures ? temperatures[index] : nil,
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

    private static func routeElevationGlobalPeakSamples(
        distances: [CLLocationDistance],
        altitudes: [Double?],
        heartRates: [Double?],
        powers: [Double?],
        temperatures: [Double?],
        steepestUphill: RouteSlopePeak?,
        seriesBreakIndices: Set<Int>,
        elevationSamples: [RouteElevationSample],
        isCancelled: @Sendable () -> Bool
    ) -> ElevationProfileView.PeakSamples? {
        guard distances.count == altitudes.count,
              heartRates.count == distances.count,
              powers.count == distances.count,
              temperatures.count == distances.count,
              !isCancelled() else {
            return nil
        }

        let altitudePeak = elevationSamples.max(by: {
            $0.altitudeMeters < $1.altitudeMeters
        })
        let heartRatePeakIndex = metricPeakIndex(
            in: heartRates,
            requiresPositiveValue: true
        )
        let powerPeakIndex = metricPeakIndex(
            in: powers,
            requiresPositiveValue: true
        )
        let temperaturePeakIndex = metricPeakIndex(
            in: temperatures,
            requiresPositiveValue: false
        )

        func peakSample(at index: Int?) -> RouteElevationSample? {
            guard let index else {
                return nil
            }
            if isCancelled() {
                return nil
            }
            guard let altitude = interpolatedPeakAltitude(
                at: index,
                distances: distances,
                altitudes: altitudes,
                seriesBreakIndices: seriesBreakIndices
            ) else {
                return nil
            }
            return RouteElevationSample(
                distanceMeters: distances[index],
                altitudeMeters: altitude,
                heartRateBeatsPerMinute: heartRates[index],
                powerWatts: powers[index],
                temperatureCelsius: temperatures[index]
            )
        }
        let slopePeak: RouteElevationSample?
        if let steepestUphill,
           steepestUphill.distanceMeters.isFinite,
           steepestUphill.gradeRatio.isFinite,
           steepestUphill.gradeRatio > 0,
           let altitude = interpolatedPeakAltitude(
               atDistance: steepestUphill.distanceMeters,
               distances: distances,
               altitudes: altitudes,
               seriesBreakIndices: seriesBreakIndices
           ) ?? steepestUphill.altitudeMeters {
            slopePeak = RouteElevationSample(
                distanceMeters: steepestUphill.distanceMeters,
                altitudeMeters: altitude
            )
        } else {
            slopePeak = nil
        }
        let heartRatePeak = peakSample(at: heartRatePeakIndex)
        let powerPeak = peakSample(at: powerPeakIndex)
        let temperaturePeak = peakSample(at: temperaturePeakIndex)
        guard !isCancelled() else {
            return nil
        }
        return ElevationProfileView.PeakSamples(
            altitude: altitudePeak,
            slope: slopePeak,
            heartRate: heartRatePeak,
            power: powerPeak,
            temperature: temperaturePeak
        )
    }

    private static func metricPeakIndex(
        in values: [Double?],
        requiresPositiveValue: Bool
    ) -> Int? {
        var peak: (index: Int, value: Double)?
        for index in values.indices {
            guard let value = values[index],
                  value.isFinite,
                  !requiresPositiveValue || value > 0 else {
                continue
            }
            if peak == nil || value > (peak?.value ?? -.greatestFiniteMagnitude) {
                peak = (index, value)
            }
        }
        return peak?.index
    }

    private static func interpolatedPeakAltitude(
        atDistance targetDistance: CLLocationDistance,
        distances: [CLLocationDistance],
        altitudes: [Double?],
        seriesBreakIndices: Set<Int>
    ) -> Double? {
        guard distances.count == altitudes.count,
              !distances.isEmpty,
              targetDistance.isFinite else {
            return nil
        }
        var lowerBound = 0
        var upperBound = distances.count
        while lowerBound < upperBound {
            let middleIndex = (lowerBound + upperBound) / 2
            if distances[middleIndex] < targetDistance {
                lowerBound = middleIndex + 1
            } else {
                upperBound = middleIndex
            }
        }
        guard lowerBound < distances.count else {
            guard let altitude = altitudes.last ?? nil,
                  altitude.isFinite else {
                return nil
            }
            return altitude
        }
        if abs(distances[lowerBound] - targetDistance) < 0.000_001 {
            guard let altitude = altitudes[lowerBound],
                  altitude.isFinite else {
                return nil
            }
            return altitude
        }
        guard lowerBound > 0,
              !seriesBreakIndices.contains(lowerBound),
              let lowerAltitude = altitudes[lowerBound - 1],
              lowerAltitude.isFinite,
              let upperAltitude = altitudes[lowerBound],
              upperAltitude.isFinite else {
            return nil
        }
        let distanceSpan = distances[lowerBound] - distances[lowerBound - 1]
        guard distanceSpan > 0 else {
            return lowerAltitude
        }
        let progress = min(
            max((targetDistance - distances[lowerBound - 1]) / distanceSpan, 0),
            1
        )
        return lowerAltitude + (upperAltitude - lowerAltitude) * progress
    }

    private static func interpolatedPeakAltitude(
        at index: Int,
        distances: [CLLocationDistance],
        altitudes: [Double?],
        seriesBreakIndices: Set<Int>
    ) -> Double? {
        if let altitude = altitudes[index], altitude.isFinite {
            return altitude
        }

        let orderedBreaks = seriesBreakIndices
            .filter { $0 > 0 && $0 < altitudes.count }
            .sorted()
        let lowerBoundary = orderedBreaks.last(where: { $0 <= index }) ?? 0
        let upperBoundary = orderedBreaks.first(where: { $0 > index }) ?? altitudes.count

        var lowerIndex: Int?
        if index > lowerBoundary {
            for candidate in stride(from: index - 1, through: lowerBoundary, by: -1) {
                if let altitude = altitudes[candidate], altitude.isFinite {
                    lowerIndex = candidate
                    break
                }
            }
        }
        var upperIndex: Int?
        if index + 1 < upperBoundary {
            for candidate in (index + 1)..<upperBoundary {
                if let altitude = altitudes[candidate], altitude.isFinite {
                    upperIndex = candidate
                    break
                }
            }
        }

        switch (lowerIndex, upperIndex) {
        case let (lowerIndex?, upperIndex?):
            guard let lowerAltitude = altitudes[lowerIndex],
                  let upperAltitude = altitudes[upperIndex] else {
                return nil
            }
            let distanceSpan = distances[upperIndex] - distances[lowerIndex]
            guard distanceSpan > 0 else {
                return lowerAltitude
            }
            let progress = min(
                max((distances[index] - distances[lowerIndex]) / distanceSpan, 0),
                1
            )
            return lowerAltitude + (upperAltitude - lowerAltitude) * progress
        case let (lowerIndex?, nil):
            return altitudes[lowerIndex]
        case let (nil, upperIndex?):
            return altitudes[upperIndex]
        case (nil, nil):
            return nil
        }
    }

    private var replayEmoji: String {
        if presentationMode == .routeCollection {
            return "📍"
        }

        switch workout.activityType {
        case .cycling:
            return "🚴"
        case .running:
            return "🏃‍♂️"
        case .hiking, .walking:
            return "🚶"
        default:
            return "🚶"
        }
    }

    private func replayTotalDistanceText(totalMeters: CLLocationDistance) -> String {
        let kilometers = max(totalMeters, 0) / 1000
        if kilometers >= 100 {
            return String(format: "%.0fkm", kilometers)
        }
        if kilometers >= 10 {
            return String(format: "%.1fkm", kilometers)
        }
        return String(format: "%.2fkm", kilometers)
    }

    private func updatePanelText() {
        titleLabel.text = workout.title
        dataSourceLabel.text = workout.routeDataSourceTitle

        distanceLabel.text = panelDistanceText()
        distanceLabel.isHidden = distanceLabel.text == nil

        guard presentationMode != .routeCollection else {
            durationLabel.text = nil
            durationLabel.isHidden = true
            return
        }

        durationLabel.text = panelDurationText()
        durationLabel.isHidden = durationLabel.text == nil
    }

    private func panelDistanceText() -> String? {
        let distanceText: String
        if workout.distanceMeters >= 1000 {
            distanceText = String(format: "%.1f km", workout.distanceMeters / 1000)
        } else if workout.distanceMeters > 0 {
            distanceText = AppLocalization.format(.distanceMetersFormat, workout.distanceMeters)
        } else {
            return nil
        }

        guard let elevationGainText = panelElevationGainText() else {
            return distanceText
        }

        return "\(distanceText) / \(elevationGainText)"
    }

    private func panelElevationGainText() -> String? {
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

    private func panelDurationText() -> String? {
        guard let durationSeconds = workout.durationSeconds, durationSeconds > 0 else {
            return nil
        }

        return workout.durationText
    }

    private func replayStatusText(for state: ReplayState) -> String {
        let distanceText = replayDistanceText(state.distanceMeters)
        let altitudeText = state.altitudeMeters.map { "\(Int(round($0)))m" } ?? "--m"
        let gradeText = state.gradeRatio.map {
            "\(Int(round($0 * 100)))%"
        } ?? "--%"
        let primaryText = [distanceText, altitudeText, gradeText]
            .joined(separator: "·")
        let metricText = replayMetricStatusText(for: state)
        guard !metricText.isEmpty else {
            return primaryText
        }

        return "\(primaryText)\n\(metricText)"
    }

    private func replayMetricStatusText(for state: ReplayState) -> String {
        var parts: [String] = []
        if let power = roundedPositiveInt(state.powerWatts) {
            parts.append("\(power)w")
        }
        if let heartRate = roundedPositiveInt(state.heartRateBeatsPerMinute) {
            parts.append("\(heartRate)bpm")
        }
        if let temperature = roundedFiniteInt(state.temperatureCelsius) {
            parts.append("\(temperature)℃")
        }
        return parts.joined(separator: "·")
    }

    private func replayDistanceText(_ distanceMeters: CLLocationDistance) -> String {
        var value = String(format: "%.2f", max(distanceMeters, 0) / 1_000)
        while value.last == "0" {
            value.removeLast()
        }
        if value.last == "." {
            value.removeLast()
        }
        return "\(value)km"
    }

    private func roundedPositiveInt(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }

        return Int(value.rounded())
    }

    private func roundedFiniteInt(_ value: Double?) -> Int? {
        guard let value, value.isFinite else {
            return nil
        }

        return Int(value.rounded())
    }
}

extension WorkoutRouteDetailViewController: UISheetPresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === panelSheetViewController else {
            return
        }

        hasPresentedPanelSheet = false
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ sheetPresentationController: UISheetPresentationController
    ) {
        let detent: PanelDetent = sheetPresentationController.selectedDetentIdentifier == Self.mediumPanelDetentIdentifier
            ? .medium
            : .minimum
        if detent == .medium, presentationMode == .workout, !isDemoMode {
            AppReviewPromptManager.shared.record(.detailPanelExpanded)
        }
        applyPanelSheetDetent(detent, animated: true)
    }
}
