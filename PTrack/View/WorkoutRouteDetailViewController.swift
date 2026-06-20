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
        let replayDistances: [CLLocationDistance]
        let replayAltitudes: [Double?]
        let elevationSamples: [RouteElevationSample]
        let totalDistanceMeters: CLLocationDistance
    }

    let workout: TrackedWorkout
    private let presentationMode: PresentationMode
    private let mediaStore = RouteMediaStore()
    private let mapContainerView = AppMapContainerView()
    private var mapView: MKMapView { mapContainerView.mapView }
    private let mapToneOverlay = AppMapStyle.makeToneOverlay()
    private let routePreparationQueue = DispatchQueue(label: "studio.pj.PTrack.route-detail-prepare", qos: .userInitiated)
    private let gpxExportQueue = DispatchQueue(label: "studio.pj.PTrack.gpx-export", qos: .userInitiated)
    private let routeLoadingView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let routeLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private let routeLoadingLabel = UILabel()
    private let gpxExportLoadingView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let gpxExportLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private let gpxExportLoadingLabel = UILabel()
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let navigationBackgroundMask = CAGradientLayer()
    private let panelShadowView = UIView()
    private let panelView = UIVisualEffectView(effect: WorkoutRouteDetailViewController.makePanelGlassEffect())
    private let handleTouchView = UIView()
    private let handleView = UIView()
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
    private lazy var panelPanGestureRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanelPan(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()
    private var panelHeightConstraint: Constraint?
    private var primaryContentTopConstraint: Constraint?
    private var selectedPanelDetent: PanelDetent = .minimum
    private var hasFittedRoute = false
    private var panStartHeight: CGFloat = 0
    var routeMediaItems: [RouteMediaItem] = []
    private var replayCoordinates: [CLLocationCoordinate2D] = []
    private var replayDistances: [CLLocationDistance] = []
    private var replayAltitudes: [Double?] = []
    private var replayAnnotation: RouteReplayAnnotation?
    private var routePolyline: MKPolyline?
    private var selectedMapStyle = AppMapDisplayStyleStore.shared.routeDetailStyle()
    private var resolvedNavigationTitle: String?
    private var lastObservedPhotoAuthorizationState: PhotoLibraryAuthorizationState?
    private var hasDisplayedRouteMediaAnnotations = false
    private var hasStartedRouteLoading = false
    private var hasStartedDeferredDetailLoading = false
    private var isExportingGPX = false

    private let minimumPanelHeight: CGFloat = 68
    private let mediumPanelHeight: CGFloat = 200
    private let calorieRiceViewHeight: CGFloat = 88
    private let calorieRiceTopSpacing: CGFloat = 12
    private let panelHandleTouchHeight: CGFloat = 32
    private let primaryContentSize: CGFloat = 28
    private let expandedPrimaryContentTop: CGFloat = 33
    private let minimumPrimaryContentScale: CGFloat = 0.88
    private let navigationBackgroundHeight: CGFloat = 124
    private let mapBottomExtension = AppMapContainerView.defaultBottomLogoAvoidanceOffset
    private let maximumElevationSampleCount = 120

    private var panelCaloriesKilocalories: Double? {
        guard let calories = workout.activeEnergyBurnedKilocalories, calories > 0 else {
            return nil
        }

        return calories
    }

    init(workout: TrackedWorkout, presentationMode: PresentationMode = .workout) {
        self.workout = workout
        self.presentationMode = presentationMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makePanelGlassEffect() -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = true
            effect.tintColor = UIColor.white.withAlphaComponent(0.16)
            return effect
        }

        return UIBlurEffect(style: .systemThinMaterialLight)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureNavigationItem()
        registerLanguageObserver()
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
        NotificationCenter.default.removeObserver(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .darkContent
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
        startDeferredDetailLoadingIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNavigationBackgroundMask()
        updatePanelShadowPath()
        fitRouteIfNeeded()
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
        menuChildren.append(exportGPXAction)

        return UIMenu(
            title: "",
            children: menuChildren
        )
    }

    private func showRouteShare() {
        let shareViewController = WorkoutRouteShareViewController(
            workout: workout,
            initialMediaItems: routeMediaItems
        )
        navigationController?.pushViewController(shareViewController, animated: true)
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
        present(alertController, animated: true)
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
        let calendar = Calendar.current
        let workoutDay = calendar.startOfDay(for: workout.startDate)
        let today = calendar.startOfDay(for: Date())
        let dayDifference = calendar.dateComponents([.day], from: workoutDay, to: today).day

        switch dayDifference {
        case 0:
            return AppLocalization.text(.today)
        case 1:
            return AppLocalization.text(.yesterday)
        case 2:
            return AppLocalization.text(.dayBeforeYesterday)
        default:
            return formattedNavigationWorkoutDate()
        }
    }

    private func formattedNavigationWorkoutDate() -> String {
        let language = AppLanguageStore.shared.language
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current

        switch language {
        case .chinese:
            formatter.locale = Locale(identifier: "zh_Hans")
            formatter.dateFormat = "yyyy 年 M 月 d 日"
        case .japanese:
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "yyyy年M月d日"
        case .korean:
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "yyyy년 M월 d일"
        case .english:
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMM d, yyyy"
        }

        return formatter.string(from: workout.startDate)
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

    private func configureRouteLoadingView() {
        routeLoadingView.isHidden = true
        routeLoadingView.alpha = 0
        routeLoadingView.layer.cornerRadius = 16
        routeLoadingView.layer.cornerCurve = .continuous
        routeLoadingView.layer.masksToBounds = true
        routeLoadingView.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.16)

        routeLoadingIndicator.hidesWhenStopped = true

        routeLoadingLabel.text = AppLocalization.text(.routeLoading)
        routeLoadingLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        routeLoadingLabel.textColor = UIColor.black.withAlphaComponent(0.72)
        routeLoadingLabel.textAlignment = .center

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
        gpxExportLoadingView.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.16)

        gpxExportLoadingIndicator.hidesWhenStopped = true

        gpxExportLoadingLabel.text = AppLocalization.text(.gpxExporting)
        gpxExportLoadingLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        gpxExportLoadingLabel.textColor = UIColor.black.withAlphaComponent(0.72)
        gpxExportLoadingLabel.textAlignment = .center

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

    private func updateNavigationBackgroundMask() {
        navigationBackgroundMask.frame = navigationBackgroundView.bounds
        navigationBackgroundMask.startPoint = CGPoint(x: 0.5, y: 0)
        navigationBackgroundMask.endPoint = CGPoint(x: 0.5, y: 1)
    }

    private func applyMapStyle(_ style: AppMapDisplayStyle) {
        guard style != selectedMapStyle else {
            return
        }

        selectedMapStyle = style
        AppMapDisplayStyleStore.shared.setRouteDetailStyle(style)
        AppMapStyle.apply(style, to: mapView)
        AppMapStyle.setToneOverlay(mapToneOverlay, visible: style == .appDefault, on: mapView)
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
            coordinate = coordinates.first ?? fallbackCoordinates.first
        case .end:
            coordinate = coordinates.last ?? fallbackCoordinates.last
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
        navigationController?.popToRootViewController(animated: true)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: RouteBookMode.didSelectWorkoutNotification,
                object: self,
                userInfo: [RouteBookMode.workoutUserInfoKey: selectedWorkout]
            )
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
                guard let self else {
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
            present(activityViewController, animated: true)
        case let .failure(error):
            showAlert(title: AppLocalization.text(.gpxExportFailed), message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String? = nil) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .default))
        present(alertController, animated: true)
    }

    private func configurePanelView() {
        let caloriesKilocalories = panelCaloriesKilocalories
        let isRouteCollectionPanel = presentationMode == .routeCollection

        panelShadowView.backgroundColor = .clear
        panelShadowView.layer.cornerRadius = 32
        panelShadowView.layer.cornerCurve = .continuous
        panelShadowView.layer.shadowColor = UIColor.black.cgColor
        panelShadowView.layer.shadowOpacity = 0.18
        panelShadowView.layer.shadowRadius = 28
        panelShadowView.layer.shadowOffset = CGSize(width: 0, height: 12)

        panelView.layer.cornerRadius = 32
        panelView.layer.cornerCurve = .continuous
        panelView.layer.masksToBounds = true
        panelView.layer.borderColor = UIColor.white.withAlphaComponent(0.46).cgColor
        panelView.layer.borderWidth = 0.8
        panelView.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        panelView.contentView.addGestureRecognizer(panelPanGestureRecognizer)

        handleView.backgroundColor = UIColor.black.withAlphaComponent(0.24)
        handleView.layer.cornerRadius = 2

        iconView.image = UIImage(systemName: workout.symbolName)
        iconView.tintColor = UIColor.black.withAlphaComponent(0.9)
        iconView.contentMode = .scaleAspectFit
        iconView.isHidden = isRouteCollectionPanel
        titleStackView.isHidden = isRouteCollectionPanel

        updatePanelText()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = UIColor.black.withAlphaComponent(0.92)
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
        distanceLabel.textColor = UIColor.black.withAlphaComponent(0.92)
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
        detailStackView.alpha = 0

        replayRulerView.configure(totalDistanceText: replayTotalDistanceText(totalMeters: workout.distanceMeters))
        replayRulerView.addTarget(self, action: #selector(handleReplayProgressChanged(_:)), for: .valueChanged)

        detailStackView.addArrangedSubview(replayRulerView)
        if let caloriesKilocalories {
            calorieRiceView.configure(caloriesKilocalories: caloriesKilocalories)
            detailStackView.addArrangedSubview(calorieRiceView)
        }

        view.addSubview(panelShadowView)
        view.addSubview(panelView)
        panelView.contentView.addSubview(handleTouchView)
        handleTouchView.addSubview(handleView)
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
            durationLabel.setContentHuggingPriority(.required, for: .horizontal)
            metricsStackView.addArrangedSubview(distanceLabel)
            metricsStackView.addArrangedSubview(metricsSpacerView)
            metricsStackView.addArrangedSubview(durationLabel)
        } else {
            metricsStackView.addArrangedSubview(distanceLabel)
            metricsStackView.addArrangedSubview(durationLabel)
        }

        panelView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(10)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(10)
            panelHeightConstraint = make.height.equalTo(panelHeight(for: .minimum)).constraint
        }

        panelShadowView.snp.makeConstraints { make in
            make.edges.equalTo(panelView)
        }

        handleTouchView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(panelHandleTouchHeight)
        }

        handleView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(9)
            make.width.equalTo(42)
            make.height.equalTo(4)
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
            make.top.equalTo(iconView.snp.bottom).offset(24)
        }

        replayRulerView.snp.makeConstraints { make in
            make.height.equalTo(98)
        }

        if caloriesKilocalories != nil {
            calorieRiceView.snp.makeConstraints { make in
                make.height.equalTo(calorieRiceViewHeight)
            }
        }

        updatePrimaryContentScale(for: panelHeight(for: .minimum))
    }

    private func updatePanelShadowPath() {
        panelShadowView.layer.shadowPath = UIBezierPath(
            roundedRect: panelShadowView.bounds,
            cornerRadius: 32
        ).cgPath
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
                guard let self else {
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
        let measuredDistance = replayDistances.last ?? workout.distanceMeters
        let totalDistanceMeters = workout.distanceMeters > 0 ? workout.distanceMeters : measuredDistance
        let elevationSamples = routeElevationSamples(
            distances: replayDistances,
            altitudes: replayAltitudes,
            maximumCount: maximumElevationSampleCount
        )

        return PreparedRoute(
            coordinates: coordinates,
            routeCoordinates: routeCoordinates,
            replayDistances: replayDistances,
            replayAltitudes: replayAltitudes,
            elevationSamples: elevationSamples,
            totalDistanceMeters: totalDistanceMeters
        )
    }

    private func applyPreparedRoute(_ preparedRoute: PreparedRoute) {
        configureReplayRoute(with: preparedRoute)

        let coordinates = preparedRoute.coordinates
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        routePolyline = polyline
        hasFittedRoute = false
        mapView.addOverlay(polyline, level: .aboveLabels)

        mapView.addAnnotations([
            RouteEndpointAnnotation(coordinate: coordinates[0], kind: .start),
            RouteEndpointAnnotation(coordinate: coordinates[coordinates.count - 1], kind: .end)
        ])

        setRouteLoadingVisible(false)
        fitRouteIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.displayRouteMediaIfRouteReady()
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

    private func loadRouteMedia() {
        mediaStore.loadMedia(for: workout) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let mediaItems):
                Task { @MainActor in
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
        guard routePolyline != nil,
              !hasDisplayedRouteMediaAnnotations,
              !routeMediaItems.isEmpty else {
            return
        }

        hasDisplayedRouteMediaAnnotations = true
        mapView.addAnnotations(routeMediaItems.map(RouteMediaAnnotation.init))
    }

    @objc private func handlePanelPan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            panStartHeight = panelCurrentHeight()
        case .changed:
            let translationY = recognizer.translation(in: view).y
            let proposedHeight = min(
                max(panStartHeight - translationY, panelHeight(for: .minimum)),
                panelHeight(for: .medium)
            )
            updatePanel(height: proposedHeight, animated: false)
        case .ended, .cancelled, .failed:
            let velocityY = recognizer.velocity(in: view).y
            let currentHeight = panelCurrentHeight()
            setPanelDetent(targetPanelDetent(for: currentHeight, velocityY: velocityY), animated: true)
        default:
            break
        }
    }

    private func panelCurrentHeight() -> CGFloat {
        panelView.bounds.height > 0 ? panelView.bounds.height : panelHeight(for: selectedPanelDetent)
    }

    private func panelHeight(for detent: PanelDetent) -> CGFloat {
        switch detent {
        case .minimum:
            return minimumPanelHeight
        case .medium:
            var height = mediumPanelHeight
            if panelCaloriesKilocalories != nil {
                height += calorieRiceTopSpacing + calorieRiceViewHeight
            }
            return height
        }
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

    private func targetPanelDetent(for height: CGFloat, velocityY: CGFloat) -> PanelDetent {
        let minimumHeight = panelHeight(for: .minimum)
        let mediumHeight = panelHeight(for: .medium)

        if velocityY < -220 {
            return .medium
        }

        if velocityY > 220 {
            return .minimum
        }

        let midpoint = (minimumHeight + mediumHeight) / 2
        return height >= midpoint ? .medium : .minimum
    }

    private func setPanelDetent(_ detent: PanelDetent, animated: Bool) {
        selectedPanelDetent = detent
        if detent == .minimum {
            removeReplayAnnotation()
            replayRulerView.setProgress(0)
        }
        updatePanel(height: panelHeight(for: detent), animated: animated)
    }

    private func updatePanel(height: CGFloat, animated: Bool) {
        let progress = panelDetailProgress(for: height)
        panelHeightConstraint?.update(offset: height)
        primaryContentTopConstraint?.update(offset: primaryContentTopOffset(for: height))

        let changes = {
            self.detailStackView.alpha = min(max(progress, 0), 1)
            self.updatePrimaryContentScale(for: height)
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
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            changes()
        }
    }

    @objc private func handleReplayProgressChanged(_ sender: WorkoutRouteReplayRulerView) {
        guard let replayState = replayState(for: sender.progress) else {
            return
        }

        let statusText = replayStatusText(
            distanceMeters: replayState.distanceMeters,
            altitudeMeters: replayState.altitudeMeters
        )

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
                isFacingLeft: replayFacingLeft(at: 0)
            )
        }

        let targetDistance = CLLocationDistance(progress) * totalDistance
        let index = nearestReplayCoordinateIndex(for: targetDistance)
        return ReplayState(
            coordinate: replayCoordinates[index],
            distanceMeters: replayDistances[index],
            altitudeMeters: replayAltitude(at: index),
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
            maximumCount: maximumElevationSampleCount
        )
    }

    private static func routeElevationSamples(
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
        return (0..<maximumCount).map { index in
            samples[Int(round(Double(index) * step))]
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

        durationLabel.text = panelDurationText()
        durationLabel.isHidden = durationLabel.text == nil
    }

    private func panelDistanceText() -> String? {
        if workout.distanceMeters >= 1000 {
            return String(format: "%.2f km", workout.distanceMeters / 1000)
        } else if workout.distanceMeters > 0 {
            return AppLocalization.format(.distanceMetersFormat, workout.distanceMeters)
        } else {
            return nil
        }
    }

    private func panelDurationText() -> String? {
        guard let durationSeconds = workout.durationSeconds, durationSeconds > 0 else {
            return nil
        }

        return workout.durationText
    }

    private func replayStatusText(
        distanceMeters: CLLocationDistance,
        altitudeMeters: Double?
    ) -> String {
        let distanceText: String
        if distanceMeters >= 1000 {
            distanceText = String(format: "%.2f km", distanceMeters / 1000)
        } else {
            distanceText = String(format: "%.0f m", max(distanceMeters, 0))
        }

        let altitudeText = altitudeMeters.map { "\(Int(round($0))) m" } ?? "-- m"
        return "\(distanceText) · \(altitudeText)"
    }
}

extension WorkoutRouteDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === panelPanGestureRecognizer else {
            return true
        }

        let rulerLocation = touch.location(in: replayRulerView)
        return !replayRulerView.bounds.contains(rulerLocation)
    }
}
