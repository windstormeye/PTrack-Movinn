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

    private struct PreparedRoute {
        let coordinates: [CLLocationCoordinate2D]
        let routeCoordinates: [RouteCoordinate]
        let startCoordinate: CLLocationCoordinate2D
        let endCoordinate: CLLocationCoordinate2D
        let replayDistances: [CLLocationDistance]
        let replayAltitudes: [Double?]
        let replayHeartRates: [Double?]
        let replayPowers: [Double?]
        let replayTemperatures: [Double?]
        let elevationSamples: [RouteElevationSample]
        let totalDistanceMeters: CLLocationDistance
    }

    let workout: TrackedWorkout
    private let presentationMode: PresentationMode
    private let providedMergeSourceWorkouts: [TrackedWorkout]?
    private let mediaStore = RouteMediaStore()
    private let mapContainerView = AppMapContainerView()
    private var mapView: MKMapView { mapContainerView.mapView }
    private let mapToneOverlay = AppMapStyle.makeToneOverlay()
    private let routePreparationQueue = DispatchQueue(label: "studio.pj.PTrack.route-detail-prepare", qos: .userInitiated)
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
    private var replayAnnotation: RouteReplayAnnotation?
    private var routePolyline: MKPolyline?
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
    private let primaryContentSize: CGFloat = 28
    private let expandedPrimaryContentTop: CGFloat = 33
    private let minimumPrimaryContentScale: CGFloat = 0.88
    private let navigationBackgroundHeight: CGFloat = 124
    private let mapBottomExtension = AppMapContainerView.defaultBottomLogoAvoidanceOffset
    private let maximumElevationSampleCount = 120
    private static let minimumPanelDetentIdentifier = UISheetPresentationController.Detent.Identifier(
        "routeDetailMinimum"
    )
    private static let mediumPanelDetentIdentifier = UISheetPresentationController.Detent.Identifier(
        "routeDetailMedium"
    )

    private var panelCaloriesKilocalories: Double? {
        guard let calories = workout.activeEnergyBurnedKilocalories, calories > 0 else {
            return nil
        }

        return calories
    }

    init(
        workout: TrackedWorkout,
        presentationMode: PresentationMode = .workout,
        mergeSourceWorkouts: [TrackedWorkout]? = nil
    ) {
        self.workout = workout
        self.presentationMode = presentationMode
        providedMergeSourceWorkouts = mergeSourceWorkouts
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
        if presentationMode == .workout {
            refreshMoreMenuForPhotoAuthorizationState()
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
        routePolyline = nil
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
        let measuredDistance = replayDistances.last ?? workout.distanceMeters
        let totalDistance = workout.distanceMeters > 0 ? workout.distanceMeters : measuredDistance
        replayRulerView.configure(
            totalDistanceText: replayTotalDistanceText(totalMeters: totalDistance),
            elevationSamples: routeElevationSamples()
        )

        if let caloriesKilocalories = panelCaloriesKilocalories {
            calorieRiceView.configure(caloriesKilocalories: caloriesKilocalories)
        }
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
                modalPresentationHost.presentProPaywall { [weak self] in
                    self?.presentRouteMergeSelectionUnlocked()
                }
                return
            }

            presentRouteMergeSelectionUnlocked()
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
        guard presentationMode == .workout else {
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
        let fileName = GPXRouteExporter.suggestedFileName(routeName: routeName)

        gpxExportQueue.async { [weak self, routeName, coordinates, fileName] in
            let result: Result<URL, Error>
            do {
                let data = try GPXRouteExporter.data(
                    routeName: routeName,
                    coordinates: coordinates
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

        replayRulerView.configure(totalDistanceText: replayTotalDistanceText(totalMeters: workout.distanceMeters))
        replayRulerView.addTarget(self, action: #selector(handleReplayProgressChanged(_:)), for: .valueChanged)

        detailStackView.addArrangedSubview(replayRulerView)
        if let caloriesKilocalories {
            calorieRiceView.configure(caloriesKilocalories: caloriesKilocalories)
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
            loadRouteMedia()
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
        routePreparationQueue.async { [weak self] in
            let preparedRoute = Self.prepareRoute(
                for: workout,
                maximumElevationSampleCount: maximumElevationSampleCount
            )

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      !self.hasPreparedForPermanentDismissal else {
                    return
                }

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
        maximumElevationSampleCount: Int
    ) -> PreparedRoute? {
        let routeCoordinates = workout.routeDetailCoordinates
        let coordinates = CoordinateTransformer.displayCoordinates(for: routeCoordinates.map(\.coordinate))
        guard coordinates.count > 1 else {
            return nil
        }

        let replayDistances = cumulativeDistances(for: coordinates)
        let replayAltitudes = routeCoordinates.map(\.altitudeMeters)
        let replayHeartRates = routeCoordinates.map(\.heartRateBeatsPerMinute)
        let replayPowers = routeCoordinates.map(\.powerWatts)
        let replayTemperatures = routeCoordinates.map(\.temperatureCelsius)
        let measuredDistance = replayDistances.last ?? workout.distanceMeters
        let totalDistanceMeters = workout.distanceMeters > 0 ? workout.distanceMeters : measuredDistance
        let elevationSamples = routeElevationSamples(
            distances: replayDistances,
            routeCoordinates: routeCoordinates,
            maximumCount: maximumElevationSampleCount
        )

        return PreparedRoute(
            coordinates: coordinates,
            routeCoordinates: routeCoordinates,
            startCoordinate: displayEndpointCoordinate(workout.routeCollectionMergeStartCoordinate)
                ?? coordinates[0],
            endCoordinate: displayEndpointCoordinate(workout.routeCollectionMergeEndCoordinate)
                ?? coordinates[coordinates.count - 1],
            replayDistances: replayDistances,
            replayAltitudes: replayAltitudes,
            replayHeartRates: replayHeartRates,
            replayPowers: replayPowers,
            replayTemperatures: replayTemperatures,
            elevationSamples: elevationSamples,
            totalDistanceMeters: totalDistanceMeters
        )
    }

    private func applyPreparedRoute(_ preparedRoute: PreparedRoute) {
        guard !hasPreparedForPermanentDismissal else {
            return
        }

        configureReplayRoute(with: preparedRoute)

        let coordinates = preparedRoute.coordinates
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        routePolyline = polyline
        hasFittedRoute = false
        mapView.addOverlay(polyline, level: .aboveLabels)

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
        guard !hasFittedRoute, let routePolyline else {
            return
        }

        hasFittedRoute = true
        mapView.setVisibleMapRect(
            routePolyline.boundingMapRect,
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

    var mapRouteStrokeColor: UIColor {
        selectedMapStyle == .dark ? .white : .black
    }

    var mapRouteDirectionIndicatorColor: UIColor {
        .black
    }

    private func refreshRouteOverlayStrokeColor() {
        guard let routePolyline,
              let renderer = mapView.renderer(for: routePolyline) as? MKPolylineRenderer else {
            return
        }

        renderer.strokeColor = mapRouteStrokeColor
        if let directionRenderer = renderer as? RouteDirectionPolylineRenderer {
            directionRenderer.directionIndicatorColor = mapRouteDirectionIndicatorColor
        }
        renderer.setNeedsDisplay()
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
                    self.routeMediaItems = mediaItems
                    self.displayRouteMediaIfRouteReady()
                    self.refreshMoreMenuForPhotoAuthorizationState(reloadMediaIfAuthorizationJustGranted: false)
                }
            case .failure(let error):
                print("PTrack Photos: failed to load route media: \(error)")
                self.refreshMoreMenuForPhotoAuthorizationState(reloadMediaIfAuthorizationJustGranted: false)
            }
        }
    }

    private func displayRouteMediaIfRouteReady() {
        guard !hasPreparedForPermanentDismissal else {
            return
        }

        guard routePolyline != nil,
              !hasDisplayedRouteMediaAnnotations,
              !routeMediaItems.isEmpty else {
            return
        }

        hasDisplayedRouteMediaAnnotations = true
        mapView.addAnnotations(routeMediaItems.map(RouteMediaAnnotation.init))
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

        let changes = {
            self.detailStackView.alpha = 1
            self.updatePrimaryContentScale(for: height)
            self.panelSheetViewController.view.layoutIfNeeded()
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
        guard selectedPanelDetent == detent,
              detent == .medium,
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

        replayRulerView.configure(
            totalDistanceText: replayTotalDistanceText(totalMeters: preparedRoute.totalDistanceMeters),
            elevationSamples: preparedRoute.elevationSamples
        )
    }

    private static func cumulativeDistances(for coordinates: [CLLocationCoordinate2D]) -> [CLLocationDistance] {
        guard let firstCoordinate = coordinates.first else {
            return []
        }

        var distances: [CLLocationDistance] = [0]
        distances.reserveCapacity(coordinates.count)

        var totalDistance: CLLocationDistance = 0
        var previousLocation = CLLocation(latitude: firstCoordinate.latitude, longitude: firstCoordinate.longitude)

        for coordinate in coordinates.dropFirst() {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            totalDistance += location.distance(from: previousLocation)
            distances.append(totalDistance)
            previousLocation = location
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
            guard let coordinate = replayCoordinates.first else {
                return nil
            }
            return ReplayState(
                coordinate: coordinate,
                distanceMeters: 0,
                altitudeMeters: replayAltitude(at: 0),
                heartRateBeatsPerMinute: replayHeartRate(at: 0),
                powerWatts: replayPower(at: 0),
                temperatureCelsius: replayTemperature(at: 0),
                isFacingLeft: replayFacingLeft(at: 0)
            )
        }

        let targetDistance = CLLocationDistance(progress) * totalDistance
        let index = nearestReplayCoordinateIndex(for: targetDistance)
        return ReplayState(
            coordinate: replayCoordinates[index],
            distanceMeters: replayDistances[index],
            altitudeMeters: replayAltitude(at: index),
            heartRateBeatsPerMinute: replayHeartRate(at: index),
            powerWatts: replayPower(at: index),
            temperatureCelsius: replayTemperature(at: index),
            isFacingLeft: replayFacingLeft(at: index)
        )
    }

    private func nearestReplayCoordinateIndex(for targetDistance: CLLocationDistance) -> Int {
        var lowerBound = 0
        var upperBound = replayDistances.count - 1

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if replayDistances[middle] < targetDistance {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        guard lowerBound > 0 else {
            return 0
        }

        let previousIndex = lowerBound - 1
        let previousDelta = abs(replayDistances[previousIndex] - targetDistance)
        let currentDelta = abs(replayDistances[lowerBound] - targetDistance)
        return previousDelta <= currentDelta ? previousIndex : lowerBound
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

        let previousIndex = max(index - 1, 0)
        let nextIndex = min(index + 1, replayCoordinates.count - 1)
        guard previousIndex != nextIndex else {
            return true
        }

        let previousCoordinate = replayCoordinates[previousIndex]
        let nextCoordinate = replayCoordinates[nextIndex]
        let longitudeDelta = nextCoordinate.longitude - previousCoordinate.longitude
        return longitudeDelta < 0
    }

    private func routeElevationSamples() -> [RouteElevationSample] {
        Self.routeElevationSamples(
            distances: replayDistances,
            altitudes: replayAltitudes,
            heartRates: replayHeartRates,
            powers: replayPowers,
            temperatures: replayTemperatures,
            maximumCount: maximumElevationSampleCount
        )
    }

    private static func routeElevationSamples(
        distances: [CLLocationDistance],
        routeCoordinates: [RouteCoordinate],
        maximumCount: Int
    ) -> [RouteElevationSample] {
        guard distances.count == routeCoordinates.count else {
            return []
        }

        return routeElevationSamples(
            distances: distances,
            altitudes: routeCoordinates.map(\.altitudeMeters),
            heartRates: routeCoordinates.map(\.heartRateBeatsPerMinute),
            powers: routeCoordinates.map(\.powerWatts),
            temperatures: routeCoordinates.map(\.temperatureCelsius),
            maximumCount: maximumCount
        )
    }

    private static func routeElevationSamples(
        distances: [CLLocationDistance],
        altitudes: [Double?],
        heartRates: [Double?] = [],
        powers: [Double?] = [],
        temperatures: [Double?] = [],
        maximumCount: Int
    ) -> [RouteElevationSample] {
        guard distances.count == altitudes.count else {
            return []
        }

        let hasHeartRates = heartRates.count == distances.count
        let hasPowers = powers.count == distances.count
        let hasTemperatures = temperatures.count == distances.count
        let samples = altitudes.enumerated().compactMap { index, altitude -> RouteElevationSample? in
            guard let altitude else {
                return nil
            }
            return RouteElevationSample(
                distanceMeters: distances[index],
                altitudeMeters: altitude,
                heartRateBeatsPerMinute: hasHeartRates ? heartRates[index] : nil,
                powerWatts: hasPowers ? powers[index] : nil,
                temperatureCelsius: hasTemperatures ? temperatures[index] : nil
            )
        }

        return downsampleElevationSamples(samples, maximumCount: maximumCount)
    }

    private static func downsampleElevationSamples(
        _ samples: [RouteElevationSample],
        maximumCount: Int
    ) -> [RouteElevationSample] {
        guard samples.count > maximumCount, maximumCount > 2 else {
            return samples
        }

        let step = Double(samples.count - 1) / Double(maximumCount - 1)
        var selectedIndices = Set<Int>()
        for index in 0..<maximumCount {
            selectedIndices.insert(Int(round(Double(index) * step)))
        }

        selectedIndices.formUnion(peakSampleIndices(in: samples))
        return selectedIndices.sorted().map { index in
            samples[index]
        }
    }

    private static func peakSampleIndices(in samples: [RouteElevationSample]) -> Set<Int> {
        var indices = Set<Int>()
        if let altitudePeak = samples.indices.max(by: { samples[$0].altitudeMeters < samples[$1].altitudeMeters }) {
            indices.insert(altitudePeak)
        }
        if let heartRatePeak = peakSampleIndex(in: samples, requiresPositiveValue: true, value: \.heartRateBeatsPerMinute) {
            indices.insert(heartRatePeak)
        }
        if let powerPeak = peakSampleIndex(in: samples, requiresPositiveValue: true, value: \.powerWatts) {
            indices.insert(powerPeak)
        }
        if let temperaturePeak = peakSampleIndex(in: samples, requiresPositiveValue: false, value: \.temperatureCelsius) {
            indices.insert(temperaturePeak)
        }
        return indices
    }

    private static func peakSampleIndex(
        in samples: [RouteElevationSample],
        requiresPositiveValue: Bool,
        value: KeyPath<RouteElevationSample, Double?>
    ) -> Int? {
        samples.indices
            .compactMap { index -> (index: Int, value: Double)? in
                guard let sampleValue = samples[index][keyPath: value],
                      sampleValue.isFinite,
                      !requiresPositiveValue || sampleValue > 0 else {
                    return nil
                }
                return (index, sampleValue)
            }
            .max { lhs, rhs in lhs.value < rhs.value }?.index
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
        let distanceText: String
        if state.distanceMeters >= 1000 {
            distanceText = String(format: "%.2f km", state.distanceMeters / 1000)
        } else {
            distanceText = String(format: "%.0f m", max(state.distanceMeters, 0))
        }

        let altitudeText = state.altitudeMeters.map { "\(Int(round($0))) m" } ?? "-- m"
        let primaryText = "\(distanceText) · \(altitudeText)"
        let metricText = replayMetricStatusText(for: state)
        guard !metricText.isEmpty else {
            return primaryText
        }

        return "\(primaryText)\n\(metricText)"
    }

    private func replayMetricStatusText(for state: ReplayState) -> String {
        var parts: [String] = []
        if let heartRate = roundedPositiveInt(state.heartRateBeatsPerMinute) {
            parts.append("❤️\(heartRate)")
        }
        if let power = roundedPositiveInt(state.powerWatts) {
            parts.append("⚡️\(power)W")
        }
        if let temperature = roundedFiniteInt(state.temperatureCelsius) {
            parts.append("☀️\(temperature)°")
        }
        return parts.joined(separator: "  ")
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
        applyPanelSheetDetent(detent, animated: true)
    }
}
