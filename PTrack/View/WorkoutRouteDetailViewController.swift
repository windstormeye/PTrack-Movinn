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
    private let workout: TrackedWorkout
    private let mediaStore = RouteMediaStore()
    private let mapView = MKMapView()
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let navigationBackgroundMask = CAGradientLayer()
    private let panelView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let handleTouchView = UIView()
    private let handleView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let distanceLabel = UILabel()
    private let detailStackView = UIStackView()
    private let replayRulerView = WorkoutRouteReplayRulerView()
    private var panelHeightConstraint: Constraint?
    private var isPanelExpanded = false
    private var hasFittedRoute = false
    private var panStartHeight: CGFloat = 0
    private var routeMediaItems: [RouteMediaItem] = []
    private var replayCoordinates: [CLLocationCoordinate2D] = []
    private var replayDistances: [CLLocationDistance] = []
    private var replayAltitudes: [Double?] = []
    private var replayAnnotation: RouteReplayAnnotation?

    private let collapsedPanelHeight: CGFloat = 82
    private let expandedPanelHeight: CGFloat = 300
    private let navigationBackgroundHeight: CGFloat = 124
    private let maximumElevationSampleCount = 120

    init(workout: TrackedWorkout) {
        self.workout = workout
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
        configurePanelView()
        drawRoute()
        loadRouteMedia()
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
        fitRouteIfNeeded()
    }

    private func configureNavigationItem() {
        title = workout.title
        navigationItem.largeTitleDisplayMode = .never
        edgesForExtendedLayout = [.top, .bottom]
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
        mapView.mapType = .standard
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsScale = true
        mapView.backgroundColor = .systemBackground

        view.addSubview(mapView)

        mapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
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

    private func configurePanelView() {
        panelView.layer.cornerRadius = 18
        panelView.layer.masksToBounds = true

        handleView.backgroundColor = .tertiaryLabel
        handleView.layer.cornerRadius = 2
        handleTouchView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePanelPan(_:))))

        iconView.image = UIImage(systemName: workout.symbolName)
        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit

        titleLabel.text = workout.title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label

        distanceLabel.text = workout.distanceText
        distanceLabel.font = .preferredFont(forTextStyle: .headline)
        distanceLabel.textColor = .label
        distanceLabel.textAlignment = .right
        distanceLabel.adjustsFontSizeToFitWidth = true
        distanceLabel.minimumScaleFactor = 0.78

        detailStackView.axis = .vertical
        detailStackView.spacing = 12
        detailStackView.alpha = 0

        replayRulerView.configure(totalDistanceText: replayTotalDistanceText(totalMeters: workout.distanceMeters))
        replayRulerView.addTarget(self, action: #selector(handleReplayProgressChanged(_:)), for: .valueChanged)

        let timeRow = makeDetailRow(title: "时间", value: workout.timeRangeText)
        let distanceRow = makeDetailRow(title: "距离", value: workout.distanceText)
        detailStackView.addArrangedSubview(timeRow)
        detailStackView.addArrangedSubview(distanceRow)
        detailStackView.setCustomSpacing(18, after: distanceRow)
        detailStackView.addArrangedSubview(replayRulerView)

        view.addSubview(panelView)
        panelView.contentView.addSubview(handleTouchView)
        handleTouchView.addSubview(handleView)
        panelView.contentView.addSubview(iconView)
        panelView.contentView.addSubview(titleLabel)
        panelView.contentView.addSubview(distanceLabel)
        panelView.contentView.addSubview(detailStackView)

        panelView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(14)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom).inset(12)
            panelHeightConstraint = make.height.equalTo(collapsedPanelHeight).constraint
        }

        handleTouchView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(32)
        }

        handleView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(9)
            make.width.equalTo(42)
            make.height.equalTo(4)
        }

        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            make.top.equalTo(handleTouchView.snp.bottom).offset(7)
            make.size.equalTo(28)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconView.snp.trailing).offset(10)
            make.centerY.equalTo(iconView)
            make.trailing.lessThanOrEqualTo(distanceLabel.snp.leading).offset(-12)
        }

        distanceLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(18)
            make.centerY.equalTo(iconView)
            make.width.greaterThanOrEqualTo(88)
        }

        detailStackView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(18)
            make.top.equalTo(iconView.snp.bottom).offset(24)
        }

        replayRulerView.snp.makeConstraints { make in
            make.height.equalTo(82)
        }
    }

    private func makeDetailRow(title: String, value: String) -> UIView {
        let container = UIView()
        let titleLabel = UILabel()
        let valueLabel = UILabel()

        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .secondaryLabel

        valueLabel.text = value
        valueLabel.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.textColor = .label
        valueLabel.textAlignment = .right
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.78

        container.addSubview(titleLabel)
        container.addSubview(valueLabel)

        titleLabel.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.greaterThanOrEqualTo(46)
        }

        valueLabel.snp.makeConstraints { make in
            make.leading.greaterThanOrEqualTo(titleLabel.snp.trailing).offset(12)
            make.trailing.top.bottom.equalToSuperview()
        }

        return container
    }

    private func drawRoute() {
        let coordinates = workout.displayCoordinates
        guard coordinates.count > 1 else {
            return
        }

        configureReplayRoute(with: coordinates, routeCoordinates: workout.coordinates)

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)

        mapView.addAnnotations([
            RouteEndpointAnnotation(coordinate: coordinates[0], kind: .start),
            RouteEndpointAnnotation(coordinate: coordinates[coordinates.count - 1], kind: .end)
        ])
    }

    private func fitRouteIfNeeded() {
        guard !hasFittedRoute, let overlay = mapView.overlays.first else {
            return
        }

        hasFittedRoute = true
        mapView.setVisibleMapRect(
            overlay.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 96, left: 32, bottom: expandedPanelHeight + 28, right: 32),
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
            panStartHeight = isPanelExpanded ? expandedPanelHeight : collapsedPanelHeight
        case .changed:
            let translationY = recognizer.translation(in: view).y
            let proposedHeight = min(max(panStartHeight - translationY, collapsedPanelHeight), expandedPanelHeight)
            updatePanel(height: proposedHeight, animated: false)
        case .ended, .cancelled, .failed:
            let velocityY = recognizer.velocity(in: view).y
            let currentHeight = panelCurrentHeight()
            let shouldExpand: Bool

            if abs(velocityY) > 220 {
                shouldExpand = velocityY < 0
            } else {
                shouldExpand = currentHeight > (collapsedPanelHeight + expandedPanelHeight) / 2
            }

            setPanelExpanded(shouldExpand, animated: true)
        default:
            break
        }
    }

    private func panelCurrentHeight() -> CGFloat {
        panelView.bounds.height > 0 ? panelView.bounds.height : (isPanelExpanded ? expandedPanelHeight : collapsedPanelHeight)
    }

    private func setPanelExpanded(_ expanded: Bool, animated: Bool) {
        isPanelExpanded = expanded
        if !expanded {
            removeReplayAnnotation()
            replayRulerView.setProgress(0)
        }
        updatePanel(height: expanded ? expandedPanelHeight : collapsedPanelHeight, animated: animated)
    }

    private func updatePanel(height: CGFloat, animated: Bool) {
        let progress = (height - collapsedPanelHeight) / (expandedPanelHeight - collapsedPanelHeight)
        panelHeightConstraint?.update(offset: height)

        let changes = {
            self.detailStackView.alpha = min(max(progress, 0), 1)
            self.view.layoutIfNeeded()
        }

        guard animated else {
            changes()
            return
        }

        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseInOut]) {
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
            if let annotationView = mapView.view(for: replayAnnotation) as? RouteReplayAnnotationView {
                annotationView.configure(emoji: replayAnnotation.emoji, statusText: statusText)
            }
        } else {
            let annotation = RouteReplayAnnotation(
                coordinate: replayState.coordinate,
                emoji: replayEmoji,
                statusText: statusText
            )
            replayAnnotation = annotation
            mapView.addAnnotation(annotation)
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
                altitudeMeters: replayAltitude(at: 0)
            )
        }

        let targetDistance = CLLocationDistance(progress) * totalDistance
        let index = nearestReplayCoordinateIndex(for: targetDistance)
        return ReplayState(
            coordinate: replayCoordinates[index],
            distanceMeters: replayDistances[index],
            altitudeMeters: replayAltitude(at: index)
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

private struct ReplayState {
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance
    let altitudeMeters: Double?
}

extension WorkoutRouteDetailViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }

        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = workout.routeColor
        renderer.lineWidth = 4.5
        renderer.lineJoin = .round
        renderer.lineCap = .round
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let replayAnnotation = annotation as? RouteReplayAnnotation {
            let identifier = RouteReplayAnnotationView.reuseIdentifier
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? RouteReplayAnnotationView
                ?? RouteReplayAnnotationView(annotation: replayAnnotation, reuseIdentifier: identifier)
            annotationView.annotation = replayAnnotation
            annotationView.configure(emoji: replayAnnotation.emoji, statusText: replayAnnotation.statusText)
            return annotationView
        }

        if let mediaAnnotation = annotation as? RouteMediaAnnotation {
            let identifier = RouteMediaAnnotationView.reuseIdentifier
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? RouteMediaAnnotationView
                ?? RouteMediaAnnotationView(annotation: mediaAnnotation, reuseIdentifier: identifier)
            annotationView.annotation = mediaAnnotation
            annotationView.configure(with: mediaAnnotation.mediaItem)
            return annotationView
        }

        guard let endpointAnnotation = annotation as? RouteEndpointAnnotation else {
            return nil
        }

        let identifier = RouteEndpointAnnotationView.reuseIdentifier
        let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? RouteEndpointAnnotationView
            ?? RouteEndpointAnnotationView(annotation: endpointAnnotation, reuseIdentifier: identifier)
        annotationView.annotation = endpointAnnotation
        annotationView.configure(kind: endpointAnnotation.kind)
        return annotationView
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
        mapView.deselectAnnotation(annotation, animated: true)
        guard let mediaAnnotation = annotation as? RouteMediaAnnotation,
              let index = routeMediaItems.firstIndex(where: { $0.id == mediaAnnotation.mediaItem.id }) else {
            return
        }

        let browser = RouteMediaBrowserViewController(mediaItems: routeMediaItems, initialIndex: index)
        navigationController?.pushViewController(browser, animated: true)
    }
}

