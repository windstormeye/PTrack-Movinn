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
    private var activeLoadingOperationCount = 0
    private var isCacheLoadInProgress = false
    private var isHealthSyncInProgress = false
    private var isStravaSyncInProgress = false
    private var isHealthAuthorizationRequestedFromEmptyState = false
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
    private let headerBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let headerBlurMask = CAGradientLayer()
    private let titleLabel = UILabel()
    private let titleAccentLabel = UILabel()
    private let totalDistanceLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let moreButton = UIButton(type: .system)
    private let routeCollectionBadgeLabel = PaddingLabel(contentInsets: UIEdgeInsets(top: 1.5, left: 4, bottom: 1.5, right: 4))
    private let routeBookLocateButton = UIButton(type: .system)
    private let emptyDataSourceView = HomeDataSourceEmptyView()
    private let columnCount: CGFloat = 3
    private let itemSpacing: CGFloat = 12
    private let lineSpacing: CGFloat = 2
    private let headerBottomPadding: CGFloat = 8
    private let sectionInset = UIEdgeInsets(top: 12, left: 12, bottom: 16, right: 12)
    private let pendingWorkoutFlushDelay: TimeInterval = 0.35
    private let activeScrollFlushDelay: TimeInterval = 0.45
    private let cacheSaveDebounceDelay: TimeInterval = 1.0
    private let cacheLoadPreviewBatchSize = 32
    private let stravaIncrementalLookback: TimeInterval = 7 * 24 * 60 * 60
    private let pullRefreshTriggerDistance: CGFloat = 86
    private var isRouteBookModeActive = false
    private var routeBookWorkout: TrackedWorkout?
    private var routeBookPolyline: MKPolyline?
    private var shouldCenterRouteBookOnNextLocation = false
    private var routeBookLastLocation: CLLocation?
    private var routeBookLastHeadingDegrees: CLLocationDirection?
    private var routeBookHeadingDisplayDegrees: CLLocationDirection?
    private var shouldClearRouteImportIndicatorsOnNextHomeAppear = false

    deinit {
        pendingFlushWorkItem?.cancel()
        pendingCacheSaveWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
        store.progressHandler = { message in
            print("PTrack HealthKit: \(message)")
        }
        importPendingSharedRoutesIfNeeded()
        loadCachedWorkoutsThenSynchronize()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHeaderBlurMask()
        updateFullScreenInsets()
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
        openRouteCollectionIfRequested()
        DispatchQueue.main.async { [weak self] in
            self?.updateFullScreenInsets(force: true)
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
            columns: columnCount,
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
        routeGridView.onColumnSnapFinished = { [weak self] in
            self?.flushPendingWorkouts()
        }

        collectionView = routeGridView.collectionView

        view.addSubview(routeGridView)

        routeGridView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
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

        configureRouteBookLocateButton()
    }

    private func configureRouteBookLocateButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(
            systemName: "location.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        configuration.baseForegroundColor = .label
        configuration.baseBackgroundColor = .white.withAlphaComponent(0.92)
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
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(30)
            make.size.equalTo(48)
        }
    }

    private func configureHeaderView() {
        headerView.isUserInteractionEnabled = true
        headerView.backgroundColor = .white

        headerBlurView.isHidden = true
        headerBlurView.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.42)
        headerBlurMask.colors = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0.78).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ]
        headerBlurMask.locations = [0, 0.58, 1]
        headerBlurView.layer.mask = headerBlurMask

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

        routeCollectionBadgeLabel.snp.makeConstraints { make in
            make.trailing.equalTo(moreButton.snp.trailing).offset(2)
            make.bottom.equalTo(moreButton.snp.top).offset(5)
        }

        updateTotalDistanceText()
        configureRouteBookScaleView()
    }

    private func configureRouteCollectionBadgeLabel() {
        routeCollectionBadgeLabel.text = AppLocalization.text(.newRoute)
        routeCollectionBadgeLabel.textColor = UIColor.black.withAlphaComponent(0.86)
        routeCollectionBadgeLabel.font = .systemFont(ofSize: 8, weight: .bold)
        routeCollectionBadgeLabel.backgroundColor = AppColors.movinnGreen
        routeCollectionBadgeLabel.layer.cornerRadius = 5
        routeCollectionBadgeLabel.layer.masksToBounds = true
        routeCollectionBadgeLabel.isUserInteractionEnabled = false
        routeCollectionBadgeLabel.isHidden = true
    }

    private func updateHeaderBlurMask() {
        headerBlurMask.frame = headerBlurView.bounds
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
        let sportsCareerAction = UIAction(
            title: AppLocalization.text(.sportsCareer),
            image: UIImage(systemName: "chart.bar")
        ) { [weak self] _ in
            self?.showSportsCareer()
        }

        let hasUnseenRoute = SharedRouteImportInbox.hasUnseenRoute
        let routeCollectionAction = UIAction(
            title: AppLocalization.text(.routeCollection),
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

        let moreAction = UIAction(
            title: AppLocalization.text(.more),
            image: UIImage(systemName: "ellipsis")
        ) { [weak self] _ in
            self?.showMoreSettings()
        }

        return UIMenu(children: [sportsCareerAction, routeCollectionAction, heatmapAction, moreAction])
    }

    private func updateHeaderMoreButtonMode() {
        var buttonConfiguration = moreButton.configuration ?? .plain()
        buttonConfiguration.image = UIImage(
            systemName: isRouteBookModeActive ? "xmark" : "ellipsis",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: isRouteBookModeActive ? 14 : 18,
                weight: isRouteBookModeActive ? .regular : .semibold
            )
        )
        buttonConfiguration.contentInsets = isRouteBookModeActive
            ? NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
            : NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 7)
        moreButton.configuration = buttonConfiguration
        moreButton.tintColor = .label
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
        routeCollectionBadgeLabel.isHidden = isRouteBookModeActive || !SharedRouteImportInbox.hasUnseenRoute
        if !isRouteBookModeActive {
            moreButton.menu = makeHeaderMoreMenu()
        }
    }

    private func routeCollectionMenuImage(hasUnseenRoute: Bool) -> UIImage? {
        guard hasUnseenRoute else {
            return UIImage(systemName: "square.and.arrow.down")
        }

        return UIImage(systemName: "square.and.arrow.down.fill")?
            .withTintColor(AppColors.movinnGreen, renderingMode: .alwaysOriginal)
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

    private var hasReadableDataSourceAuthorization: Bool {
        store.authorizationState == .authorized || StravaManager.shared.hasStoredAuthorization
    }

    private func updateHeaderReadAuthorizationState() {
        totalDistanceLabel.isHidden = isRouteBookModeActive || !hasReadableDataSourceAuthorization
        updateLoadingIndicatorVisibility()
        updateHeaderMoreButtonMode()
    }

    private func updateLoadingIndicatorVisibility() {
        if activeLoadingOperationCount > 0, hasReadableDataSourceAuthorization, !isRouteBookModeActive {
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
        emptyDataSourceView.updateAuthorizationState(appleHealth: store.authorizationState)
        emptyDataSourceView.isHidden = isRouteBookModeActive || !workouts.isEmpty || hasReadableDataSourceAuthorization
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
        restorePersistedRouteBookModeIfNeeded()
    }

    private func applyCachedWorkouts(_ cachedWorkouts: [TrackedWorkout]) {
        workouts = cachedWorkouts
        removeCachedAppleHealthWorkoutsConflictingWithStrava()
        knownWorkoutIDs = Set(workouts.map(\.id))
        totalDistanceMeters = workouts.reduce(0) { $0 + $1.distanceMeters }
        updateTotalDistanceText()
        collectionView.reloadData()
        prewarmInitialRouteSources()
        restorePersistedRouteBookModeIfNeeded()
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
                    self.isHealthAuthorizationRequestedFromEmptyState = false
                    self.updateHeaderReadAuthorizationState()
                    self.updateEmptyDataSourceVisibility()
                    self.presentHealthAuthorizationError(error)
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
                self.markStravaHistoricalBackfillCompletedIfNeeded(after: startDate)

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
        let wasRequestedFromEmptyState = isHealthAuthorizationRequestedFromEmptyState
        isHealthAuthorizationRequestedFromEmptyState = false
        isHealthSyncInProgress = false
        let didFlushPendingWorkouts = flushPendingWorkouts()
        switch result {
        case .success(let count):
            print("PTrack HealthKit: route query completed, loaded routes: \(count)")
            if shouldTreatEmptyHealthImportAsNeedsAttention(
                loadedCount: count,
                wasRequestedFromEmptyState: wasRequestedFromEmptyState
            ) {
                store.markAuthorizationNeedsAttention()
            }
            newWorkoutBadgeStore.markInitialSyncCompleted()
        case .failure(let error):
            print("PTrack HealthKit: route query failed: \(error)")
        }
        endLoadingOperation()
        updateHeaderReadAuthorizationState()
        if didFlushPendingWorkouts {
            scheduleCacheSave(delay: 0)
        }
    }

    private func shouldTreatEmptyHealthImportAsNeedsAttention(
        loadedCount: Int,
        wasRequestedFromEmptyState: Bool
    ) -> Bool {
        guard loadedCount == 0,
              workouts.isEmpty,
              pendingWorkouts.isEmpty,
              !StravaManager.shared.hasStoredAuthorization else {
            return false
        }

        return wasRequestedFromEmptyState || store.authorizationState == .authorized
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

    private func showWorkoutDetail(
        _ workout: TrackedWorkout,
        indexPath: IndexPath,
        cell: WorkoutRouteCell?
    ) {
        if newWorkoutBadgeStore.markSeen(workout) {
            cell?.setShowsNewBadge(false)
        }

        let detailViewController = WorkoutRouteDetailViewController(workout: workout)
        navigationController?.pushViewController(detailViewController, animated: true)
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

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let mapItem = MKMapItem(location: location, address: nil)
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
            presentHealthAuthorizationSettingsAlert()
            return
        case .notDetermined:
            break
        }

        guard !isHealthSyncInProgress else {
            return
        }

        isHealthAuthorizationRequestedFromEmptyState = true
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
        applyRouteBookInterfaceState()

        drawRouteBookRoute(coordinates)
        requestRouteBookLocationAuthorizationIfNeeded()
        updateRouteBookLocateButtonState()
        updateHeaderReadAuthorizationState()
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
                bottom: 72 + AppMapContainerView.defaultBottomLogoAvoidanceOffset,
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
        present(alertController, animated: true)
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
        present(alertController, animated: true)
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
        headerView.backgroundColor = isRouteBookModeActive ? .clear : .white
        headerBlurView.isHidden = !isRouteBookModeActive

        if isRouteBookModeActive {
            emptyDataSourceView.isHidden = true
            view.bringSubviewToFront(headerView)
            view.bringSubviewToFront(routeBookScaleView)
            view.bringSubviewToFront(routeBookLocateButton)
        } else {
            view.bringSubviewToFront(headerView)
            updateEmptyDataSourceVisibility()
        }

        updateRouteCollectionBadgeVisibility()
    }

    private func setRouteBookScaleViewVisible(_ isVisible: Bool) {
        routeBookScaleView.layer.removeAllAnimations()
        routeBookScaleView.scaleVisibility = isVisible ? .visible : .hidden
        routeBookScaleView.isHidden = !isVisible
        routeBookScaleView.alpha = isVisible ? 1 : 0
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

        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = UIColor.black.withAlphaComponent(0.34)
        renderer.lineWidth = 3
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
        let outline = UIColor.white

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
        privacyLabel.attributedText = privacyStatementAttributedText(
            AppLocalization.text(.movinnLocalDataPrivacyStatement)
        )
    }

    func updateAuthorizationState(appleHealth state: HealthWorkoutStore.AuthorizationState) {
        switch state {
        case .authorized:
            appleHealthCard.setStatusIndicatorColor(AppColors.movinnGreen)
        case .notDetermined, .needsAttention:
            appleHealthCard.setStatusIndicatorColor(nil)
        }
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

        statusIndicatorView.isHidden = true
        statusIndicatorView.layer.cornerRadius = 4
        statusIndicatorView.layer.masksToBounds = true
        statusIndicatorView.layer.borderWidth = 1
        statusIndicatorView.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor

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
