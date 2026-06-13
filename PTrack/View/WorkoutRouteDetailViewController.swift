//
//  WorkoutRouteDetailViewController.swift
//  PTrack
//
//  Created by pjhubs on 2026/6/13.
//

import MapKit
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
    private var panelHeightConstraint: Constraint?
    private var isPanelExpanded = false
    private var hasFittedRoute = false
    private var panStartHeight: CGFloat = 0
    private var routeMediaItems: [RouteMediaItem] = []

    private let collapsedPanelHeight: CGFloat = 82
    private let expandedPanelHeight: CGFloat = 194
    private let navigationBackgroundHeight: CGFloat = 124

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

        detailStackView.addArrangedSubview(makeDetailRow(title: "时间", value: workout.timeRangeText))
        detailStackView.addArrangedSubview(makeDetailRow(title: "距离", value: workout.distanceText))

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