private enum RouteEndpointKind {
    case start
    case end
}

private final class RouteEndpointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let kind: RouteEndpointKind

    init(coordinate: CLLocationCoordinate2D, kind: RouteEndpointKind) {
        self.coordinate = coordinate
        self.kind = kind
        super.init()
    }
}

private final class RouteEndpointAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "RouteEndpointAnnotationView"

    private let diameter: CGFloat = 18

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configureBaseView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureBaseView()
    }

    func configure(kind: RouteEndpointKind) {
        backgroundColor = kind == .start ? .systemGreen : .systemRed
    }

    private func configureBaseView() {
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        centerOffset = .zero
        collisionMode = .circle
        displayPriority = .required

        layer.cornerRadius = diameter / 2
        layer.borderColor = UIColor.white.cgColor
        layer.borderWidth = 3
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.16
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }
}

private final class RouteReplayAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let emoji: String
    var statusText: String

    init(coordinate: CLLocationCoordinate2D, emoji: String, statusText: String) {
        self.coordinate = coordinate
        self.emoji = emoji
        self.statusText = statusText
        super.init()
    }
}

private final class RouteReplayAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "RouteReplayAnnotationView"

    private let statusContainerView = UIView()
    private let statusLabel = UILabel()
    private let emojiLabel = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        configureBaseView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureBaseView()
    }

    func configure(emoji: String, statusText: String) {
        emojiLabel.text = emoji
        statusLabel.text = statusText
    }

    private func configureBaseView() {
        bounds = CGRect(x: 0, y: 0, width: 150, height: 80)
        centerOffset = CGPoint(x: 0, y: -18)
        collisionMode = .circle
        displayPriority = .required
        backgroundColor = .clear
        clipsToBounds = false

        statusContainerView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.96)
        statusContainerView.layer.cornerRadius = 13
        statusContainerView.layer.shadowColor = UIColor.black.cgColor
        statusContainerView.layer.shadowOpacity = 0.14
        statusContainerView.layer.shadowRadius = 5
        statusContainerView.layer.shadowOffset = CGSize(width: 0, height: 2)

        statusLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        statusLabel.textColor = .label
        statusLabel.textAlignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        emojiLabel.font = .systemFont(ofSize: 31)
        emojiLabel.textAlignment = .center
        emojiLabel.layer.shadowColor = UIColor.black.cgColor
        emojiLabel.layer.shadowOpacity = 0.22
        emojiLabel.layer.shadowRadius = 3
        emojiLabel.layer.shadowOffset = CGSize(width: 0, height: 1)

        addSubview(statusContainerView)
        statusContainerView.addSubview(statusLabel)
        addSubview(emojiLabel)

        statusContainerView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.height.equalTo(26)
            make.leading.greaterThanOrEqualToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }

        statusLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10))
        }

        emojiLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview()
            make.size.equalTo(44)
        }
    }
}
