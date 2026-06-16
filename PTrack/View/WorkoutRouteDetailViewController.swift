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
    private enum PanelDetent: CaseIterable {
        case minimum
        case medium
    }

    let workout: TrackedWorkout
    private let mediaStore = RouteMediaStore()
    private let mapContainerView = AppMapContainerView()
    private var mapView: MKMapView { mapContainerView.mapView }
    private let mapToneOverlay = AppMapStyle.makeToneOverlay()
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

    init(workout: TrackedWorkout) {
        self.workout = workout
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makePanelGlassEffect() -> UIVisualEffect {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        effect.tintColor = UIColor.white.withAlphaComponent(0.16)
        return effect
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureNavigationItem()
        registerLanguageObserver()
        configureMapView()
        configureNavigationBackgroundView()
        configurePanelView()
        drawRoute()
        loadRouteLocationTitle()
        loadRouteMedia()
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

        titleLabel.text = workout.title
        dataSourceLabel.text = workout.routeDataSourceTitle
        distanceLabel.text = panelDistanceText()
        durationLabel.text = workout.durationText
        let measuredDistance = replayDistances.last ?? workout.distanceMeters
        let totalDistance = workout.distanceMeters > 0 ? workout.distanceMeters : measuredDistance
        replayRulerView.configure(
            totalDistanceText: replayTotalDistanceText(totalMeters: totalDistance),
            elevationSamples: elevationSamples()
        )

        if let caloriesKilocalories = panelCaloriesKilocalories {
            calorieRiceView.configure(caloriesKilocalories: caloriesKilocalories)
        }
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
            self?.openStartInMaps()
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
                openStartAction,
                UIMenu(title: AppLocalization.text(.mapStyle), image: UIImage(systemName: "map"), children: mapStyleActions)
            ]
        )
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

    private func openStartInMaps() {
        guard let startCoordinate = workout.displayCoordinates.first ?? workout.coordinates.first?.coordinate else {
            showAlert(title: AppLocalization.text(.startNotFound))
            return
        }

        let startLocation = CLLocation(latitude: startCoordinate.latitude, longitude: startCoordinate.longitude)
        let mapItem = MKMapItem(location: startLocation, address: nil)
        mapItem.name = AppLocalization.text(.workoutStart)

        let launchOptions: [String: Any] = [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: startCoordinate),
            MKLaunchOptionsMapSpanKey: NSValue(
                mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        ]

        guard mapItem.openInMaps(launchOptions: launchOptions) else {
            showAlert(title: AppLocalization.text(.systemMapsNotFound))
            return
        }
    }

    private func showAlert(title: String) {
        let alertController = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .default))
        present(alertController, animated: true)
    }

    private func configurePanelView() {
        let caloriesKilocalories = panelCaloriesKilocalories

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

        titleLabel.text = workout.title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = UIColor.black.withAlphaComponent(0.92)
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        dataSourceLabel.text = workout.routeDataSourceTitle
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

        metricsStackView.axis = .vertical
        metricsStackView.alignment = .trailing
        metricsStackView.spacing = 2

        distanceLabel.text = panelDistanceText()
        distanceLabel.font = distanceFont
        distanceLabel.textColor = UIColor.black.withAlphaComponent(0.92)
        distanceLabel.textAlignment = .right
        distanceLabel.adjustsFontSizeToFitWidth = true
        distanceLabel.minimumScaleFactor = 0.78
        distanceLabel.numberOfLines = 1

        durationLabel.text = workout.durationText
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
        metricsStackView.addArrangedSubview(distanceLabel)
        metricsStackView.addArrangedSubview(durationLabel)

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
            make.size.equalTo(primaryContentSize)
        }

        titleStackView.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(10)
            make.centerY.equalTo(iconView)
            make.trailing.lessThanOrEqualTo(metricsStackView.snp.leading).offset(-12)
        }

        metricsStackView.snp.makeConstraints { make in
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

    private func drawRoute() {
        let coordinates = workout.displayCoordinates
        guard coordinates.count > 1 else {
            return
        }

        configureReplayRoute(with: coordinates, routeCoordinates: workout.coordinates)

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        routePolyline = polyline
        mapView.addOverlay(polyline, level: .aboveLabels)

        mapView.addAnnotations([
            RouteEndpointAnnotation(coordinate: coordinates[0], kind: .start),
            RouteEndpointAnnotation(coordinate: coordinates[coordinates.count - 1], kind: .end)
        ])
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
                bottom: panelHeight(for: .medium) + 28 + mapBottomExtension,
                right: 32
            ),
            animated: false
        )
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
                    let annotations = mediaItems.map(RouteMediaAnnotation.init)
                    self.mapView.addAnnotations(annotations)
                }
            case .failure(let error):
                print("PTrack Photos: failed to load route media: \(error)")
            }
        }
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
        let minimumPrimaryContentTop = (minimumPanelHeight - primaryContentSize) / 2
        let progress = min(max(panelDetailProgress(for: height), 0), 1)
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

    private func configureReplayRoute(
        with coordinates: [CLLocationCoordinate2D],
        routeCoordinates: [RouteCoordinate]
    ) {
        replayCoordinates = coordinates
        replayDistances = cumulativeDistances(for: coordinates)
        replayAltitudes = routeCoordinates.map(\.altitudeMeters)

        let measuredDistance = replayDistances.last ?? workout.distanceMeters
        let totalDistance = workout.distanceMeters > 0 ? workout.distanceMeters : measuredDistance
        replayRulerView.configure(
            totalDistanceText: replayTotalDistanceText(totalMeters: totalDistance),
            elevationSamples: elevationSamples()
        )

    }

    private func cumulativeDistances(for coordinates: [CLLocationCoordinate2D]) -> [CLLocationDistance] {
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

    private func elevationSamples() -> [RouteElevationSample] {
        guard replayDistances.count == replayAltitudes.count else {
            return []
        }

        let samples = replayAltitudes.enumerated().compactMap { index, altitude -> RouteElevationSample? in
            guard let altitude else {
                return nil
            }
            return RouteElevationSample(distanceMeters: replayDistances[index], altitudeMeters: altitude)
        }

        return downsampleElevationSamples(samples, maximumCount: maximumElevationSampleCount)
    }

    private func downsampleElevationSamples(
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

    private func panelDistanceText() -> String {
        if workout.distanceMeters >= 1000 {
            return String(format: "%.2f km", workout.distanceMeters / 1000)
        } else if workout.distanceMeters > 0 {
            return AppLocalization.format(.distanceMetersFormat, workout.distanceMeters)
        } else {
            return AppLocalization.text(.unknownDistance)
        }
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
