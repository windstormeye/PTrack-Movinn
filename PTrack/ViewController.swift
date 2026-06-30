//
//  ViewController.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/12.
//

import AuthenticationServices
import CoreLocation
import MapKit
import SnapKit
import HealthKit
import UIKit

class ViewController: UIViewController {
    private enum DefaultsKey {
        static let stravaHistoricalBackfillCompleted = "studio.pj.PTrack.strava.historicalBackfillCompleted"
        static let homeRouteGridColumnCount = "studio.pj.PTrack.home.routeGridColumnCount"
    }

    private enum RouteBookPanelDetent {
        case minimum
        case medium
    }

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
    private var cachedWorkoutSummary: WorkoutCacheSummary?
    private var activeLoadingOperationCount = 0
    private var isCacheLoadInProgress = false
    private var isHealthSyncInProgress = false
    private var isStravaSyncInProgress = false
    private var isHealthNewDataSyncInProgress = false
    private var isStravaNewDataSyncInProgress = false
    private var isCacheLoadShowingLoadingIndicator = false
    private var isHealthSyncShowingLoadingIndicator = false
    private var isStravaSyncShowingLoadingIndicator = false
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
    private var totalDistanceTrailingToLoadingConstraint: Constraint?
    private var totalDistanceTrailingToMoreConstraint: Constraint?
    private let routeBookLocateButton = UIButton(type: .system)
    private let routeBookPanelSheetViewController = RouteBookPanelSheetViewController()
    private let routeBookPanelView = UIVisualEffectView(effect: ViewController.makeRouteBookPanelGlassEffect())
    private let routeBookPanelMetricsStackView = UIStackView()
    private let routeBookPanelDistanceLabel = UILabel()
    private let routeBookPanelDetailStackView = UIStackView()
    private let routeBookReplayRulerView = WorkoutRouteReplayRulerView()
    private let emptyDataSourceView = HomeDataSourceEmptyView()
    private let defaultColumnCount: CGFloat = 3
    private let itemSpacing: CGFloat = 12
    private let lineSpacing: CGFloat = 2
    private let headerBottomPadding: CGFloat = 8
    private let sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 16, right: 12)
    private let pendingWorkoutFlushDelay: TimeInterval = 0.35
    private let activeScrollFlushDelay: TimeInterval = 0.45
    private let cacheSaveDebounceDelay: TimeInterval = 1.0
    private let cacheLoadPreviewBatchSize = 32
    private let homePreviewCoordinateLimit = 240
    private let stravaIncrementalLookback: TimeInterval = 7 * 24 * 60 * 60
    private let pullRefreshTriggerDistance: CGFloat = 86
    private let routeBookPanelHeight: CGFloat = 68
    private let routeBookPanelDetailContentTopSpacing: CGFloat = 24
    private let routeBookReplayRulerViewHeight: CGFloat = 98
    private let routeBookPanelMediumBottomPadding: CGFloat = 18
    private let routeBookPanelPrimaryContentSize: CGFloat = 28
    private let routeBookPanelExpandedPrimaryContentTop: CGFloat = 33
    private let routeBookPanelMinimumPrimaryContentScale: CGFloat = 0.88
    private let routeBookLocateButtonPanelSpacing: CGFloat = 18
    private let routeBookMaximumElevationSampleCount = 120
    private var hasPresentedRouteBookPanelSheet = false
    private var selectedRouteBookPanelDetent: RouteBookPanelDetent = .minimum
    private var routeBookPanelMetricsCenterYConstraint: Constraint?
    private var routeBookLocateButtonBottomConstraint: Constraint?
    private var routeBookPresentedPanelHeight: CGFloat = 68
    private var isRouteBookModeActive = false
    private var routeBookWorkout: TrackedWorkout?
    private var routeBookPolyline: MKPolyline?
    private var routeBookReplayCoordinates: [CLLocationCoordinate2D] = []
    private var routeBookReplayDistances: [CLLocationDistance] = []
    private var shouldCenterRouteBookOnNextLocation = false
    private var routeBookLastLocation: CLLocation?
    private var routeBookLastHeadingDegrees: CLLocationDirection?
    private var routeBookHeadingDisplayDegrees: CLLocationDirection?
    private var shouldClearRouteImportIndicatorsOnNextHomeAppear = false
    private var isHealthAuthorizationRecoveryCheckInProgress = false

    deinit {
        pendingFlushWorkItem?.cancel()
        pendingCacheSaveWorkItem?.cancel()
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
        configureEmptyDataSourceView()
        configureLoadingIndicator()
        registerLanguageObserver()
        registerStravaImportObserver()
        registerRouteBookObserver()
        registerSharedRouteImportObserver()
        registerAppForegroundObserver()
        registerHealthAuthorizationObserver()
        registerTraitChangeHandler()
        store.progressHandler = { message in
            print("PTrack HealthKit: \(message)")
        }
        importPendingSharedRoutesIfNeeded()
        loadCachedWorkoutsThenSynchronize()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateFullScreenInsets()
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        clearRouteImportIndicatorsIfNeededOnHomeAppear()
        applyRouteBookInterfaceState()
        updateFullScreenInsets(force: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateFullScreenInsets(force: true)
        presentRouteBookPanelSheetIfNeeded()
        openRouteCollectionIfRequested()
        DispatchQueue.main.async { [weak self] in
            self?.updateFullScreenInsets(force: true)
            self?.presentRouteBookPanelSheetIfNeeded()
            self?.openRouteCollectionIfRequested()
        }
    }

    private func configureNavigationItem() {
        title = "Movinn"
        navigationItem.largeTitleDisplayMode = .never
    }

    private func configureCollectionView() {
        view.backgroundColor = .systemBackground

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
        }
        routeGridView.onEndDragging = { [weak self] _, decelerate in
            self?.performPullRefreshIfNeeded()
            if !decelerate {
                self?.flushPendingWorkouts()
            }
        }
        routeGridView.onEndDecelerating = { [weak self] _ in
            self?.finishPullRefreshTracking()
            self?.flushPendingWorkouts()
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
        routeBookMapView.userTrackingMode = .none
        resetRouteBookMapHeading(animated: false)
        routeBookLocationManager.delegate = self
        routeBookLocationManager.desiredAccuracy = kCLLocationAccuracyBest
        routeBookLocationManager.headingFilter = 5

        AppMapStyle.apply(.appDefault, to: routeBookMapView)
        AppMapStyle.setToneOverlay(routeBookMapToneOverlay, visible: true, on: routeBookMapView)

        view.addSubview(routeBookMapContainerView)
        view.sendSubviewToBack(routeBookMapContainerView)

        routeBookMapContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        configureRouteBookPanelView()
        configureRouteBookLocateButton()
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

        routeBookReplayRulerView.configure(totalDistanceText: routeBookReplayTotalDistanceText(totalMeters: 0))
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
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(
            systemName: "location.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = AppColors.background(alpha: 0.92)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)

        routeBookLocateButton.configuration = configuration
        routeBookLocateButton.isHidden = true
        routeBookLocateButton.layer.shadowColor = UIColor.black.cgColor
        routeBookLocateButton.layer.shadowOpacity = 0.14
        routeBookLocateButton.layer.shadowRadius = 12
        routeBookLocateButton.layer.shadowOffset = CGSize(width: 0, height: 4)
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

        headerView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(122)
        }

        headerBlurView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
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
            totalDistanceTrailingToLoadingConstraint = make.trailing.lessThanOrEqualTo(loadingIndicator.snp.leading).offset(-8).constraint
            totalDistanceTrailingToMoreConstraint = make.trailing.lessThanOrEqualTo(moreButton.snp.leading).offset(-10).constraint
            make.lastBaseline.equalTo(titleLabel.snp.lastBaseline).offset(-3)
        }

        loadingIndicator.snp.makeConstraints { make in
            make.centerY.equalTo(totalDistanceLabel)
            make.trailing.equalTo(moreButton.snp.leading).offset(-10)
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
        case .medium:
            updateRouteBookReplayProgressForCurrentLocation()
        }

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
            make.centerY.equalTo(view.safeAreaLayoutGuide.snp.centerY).offset(-18)
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

    private func showCacheLoadLoadingIndicatorIfNeeded() {
        guard isCacheLoadInProgress, !isCacheLoadShowingLoadingIndicator else {
            return
        }

        isCacheLoadShowingLoadingIndicator = true
        beginLoadingOperation()
    }

    private func showHealthSyncLoadingIndicatorIfNeeded() {
        guard isHealthSyncInProgress, !isHealthSyncShowingLoadingIndicator else {
            return
        }

        isHealthSyncShowingLoadingIndicator = true
        beginLoadingOperation()
    }

    private func showStravaSyncLoadingIndicatorIfNeeded() {
        guard isStravaSyncInProgress, !isStravaSyncShowingLoadingIndicator else {
            return
        }

        isStravaSyncShowingLoadingIndicator = true
        beginLoadingOperation()
    }

    private var isNewDataSyncInProgress: Bool {
        isHealthNewDataSyncInProgress || isStravaNewDataSyncInProgress
    }

    private func setHealthNewDataSyncInProgress(_ isInProgress: Bool) {
        guard isHealthNewDataSyncInProgress != isInProgress else {
            return
        }

        isHealthNewDataSyncInProgress = isInProgress
        updateTotalDistanceText()
    }

    private func setStravaNewDataSyncInProgress(_ isInProgress: Bool) {
        guard isStravaNewDataSyncInProgress != isInProgress else {
            return
        }

        isStravaNewDataSyncInProgress = isInProgress
        updateTotalDistanceText()
    }

    private var hasReadableDataSourceAuthorization: Bool {
        store.authorizationState == .authorized || StravaManager.shared.hasStoredAuthorization
    }

    private func updateHeaderReadAuthorizationState() {
        totalDistanceLabel.isHidden = isRouteBookModeActive || !hasReadableDataSourceAuthorization
        updateLoadingIndicatorVisibility()
        updateHeaderMoreButtonMode()
    }

    private func updateLoadingIndicatorVisibility() {
        let shouldShowLoadingIndicator = (activeLoadingOperationCount > 0 || isNewDataSyncInProgress)
            && hasReadableDataSourceAuthorization
            && !isRouteBookModeActive

        if shouldShowLoadingIndicator {
            totalDistanceTrailingToMoreConstraint?.deactivate()
            totalDistanceTrailingToLoadingConstraint?.activate()
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
            totalDistanceTrailingToLoadingConstraint?.deactivate()
            totalDistanceTrailingToMoreConstraint?.activate()
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

    func synchronizeDataSourcesForAppOpen(showsLoadingIndicator: Bool = true) {
        updateHeaderReadAuthorizationState()

        switch store.authorizationState {
        case .authorized:
            loadAuthorizedHealthWorkouts(showsLoadingIndicator: showsLoadingIndicator)
        case .needsAttention:
            print("PTrack HealthKit: checking pending authorization on app open")
            recoverHealthAuthorizationIfNeeded(showsLoadingIndicator: showsLoadingIndicator)
        case .notDetermined:
            print("PTrack HealthKit: skipped import, no stored authorization")
        }
        loadAuthorizedStravaWorkouts(showsLoadingIndicator: showsLoadingIndicator)
    }

    func updatePullRefreshTracking(for scrollView: UIScrollView) {
        guard scrollView.isDragging else {
            isPullRefreshArmedInCurrentDrag = false
            return
        }

        let pullDistance = max(-(scrollView.contentOffset.y + scrollView.contentInset.top), 0)
        isPullRefreshArmedInCurrentDrag = pullDistance >= pullRefreshTriggerDistance
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
        isCacheLoadInProgress || isHealthSyncInProgress || isStravaSyncInProgress
    }

    private func synchronizeDataSourcesForPullRefresh() {
        if isCacheLoadInProgress {
            showCacheLoadLoadingIndicatorIfNeeded()
        }

        synchronizeDataSourcesForAppOpen()
    }

    private func updateTotalDistanceText() {
        if isNewDataSyncInProgress {
            totalDistanceLabel.text = AppLocalization.text(.newDataSyncing)
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
            return
        }

        let displayedTotalDistanceMeters = cachedWorkoutSummary?.totalDistanceMeters ?? totalDistanceMeters
        let displayedWorkoutCount = cachedWorkoutSummary?.workoutCount ?? workouts.count
        let totalKilometers = displayedTotalDistanceMeters / 1000
        let prefixText = AppLocalization.text(.activitySummaryPrefix)
        let distanceText = AppLocalization.format(.totalDistanceFormat, Int(totalKilometers.rounded()))
        let activityCountText = AppLocalization.format(.totalActivityCountFormat, displayedWorkoutCount)
        totalDistanceLabel.text = "\(prefixText) \(distanceText)/\(activityCountText)"
        updateHeaderReadAuthorizationState()
        updateEmptyDataSourceVisibility()
    }

    private func updateEmptyDataSourceVisibility() {
        emptyDataSourceView.updateAuthorizationState(appleHealth: store.authorizationState)

        guard !isRouteBookModeActive, workouts.isEmpty else {
            emptyDataSourceView.isHidden = true
            return
        }

        if isDataSourceSyncInProgress {
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
        updateTotalDistanceText()
        updateRouteBookPanelText()
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

    private func registerAppForegroundObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
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
            viewController.updateRouteBookLocateButtonAppearance()
            viewController.updateRouteBookPanelAppearanceColors()
            viewController.collectionView?.reloadData()
        }
    }

    @objc private func handleAppWillEnterForeground() {
        recoverHealthAuthorizationIfNeeded(showsLoadingIndicator: false)
        updateHeaderReadAuthorizationState()
        updateEmptyDataSourceVisibility()
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
            print("PTrack Route Collection: imported \(importedRoutes.count) shared GPX routes")
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

    private func loadCachedWorkoutSummary() {
        cachedWorkoutSummary = cacheStore.loadSummary()
    }

    private func loadCachedWorkoutsThenSynchronize() {
        isCacheLoadInProgress = true
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

            let loadedWorkoutCount = self.cacheStore.loadProgressively(
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

                let hadCachedSummary = self.cachedWorkoutSummary != nil
                self.finishApplyingCachedWorkoutPreviews()
                self.isCacheLoadInProgress = false
                if self.isCacheLoadShowingLoadingIndicator {
                    self.isCacheLoadShowingLoadingIndicator = false
                    self.endLoadingOperation()
                } else {
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                }

                self.synchronizeDataSourcesForAppOpen(
                    showsLoadingIndicator: loadedWorkoutCount == 0 && !hadCachedSummary
                )
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
        restorePersistedRouteBookModeIfNeeded()
    }

    private func finishApplyingCachedWorkoutPreviews() {
        removeCachedAppleHealthWorkoutsConflictingWithStrava()
        markHealthAuthorizationVerifiedFromCachedWorkoutsIfNeeded()
        knownWorkoutIDs = Set(workouts.map(\.id))
        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        let shouldBackfillCacheSummary = cachedWorkoutSummary == nil && !workouts.isEmpty
        cachedWorkoutSummary = nil
        updateTotalDistanceText()
        collectionView.reloadData()
        prewarmInitialRouteSources()
        restorePersistedRouteBookModeIfNeeded()
        refreshWidgetSnapshot()
        if shouldBackfillCacheSummary {
            cacheSaveQueue.async { [cacheStore = self.cacheStore, workouts] in
                cacheStore.saveSummary(for: workouts)
            }
        }
    }

    private func markHealthAuthorizationVerifiedFromCachedWorkoutsIfNeeded() {
        guard workouts.contains(where: { !$0.isStravaSource && !$0.isRouteCollectionSource }) else {
            return
        }

        store.markAuthorizationVerified()
    }

    private func recoverHealthAuthorizationIfNeeded(showsLoadingIndicator: Bool) {
        guard store.authorizationState == .needsAttention,
              !isHealthSyncInProgress,
              !isHealthAuthorizationRecoveryCheckInProgress else {
            return
        }

        isHealthAuthorizationRecoveryCheckInProgress = true
        store.authorizationRequestAvailability { [weak self] result in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isHealthAuthorizationRecoveryCheckInProgress = false
                guard self.store.authorizationState == .needsAttention,
                      !self.isHealthSyncInProgress else {
                    return
                }

                switch result {
                case .success(.settingsRequired):
                    self.loadAuthorizedHealthWorkouts(showsLoadingIndicator: showsLoadingIndicator)
                case .success(.canRequest), .failure:
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                }
            }
        }
    }

    private func loadAuthorizedHealthWorkouts(showsLoadingIndicator: Bool = true) {
        guard !isHealthSyncInProgress else {
            if showsLoadingIndicator {
                showHealthSyncLoadingIndicatorIfNeeded()
            }
            return
        }

        isHealthSyncInProgress = true
        setHealthNewDataSyncInProgress(false)
        isHealthSyncShowingLoadingIndicator = showsLoadingIndicator
        if showsLoadingIndicator {
            beginLoadingOperation()
        } else {
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
        }
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
                    self.setHealthNewDataSyncInProgress(false)
                    self.isHealthSyncShowingLoadingIndicator = true
                    self.beginLoadingOperation()
                    self.loadIncrementalHealthWorkouts()
                }
            case .failure(let error):
                print("PTrack HealthKit: authorization failed: \(error)")
                Task { @MainActor in
                    self.isHealthSyncInProgress = false
                    self.setHealthNewDataSyncInProgress(false)
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                    self.presentHealthAuthorizationError(error)
                }
            }
        }
    }

    private func loadAuthorizedStravaWorkouts(showsLoadingIndicator: Bool = true) {
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
            presentsErrors: false,
            showsLoadingIndicator: showsLoadingIndicator
        )
    }

    private func loadStravaWorkouts(
        excludingStravaActivityIDs: Set<Int64>,
        after startDate: Date? = nil,
        presentsErrors: Bool,
        showsLoadingIndicator: Bool = true
    ) {
        guard !isStravaSyncInProgress else {
            if showsLoadingIndicator {
                showStravaSyncLoadingIndicatorIfNeeded()
            }
            return
        }

        isStravaSyncInProgress = true
        setStravaNewDataSyncInProgress(false)
        isStravaSyncShowingLoadingIndicator = showsLoadingIndicator
        if showsLoadingIndicator {
            beginLoadingOperation()
        } else {
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
        }
        print(
            "PTrack Strava: starting import, after: \(Self.debugDateString(startDate)), excluding cached activities: \(excludingStravaActivityIDs.count)"
        )

        Task { [weak self] in
            do {
                let importedWorkouts = try await StravaManager.shared.loadTrackedWorkouts(
                    after: startDate,
                    excludingStravaActivityIDs: excludingStravaActivityIDs,
                    onNewDataDetected: { [weak self] _ in
                        await MainActor.run {
                            self?.setStravaNewDataSyncInProgress(true)
                        }
                    },
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
                self.markStravaHistoricalBackfillCompletedIfNeeded(after: startDate)

                print(
                    "PTrack Strava: import completed, loaded routes: \(importedWorkouts.count), flushed: \(didFlushPendingWorkouts)"
                )
                self.isStravaSyncInProgress = false
                self.setStravaNewDataSyncInProgress(false)
                if self.isStravaSyncShowingLoadingIndicator {
                    self.isStravaSyncShowingLoadingIndicator = false
                    self.endLoadingOperation()
                } else {
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                }
            } catch {
                guard let self else {
                    return
                }

                print("PTrack Strava: import failed: \(error)")
                self.isStravaSyncInProgress = false
                self.setStravaNewDataSyncInProgress(false)
                if self.isStravaSyncShowingLoadingIndicator {
                    self.isStravaSyncShowingLoadingIndicator = false
                    self.endLoadingOperation()
                } else {
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                }
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
        guard UserDefaults.standard.bool(forKey: DefaultsKey.stravaHistoricalBackfillCompleted) else {
            print("PTrack Strava: historical backfill not completed; requesting full activity history")
            return nil
        }

        let latestStartDate = workouts
            .filter { $0.stravaActivityID != nil }
            .map(\.startDate)
            .max()

        return latestStartDate?.addingTimeInterval(-stravaIncrementalLookback)
    }

    private func markStravaHistoricalBackfillCompletedIfNeeded(after startDate: Date?) {
        guard startDate == nil,
              !UserDefaults.standard.bool(forKey: DefaultsKey.stravaHistoricalBackfillCompleted) else {
            return
        }

        UserDefaults.standard.set(true, forKey: DefaultsKey.stravaHistoricalBackfillCompleted)
        print("PTrack Strava: historical backfill marked completed")
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
            onNewDataDetected: { [weak self] _ in
                Task { @MainActor in
                    self?.setHealthNewDataSyncInProgress(true)
                }
            },
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
        restorePersistedRouteBookModeIfNeeded()
        return true
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
                } else {
                    self.refreshWidgetSnapshot()
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

    private func refreshWidgetSnapshot() {
        PTrackWidgetSnapshotStore.refresh(with: workouts)
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

    private func handleLoadResult(_ result: Result<Int, Error>) {
        isHealthSyncInProgress = false
        setHealthNewDataSyncInProgress(false)
        let didFlushPendingWorkouts = flushPendingWorkouts()
        switch result {
        case .success(let count):
            print("PTrack HealthKit: route query completed, loaded routes: \(count)")
            newWorkoutBadgeStore.markInitialSyncCompleted()
        case .failure(let error):
            print("PTrack HealthKit: route query failed: \(error)")
        }
        if isHealthSyncShowingLoadingIndicator {
            isHealthSyncShowingLoadingIndicator = false
            endLoadingOperation()
        } else {
            updateHeaderReadAuthorizationState()
            updateEmptyDataSourceVisibility()
        }
        if didFlushPendingWorkouts {
            scheduleCacheSave(delay: 0)
        }
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

        guard !isHealthSyncInProgress else {
            return
        }

        requestHealthAuthorizationAndLoadWorkouts()
    }

    private func requestHealthAuthorizationIfAvailable() {
        guard !isHealthSyncInProgress else {
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
                    self.presentHealthAuthorizationSettingsAlert()
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                case .failure(let error):
                    self.presentHealthAuthorizationError(error)
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                }
            }
        }
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
              let activeWorkoutID = RouteBookMode.activeWorkoutID,
              let workout = workouts.first(where: { $0.id == activeWorkoutID }) else {
            return
        }

        enterRouteBookMode(with: workout, persists: false)
    }

    private func enterRouteBookMode(with workout: TrackedWorkout, persists: Bool = true) {
        let workout = resolvedWorkoutForDetailedUse(workout)
        let coordinates = workout.displayCoordinates
        guard coordinates.count > 1 else {
            presentSimpleAlert(title: AppLocalization.text(.routeBook), message: AppLocalization.text(.unknownLocation))
            return
        }

        if persists {
            RouteBookMode.activate(workoutID: workout.id)
        }

        routeBookWorkout = workout
        isRouteBookModeActive = true
        applyRouteBookPanelDetent(.minimum, animated: false)
        updateRouteBookPanelText()
        applyRouteBookInterfaceState()

        drawRouteBookRoute(coordinates)
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
            routeBookReplayRulerView.configure(
                totalDistanceText: routeBookReplayTotalDistanceText(totalMeters: 0),
                elevationSamples: []
            )
            routeBookReplayRulerView.setProgress(0)
            return
        }

        routeBookPanelDistanceLabel.text = routeBookPanelDistanceText(for: routeBookWorkout)
        routeBookPanelDistanceLabel.isHidden = routeBookPanelDistanceLabel.text == nil
        configureRouteBookReplayRuler(for: routeBookWorkout)
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

    private func configureRouteBookReplayRuler(for workout: TrackedWorkout) {
        let routeCoordinates = workout.routeDetailCoordinates
        let coordinates = CoordinateTransformer.displayCoordinates(for: routeCoordinates.map(\.coordinate))
        let replayDistances = routeBookCumulativeDistances(for: coordinates)
        let totalDistance = workout.distanceMeters > 0
            ? workout.distanceMeters
            : (replayDistances.last ?? 0)
        let elevationSamples = routeBookElevationSamples(
            distances: replayDistances,
            altitudes: routeCoordinates.map(\.altitudeMeters),
            maximumCount: routeBookMaximumElevationSampleCount
        )

        routeBookReplayRulerView.configure(
            totalDistanceText: routeBookReplayTotalDistanceText(totalMeters: totalDistance),
            elevationSamples: elevationSamples
        )
        routeBookReplayRulerView.setProgress(0)
        routeBookReplayCoordinates = coordinates
        routeBookReplayDistances = replayDistances
        if selectedRouteBookPanelDetent == .medium {
            updateRouteBookReplayProgressForCurrentLocation()
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

    private func routeBookCumulativeDistances(
        for coordinates: [CLLocationCoordinate2D]
    ) -> [CLLocationDistance] {
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

    private func routeBookElevationSamples(
        distances: [CLLocationDistance],
        altitudes: [Double?],
        maximumCount: Int
    ) -> [RouteElevationSample] {
        guard distances.count == altitudes.count else {
            return []
        }

        let samples = altitudes.enumerated().compactMap { index, altitude -> RouteElevationSample? in
            guard let altitude else {
                return nil
            }
            return RouteElevationSample(distanceMeters: distances[index], altitudeMeters: altitude)
        }

        return routeBookDownsampleElevationSamples(samples, maximumCount: maximumCount)
    }

    private func routeBookDownsampleElevationSamples(
        _ samples: [RouteElevationSample],
        maximumCount: Int
    ) -> [RouteElevationSample] {
        guard samples.count > maximumCount, maximumCount > 2 else {
            return samples
        }

        let step = Double(samples.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            samples[Int(round(Double(index) * step))]
        }
    }

    private func updateRouteBookReplayProgressForCurrentLocation() {
        guard let progress = routeBookReplayProgressForCurrentLocation() else {
            return
        }

        routeBookReplayRulerView.setProgress(progress)
    }

    private func routeBookReplayProgressForCurrentLocation() -> CGFloat? {
        guard routeBookReplayCoordinates.count == routeBookReplayDistances.count,
              routeBookReplayCoordinates.count > 1,
              let totalDistance = routeBookReplayDistances.last,
              totalDistance > 0,
              let location = routeBookCurrentLocation() else {
            return nil
        }

        let displayCoordinate = CoordinateTransformer.displayCoordinate(for: location.coordinate)
        guard CLLocationCoordinate2DIsValid(displayCoordinate) else {
            return nil
        }

        let userPoint = MKMapPoint(displayCoordinate)
        var nearestDistanceSquared = Double.greatestFiniteMagnitude
        var nearestRouteDistance: CLLocationDistance = 0

        for index in 0..<(routeBookReplayCoordinates.count - 1) {
            let startPoint = MKMapPoint(routeBookReplayCoordinates[index])
            let endPoint = MKMapPoint(routeBookReplayCoordinates[index + 1])
            let deltaX = endPoint.x - startPoint.x
            let deltaY = endPoint.y - startPoint.y
            let segmentLengthSquared = deltaX * deltaX + deltaY * deltaY
            let projection: Double
            if segmentLengthSquared > 0 {
                let userDeltaX = userPoint.x - startPoint.x
                let userDeltaY = userPoint.y - startPoint.y
                projection = min(max((userDeltaX * deltaX + userDeltaY * deltaY) / segmentLengthSquared, 0), 1)
            } else {
                projection = 0
            }

            let projectedX = startPoint.x + deltaX * projection
            let projectedY = startPoint.y + deltaY * projection
            let distanceX = userPoint.x - projectedX
            let distanceY = userPoint.y - projectedY
            let distanceSquared = distanceX * distanceX + distanceY * distanceY
            guard distanceSquared < nearestDistanceSquared else {
                continue
            }

            nearestDistanceSquared = distanceSquared
            let segmentRouteDistance = routeBookReplayDistances[index + 1] - routeBookReplayDistances[index]
            nearestRouteDistance = routeBookReplayDistances[index] + segmentRouteDistance * projection
        }

        return CGFloat(min(max(nearestRouteDistance / totalDistance, 0), 1))
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

    private func drawRouteBookRoute(_ coordinates: [CLLocationCoordinate2D]) {
        if let routeBookPolyline {
            routeBookMapView.removeOverlay(routeBookPolyline)
        }

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        routeBookPolyline = polyline
        routeBookMapView.addOverlay(polyline, level: .aboveLabels)
        resetRouteBookMapHeading(animated: false)
        routeBookMapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(
                top: 150,
                left: 44,
                bottom: routeBookPanelContentHeight(for: .medium) + 44 + AppMapContainerView.defaultBottomLogoAvoidanceOffset,
                right: 44
            ),
            animated: false
        )
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
        routeBookWorkout = nil
        RouteBookMode.clearActiveWorkout()
        shouldCenterRouteBookOnNextLocation = false
        routeBookLastLocation = nil
        routeBookLastHeadingDegrees = nil
        routeBookHeadingDisplayDegrees = nil
        stopRouteBookLocationAndHeadingUpdates()
        routeBookMapView.setUserTrackingMode(.none, animated: false)
        routeBookMapView.showsUserLocation = false
        if let routeBookPolyline {
            routeBookMapView.removeOverlay(routeBookPolyline)
        }
        routeBookPolyline = nil
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
        setRouteBookScaleViewVisible(isRouteBookModeActive)
        routeGridView.isHidden = isRouteBookModeActive
        collectionView.isHidden = isRouteBookModeActive
        headerView.backgroundColor = isRouteBookModeActive ? .clear : AppColors.solidBackground
        headerBlurView.isHidden = true
        updateRouteBookHeaderColors()
        setNeedsStatusBarAppearanceUpdate()

        if isRouteBookModeActive {
            emptyDataSourceView.isHidden = true
            view.bringSubviewToFront(headerView)
            view.bringSubviewToFront(routeBookScaleView)
            view.bringSubviewToFront(routeBookLocateButton)
            presentRouteBookPanelSheetIfNeeded()
        } else {
            dismissRouteBookPanelSheetIfNeeded(animated: false)
            view.bringSubviewToFront(headerView)
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
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard mapView === routeBookMapView,
              annotation is MKUserLocation else {
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

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let renderer = AppMapStyle.renderer(for: overlay) {
            return renderer
        }

        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }

        let renderer = RouteDirectionPolylineRenderer(polyline: polyline)
        renderer.strokeColor = .black
        renderer.directionIndicatorColor = .black
        renderer.lineWidth = 2.4
        renderer.lineJoin = .round
        renderer.lineCap = .round
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
        print("PTrack RouteBook: location update failed: \(error)")
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

    private var mode: HomeDataSourceEmptyMode = .authorization
    private let stackView = UIStackView()
    private let messageLabel = UILabel()
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
        switch state {
        case .authorized:
            appleHealthCard.setStatusIndicatorColor(AppColors.movinnGreen)
        case .notDetermined, .needsAttention:
            appleHealthCard.setStatusIndicatorColor(nil)
        }
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
        messageLabel.isHidden = mode == .authorization
        isUserInteractionEnabled = mode == .authorization
        updateMessageText()
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

        privacyLabel.textColor = .secondaryLabel
        privacyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        privacyLabel.numberOfLines = 0
        privacyLabel.textAlignment = .left

        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.isHidden = true

        appleHealthCard.addAction(UIAction { [weak self] _ in
            self?.onAppleHealthTap?()
        }, for: .touchUpInside)
        stravaCard.addAction(UIAction { [weak self] _ in
            self?.onStravaTap?()
        }, for: .touchUpInside)

        addSubview(stackView)
        addSubview(messageLabel)
        stackView.addArrangedSubview(appleHealthCard)
        stackView.addArrangedSubview(stravaCard)
        stackView.setCustomSpacing(16, after: stravaCard)
        stackView.addArrangedSubview(privacyLabel)

        stackView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview()
        }

        messageLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
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
