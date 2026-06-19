//
//  WorkoutRouteShareViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import MapKit
import Photos
import PhotosUI
import SnapKit
import UIKit

final class WorkoutRouteShareViewController: UIViewController {
    private typealias PreviewModule = RouteSharePreviewModule
    private typealias PreviewBackground = RouteSharePreviewBackground
    private typealias SharePhotoItem = RouteSharePhotoItem

    private let workout: TrackedWorkout
    private let mediaStore = RouteMediaStore()
    private let livePhotoExporter = RouteShareLivePhotoExporter()
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
    private let navigationBackgroundMask = CAGradientLayer()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let previewView = UIView()
    private let mapContainerView = AppMapContainerView()
    private var mapView: MKMapView { mapContainerView.mapView }
    private let mapToneOverlay = AppMapStyle.makeToneOverlay()
    private let previewImageView = UIImageView()
    private let previewLivePhotoView = PHLivePhotoView()
    private let previewPlaceholderView = UIView()
    private let previewPlaceholderIconView = UIImageView()
    private let routeModuleView = RouteShareRouteModuleView()
    private var routePathView: WorkoutRoutePathView { routeModuleView.pathView }
    private let routeSelectionBorderLayer = CAShapeLayer()
    private var routeDeleteCornerButton: UIButton { routeModuleView.deleteButton }
    private let metricsModuleView = RouteShareMetricsModuleView()
    private let metricsSelectionBorderLayer = CAShapeLayer()
    private var metricsDeleteCornerButton: UIButton { metricsModuleView.deleteButton }
    private let brandPillView = RouteShareBrandPillView()
    private let photoCollectionView: UICollectionView
    private let toolBarView = RouteShareToolBarView()
    private var colorToolButton: UIButton { toolBarView.colorButton }
    private var mapStyleToolButton: UIButton { toolBarView.mapStyleButton }
    private var deleteToolButton: UIButton { toolBarView.deleteButton }
    private var addRouteToolButton: UIButton { toolBarView.addRouteButton }
    private var addMetricsToolButton: UIButton { toolBarView.addMetricsButton }
    private let exportLoadingView = RouteShareExportLoadingView()
    private var toolsContainerWidthConstraint: Constraint?
    private weak var previewBackgroundTapGesture: UITapGestureRecognizer?
    private weak var previewModulePanGesture: UIPanGestureRecognizer?
    private weak var previewModulePinchGesture: UIPinchGestureRecognizer?
    private weak var previewModuleRotationGesture: UIRotationGestureRecognizer?
    private var hasPlayedEntranceAnimation = false

    private var photoItems: [SharePhotoItem]
    private var selectedPhotoIndex: Int?
    private var selectedPreviewModule: PreviewModule?
    private var selectedRouteColorIndex = 0 {
        didSet {
            routePathView.setStrokeColor(colorOptions[selectedRouteColorIndex])
            mapView.removeOverlays(mapView.overlays.filter { !($0 is AppMapToneTileOverlay) })
            configureMapRouteOverlay()
        }
    }
    private var selectedMetricsColorIndex = 0 {
        didSet {
            applyMetricsColor()
        }
    }
    private var selectedMapStyle = AppMapDisplayStyleStore.shared.routeDetailStyle()
    private var previewBackground: PreviewBackground
    private var routePolyline: MKPolyline?
    private var previewImageRequestID: PHImageRequestID?
    private var previewLivePhotoRequestID: PHImageRequestID?
    private var representedPreviewPhotoID: String?
    private var pendingUploadedSelectionID: UUID?
    private var isRouteModuleEnabled = true
    private var isMetricsModuleEnabled = true
    private var routeModuleScale: CGFloat = 1
    private var metricsModuleScale: CGFloat = 1
    private var routeModuleRotation: CGFloat = 0
    private var metricsModuleRotation: CGFloat = 0
    private var routeModuleTranslation: CGPoint = .zero
    private var metricsModuleTranslation: CGPoint = .zero
    private var brandPillTranslation: CGPoint = .zero
    private var previousInteractivePopGestureEnabled: Bool?
    private let moduleMinimumScale: CGFloat = 0.35
    private let moduleMaximumScale: CGFloat = 3
    private let brandPillVisibleInset: CGFloat = 6

    private let navigationBackgroundHeight: CGFloat = 124
    private let colorOptions: [UIColor] = [
        .white,
        .black,
        AppColors.movinnGreen,
        .systemBlue,
        .systemOrange,
        .systemPink
    ]

    init(workout: TrackedWorkout, initialMediaItems: [RouteMediaItem]) {
        self.workout = workout
        let imageMediaItems = initialMediaItems.filter { !$0.isVideo }
        photoItems = imageMediaItems.map(SharePhotoItem.routeMedia)
        selectedPhotoIndex = imageMediaItems.isEmpty ? nil : 0
        previewBackground = imageMediaItems.isEmpty ? .map : .photo(0)
        selectedRouteColorIndex = imageMediaItems.isEmpty ? 1 : 0
        selectedMetricsColorIndex = imageMediaItems.isEmpty ? 1 : 0

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 10
        layout.minimumInteritemSpacing = 10
        photoCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let previewImageRequestID {
            PHImageManager.default().cancelImageRequest(previewImageRequestID)
        }
        if let previewLivePhotoRequestID {
            PHImageManager.default().cancelImageRequest(previewLivePhotoRequestID)
        }
        NotificationCenter.default.removeObserver(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .darkContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureScrollView()
        configurePreviewView()
        configurePhotoCollectionView()
        configureToolsView()
        configureNavigationBackgroundView()
        configureExportLoadingView()
        registerObservers()
        updateLocalizedText()
        updatePreviewSelection()
        updatePreviewPhoto()
        updateToolBarVisibility()
        loadRouteMediaIfNeeded()
        prepareEntranceAnimation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        configureNavigationBar()
        disableInteractivePopGesture()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        restoreInteractivePopGesture()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        playEntranceAnimationIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNavigationBackgroundMask()
        updateSelectionChromeFrames()
        updatePreviewPhotoIfNeeded()
        fitMapRouteIfNeeded()
        snapBrandPillIntoPreviewBounds(animated: false)
    }

    private func configureNavigationItem() {
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(sharePreviewImage)
        )
        navigationItem.rightBarButtonItem?.tintColor = AppColors.movinnGreen
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
        navigationItem.rightBarButtonItem?.tintColor = AppColors.movinnGreen
    }

    private func disableInteractivePopGesture() {
        guard let gestureRecognizer = navigationController?.interactivePopGestureRecognizer else {
            return
        }

        if previousInteractivePopGestureEnabled == nil {
            previousInteractivePopGestureEnabled = gestureRecognizer.isEnabled
        }
        gestureRecognizer.isEnabled = false
    }

    private func restoreInteractivePopGesture() {
        guard let gestureRecognizer = navigationController?.interactivePopGestureRecognizer,
              let previousInteractivePopGestureEnabled else {
            return
        }

        gestureRecognizer.isEnabled = previousInteractivePopGestureEnabled
        self.previousInteractivePopGestureEnabled = nil
    }

    private func configureScrollView() {
        scrollView.backgroundColor = .systemBackground
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.contentInset = UIEdgeInsets(
            top: navigationBackgroundHeight,
            left: 0,
            bottom: 28,
            right: 0
        )
        scrollView.scrollIndicatorInsets = scrollView.contentInset

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
        }
    }

    private func configurePreviewView() {
        previewView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        previewView.layer.cornerRadius = 8
        previewView.layer.masksToBounds = true
        let previewBackgroundTapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePreviewBackgroundTap(_:)))
        previewBackgroundTapGesture.cancelsTouchesInView = false
        previewBackgroundTapGesture.delegate = self
        previewView.addGestureRecognizer(previewBackgroundTapGesture)
        self.previewBackgroundTapGesture = previewBackgroundTapGesture
        configurePreviewModuleGestures()

        mapView.delegate = self
        mapView.isUserInteractionEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = false
        AppMapStyle.apply(selectedMapStyle, to: mapView)
        AppMapStyle.setToneOverlay(mapToneOverlay, visible: selectedMapStyle == .appDefault, on: mapView)

        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true

        previewLivePhotoView.contentMode = .scaleAspectFill
        previewLivePhotoView.clipsToBounds = true
        previewLivePhotoView.isMuted = false

        previewPlaceholderView.backgroundColor = UIColor(white: 0.91, alpha: 1)
        previewPlaceholderIconView.image = UIImage(
            systemName: "photo",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        )
        previewPlaceholderIconView.tintColor = UIColor.black.withAlphaComponent(0.22)
        previewPlaceholderIconView.contentMode = .scaleAspectFit

        routeModuleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectRouteModule)))
        routeModuleView.configure(with: workout, color: colorOptions[selectedRouteColorIndex])

        metricsModuleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectMetricsModule)))
        metricsModuleView.configure(with: workout, color: colorOptions[selectedMetricsColorIndex])
        configureModuleGestures()
        configureBrandPillGestures()
        configureModuleSelectionChrome()

        contentView.addSubview(previewView)
        previewView.addSubview(mapContainerView)
        previewView.addSubview(previewImageView)
        previewView.addSubview(previewLivePhotoView)
        previewView.addSubview(previewPlaceholderView)
        previewPlaceholderView.addSubview(previewPlaceholderIconView)
        previewView.addSubview(routeModuleView)
        previewView.addSubview(metricsModuleView)
        previewView.addSubview(routeDeleteCornerButton)
        previewView.addSubview(metricsDeleteCornerButton)
        previewView.addSubview(brandPillView)

        previewView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(previewView.snp.width).multipliedBy(1.25)
        }

        mapContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        previewImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        previewLivePhotoView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        previewPlaceholderView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        previewPlaceholderIconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(48)
        }

        routeModuleView.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(22)
            make.width.height.equalTo(138)
        }

        metricsModuleView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(22)
            make.height.equalTo(104)
        }

        brandPillView.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview().inset(18)
            make.size.equalTo(RouteShareBrandPillView.preferredSize)
        }

        configureMapRouteOverlay()
        updatePreviewModuleVisibility()
    }

    private func configureModuleGestures() {
        [routeModuleView, metricsModuleView].forEach { moduleView in
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleModulePan(_:)))
            panGesture.delegate = self
            moduleView.addGestureRecognizer(panGesture)

            let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleModulePinch(_:)))
            pinchGesture.delegate = self
            moduleView.addGestureRecognizer(pinchGesture)

            let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleModuleRotation(_:)))
            rotationGesture.delegate = self
            moduleView.addGestureRecognizer(rotationGesture)
        }
    }

    private func configurePreviewModuleGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleModulePan(_:)))
        panGesture.delegate = self
        previewView.addGestureRecognizer(panGesture)
        previewModulePanGesture = panGesture

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleModulePinch(_:)))
        pinchGesture.delegate = self
        previewView.addGestureRecognizer(pinchGesture)
        previewModulePinchGesture = pinchGesture

        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleModuleRotation(_:)))
        rotationGesture.delegate = self
        previewView.addGestureRecognizer(rotationGesture)
        previewModuleRotationGesture = rotationGesture
    }

    private func configureBrandPillGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleBrandPillPan(_:)))
        panGesture.delegate = self
        brandPillView.addGestureRecognizer(panGesture)
    }

    private func configureModuleSelectionChrome() {
        configureSelectionBorderLayer(routeSelectionBorderLayer)
        configureSelectionBorderLayer(metricsSelectionBorderLayer)
        [routeDeleteCornerButton, metricsDeleteCornerButton].forEach { button in
            button.bounds = CGRect(origin: .zero, size: CGSize(width: 24, height: 24))
        }
        routeDeleteCornerButton.addTarget(self, action: #selector(deleteRouteModuleFromChrome), for: .touchUpInside)
        metricsDeleteCornerButton.addTarget(self, action: #selector(deleteMetricsModuleFromChrome), for: .touchUpInside)
    }

    private func configureSelectionBorderLayer(_ borderLayer: CAShapeLayer) {
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = AppColors.movinnGreen.cgColor
        borderLayer.lineWidth = 2
        borderLayer.lineDashPattern = [6, 4]
        borderLayer.isHidden = true
        previewView.layer.addSublayer(borderLayer)
    }

    private func updateSelectionChromeFrames() {
        updateSelectionChrome(
            borderLayer: routeSelectionBorderLayer,
            deleteButton: routeDeleteCornerButton,
            for: routeModuleView
        )
        updateSelectionChrome(
            borderLayer: metricsSelectionBorderLayer,
            deleteButton: metricsDeleteCornerButton,
            for: metricsModuleView
        )
    }

    private func updateSelectionChrome(
        borderLayer: CAShapeLayer,
        deleteButton: UIButton,
        for moduleView: UIView
    ) {
        borderLayer.frame = previewView.bounds
        borderLayer.path = selectionBorderPath(for: moduleView)
        deleteButton.center = moduleView.convert(
            CGPoint(x: moduleView.bounds.maxX, y: moduleView.bounds.minY),
            to: previewView
        )
    }

    private func selectionBorderPath(for moduleView: UIView) -> CGPath {
        let corners = [
            CGPoint(x: moduleView.bounds.minX, y: moduleView.bounds.minY),
            CGPoint(x: moduleView.bounds.maxX, y: moduleView.bounds.minY),
            CGPoint(x: moduleView.bounds.maxX, y: moduleView.bounds.maxY),
            CGPoint(x: moduleView.bounds.minX, y: moduleView.bounds.maxY)
        ].map { moduleView.convert($0, to: previewView) }

        let path = UIBezierPath()
        guard let firstCorner = corners.first else {
            return path.cgPath
        }
        path.move(to: firstCorner)
        corners.dropFirst().forEach(path.addLine)
        path.close()
        return path.cgPath
    }

    private func configurePhotoCollectionView() {
        photoCollectionView.backgroundColor = .clear
        photoCollectionView.showsHorizontalScrollIndicator = false
        photoCollectionView.alwaysBounceHorizontal = true
        photoCollectionView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        photoCollectionView.dataSource = self
        photoCollectionView.delegate = self
        photoCollectionView.register(RouteSharePhotoCell.self, forCellWithReuseIdentifier: RouteSharePhotoCell.reuseIdentifier)

        contentView.addSubview(photoCollectionView)

        photoCollectionView.snp.makeConstraints { make in
            make.top.equalTo(previewView.snp.bottom).offset(14)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(82)
        }
    }

    private func configureToolsView() {
        configureColorToolButton()
        configureDeleteToolButton()
        configureAddToolButtons()
        mapStyleToolButton.showsMenuAsPrimaryAction = true
        configureMapStyleButton()

        contentView.addSubview(toolBarView)

        toolBarView.snp.makeConstraints { make in
            make.top.equalTo(photoCollectionView.snp.bottom).offset(14)
            make.leading.equalToSuperview().offset(16)
            make.height.equalTo(64)
            toolsContainerWidthConstraint = make.width.equalTo(156).constraint
            make.bottom.equalToSuperview()
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

    private func configureExportLoadingView() {
        view.addSubview(exportLoadingView)

        exportLoadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageDidChange),
            name: AppLanguageStore.languageDidChangeNotification,
            object: nil
        )
    }

    private func updateNavigationBackgroundMask() {
        navigationBackgroundMask.frame = navigationBackgroundView.bounds
        navigationBackgroundMask.startPoint = CGPoint(x: 0.5, y: 0)
        navigationBackgroundMask.endPoint = CGPoint(x: 0.5, y: 1)
    }

    @objc private func handleLanguageDidChange() {
        updateLocalizedText()
        configureColorToolButton()
        configureMapStyleButton()
    }

    private func updateLocalizedText() {
        title = AppLocalization.text(.share)
        metricsModuleView.updateLocalizedText(for: workout)
        configureColorToolButton()
        configureDeleteToolButton()
        configureAddToolButtons()
        configureMapStyleButton()
    }

    private func prepareEntranceAnimation() {
        RouteShareEntranceAnimator.prepare(entranceAnimatedViews)
    }

    private func playEntranceAnimationIfNeeded() {
        guard !hasPlayedEntranceAnimation else {
            return
        }

        hasPlayedEntranceAnimation = true
        view.layoutIfNeeded()
        RouteShareEntranceAnimator.animate(entranceAnimatedViews)
    }

    private var entranceAnimatedViews: [UIView] {
        [
            previewView,
            photoCollectionView,
            toolBarView
        ]
    }

    private func configureColorToolButton() {
        let hasSelection = selectedPreviewModule != nil
        colorToolButton.configuration = toolButtonConfiguration(
            title: AppLocalization.text(.color),
            imageName: "paintpalette"
        )
        colorToolButton.isEnabled = hasSelection
        colorToolButton.alpha = hasSelection ? 1 : 0.38
        colorToolButton.showsMenuAsPrimaryAction = true
        colorToolButton.menu = UIMenu(children: colorOptions.enumerated().map { index, color in
            UIAction(
                title: colorName(for: index),
                image: colorSwatchImage(color),
                attributes: hasSelection ? [] : [.disabled],
                state: selectedColorIndexForCurrentModule() == index ? .on : .off
            ) { [weak self] _ in
                self?.applyColor(at: index)
            }
        })
    }

    private func configureDeleteToolButton() {
        deleteToolButton.configuration = toolButtonConfiguration(
            title: AppLocalization.text(.delete),
            imageName: "trash"
        )
        deleteToolButton.removeTarget(nil, action: nil, for: .touchUpInside)
        deleteToolButton.addTarget(self, action: #selector(deleteSelectedModule), for: .touchUpInside)
    }

    private func configureAddToolButtons() {
        addRouteToolButton.configuration = toolButtonConfiguration(
            title: AppLocalization.text(.route),
            imageName: "point.topleft.down.curvedto.point.bottomright.up"
        )
        addRouteToolButton.removeTarget(nil, action: nil, for: .touchUpInside)
        addRouteToolButton.addTarget(self, action: #selector(addRouteModule), for: .touchUpInside)

        addMetricsToolButton.configuration = toolButtonConfiguration(
            title: AppLocalization.text(.data),
            imageName: "textformat.size"
        )
        addMetricsToolButton.removeTarget(nil, action: nil, for: .touchUpInside)
        addMetricsToolButton.addTarget(self, action: #selector(addMetricsModule), for: .touchUpInside)
    }

    private func configureMapStyleButton() {
        mapStyleToolButton.configuration = toolButtonConfiguration(
            title: AppLocalization.text(.mapStyle),
            imageName: "map"
        )
        mapStyleToolButton.menu = UIMenu(children: AppMapDisplayStyle.menuCases.map { style in
            UIAction(
                title: style.title,
                state: style == selectedMapStyle ? .on : .off
            ) { [weak self] _ in
                self?.applyMapStyle(style)
            }
        })
    }

    private func toolButtonConfiguration(title: String, imageName: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = .black
        configuration.image = UIImage(systemName: imageName)
        configuration.imagePlacement = .top
        configuration.imagePadding = 4
        configuration.title = title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 11, weight: .semibold)
            return outgoing
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 7, trailing: 4)
        return configuration
    }

    private func loadRouteMediaIfNeeded() {
        guard photoItems.isEmpty else {
            return
        }

        mediaStore.loadMedia(for: workout) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let mediaItems):
                let imageMediaItems = mediaItems.filter { !$0.isVideo }
                photoItems = imageMediaItems.map(SharePhotoItem.routeMedia)
                selectedPhotoIndex = imageMediaItems.isEmpty ? nil : 0
                previewBackground = imageMediaItems.isEmpty ? .map : .photo(0)
                applyDefaultColorsForCurrentBackground()
                resetPreviewModuleAdjustments()
                photoCollectionView.reloadData()
                updatePreviewPhoto()
                updateToolBarVisibility()
            case .failure(let error):
                print("PTrack Share Photos: failed to load route media: \(error)")
            }
        }
    }

    private func updatePreviewSelection() {
        applySelectionStyle(to: routeModuleView, isSelected: selectedPreviewModule == .route)
        applySelectionStyle(to: metricsModuleView, isSelected: selectedPreviewModule == .metrics)
        configureColorToolButton()
        updateToolBarVisibility()
    }

    private func applySelectionStyle(to view: UIView, isSelected: Bool) {
        let isRouteView = view === routeModuleView
        let borderLayer = isRouteView ? routeSelectionBorderLayer : metricsSelectionBorderLayer
        let deleteButton = isRouteView ? routeDeleteCornerButton : metricsDeleteCornerButton
        borderLayer.isHidden = !isSelected
        deleteButton.isHidden = !isSelected
        if isSelected {
            borderLayer.removeFromSuperlayer()
            previewView.layer.addSublayer(borderLayer)
            updateSelectionChrome(borderLayer: borderLayer, deleteButton: deleteButton, for: view)
            keepBrandPillOnTop()
            previewView.bringSubviewToFront(deleteButton)
        }
    }

    private func updatePreviewPhotoIfNeeded() {
        guard representedPreviewPhotoID == nil else {
            return
        }

        updatePreviewPhoto()
    }

    private func updatePreviewPhoto() {
        if let previewImageRequestID {
            PHImageManager.default().cancelImageRequest(previewImageRequestID)
            self.previewImageRequestID = nil
        }
        if let previewLivePhotoRequestID {
            PHImageManager.default().cancelImageRequest(previewLivePhotoRequestID)
            self.previewLivePhotoRequestID = nil
        }
        previewLivePhotoView.stopPlayback()
        previewLivePhotoView.livePhoto = nil

        switch previewBackground {
        case .map:
            representedPreviewPhotoID = nil
            previewImageView.image = nil
            previewImageView.isHidden = true
            previewLivePhotoView.isHidden = true
            previewPlaceholderView.isHidden = true
            mapView.isHidden = false
            routeModuleView.isHidden = true
            if selectedPreviewModule == .route {
                selectedPreviewModule = nil
                updatePreviewSelection()
            }
            fitMapRouteIfNeeded()
        case .photo(let selectedPhotoIndex):
            guard photoItems.indices.contains(selectedPhotoIndex) else {
                representedPreviewPhotoID = nil
                previewImageView.image = nil
                previewImageView.isHidden = true
                previewLivePhotoView.isHidden = true
                previewPlaceholderView.isHidden = false
                mapView.isHidden = true
                return
            }

            let item = photoItems[selectedPhotoIndex]
            representedPreviewPhotoID = item.id
            mapView.isHidden = true
            previewPlaceholderView.isHidden = true
            updatePreviewModuleVisibility()

            switch item {
            case .uploaded(let image):
                previewImageView.image = image
                previewImageView.isHidden = false
                previewLivePhotoView.isHidden = true
            case .routeMedia(let mediaItem):
                if mediaItem.isLivePhoto {
                    previewImageView.isHidden = true
                    previewLivePhotoView.isHidden = false
                    requestPreviewLivePhoto(for: mediaItem.asset, representedID: item.id, playWhenReady: true)
                } else {
                    previewImageView.isHidden = false
                    previewLivePhotoView.isHidden = true
                    requestPreviewImage(for: mediaItem.asset, representedID: item.id)
                }
            }
        }
    }

    private func requestPreviewImage(for asset: PHAsset, representedID: String) {
        let scale = max(UIScreen.main.scale, 2)
        let targetWidth = max(previewView.bounds.width, 720) * scale
        let targetHeight = max(previewView.bounds.height, 900) * scale
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        previewImageRequestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: targetWidth, height: targetHeight),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard let self,
                  representedPreviewPhotoID == representedID else {
                return
            }

            previewImageView.image = image
            previewPlaceholderView.isHidden = image != nil
        }
    }

    private func requestPreviewLivePhoto(
        for asset: PHAsset,
        representedID: String,
        playWhenReady: Bool
    ) {
        let scale = max(UIScreen.main.scale, 2)
        let targetWidth = max(previewView.bounds.width, 720) * scale
        let targetHeight = max(previewView.bounds.height, 900) * scale
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        previewLivePhotoRequestID = PHImageManager.default().requestLivePhoto(
            for: asset,
            targetSize: CGSize(width: targetWidth, height: targetHeight),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] livePhoto, _ in
            guard let self,
                  representedPreviewPhotoID == representedID else {
                return
            }

            previewLivePhotoView.livePhoto = livePhoto
            previewPlaceholderView.isHidden = livePhoto != nil
            if livePhoto != nil, playWhenReady {
                previewLivePhotoView.startPlayback(with: .full)
            }
        }
    }

    private func selectPhoto(at index: Int) {
        let replayLivePhoto = selectedPhotoIndex == index
            && photoItems.indices.contains(index)
            && photoItems[index].isLivePhoto
        selectedPhotoIndex = index
        previewBackground = .photo(index)
        applyDefaultColorsForCurrentBackground()
        resetPreviewModuleAdjustments()
        representedPreviewPhotoID = nil
        photoCollectionView.reloadData()
        updatePreviewPhoto()
        updateToolBarVisibility()

        if replayLivePhoto {
            previewLivePhotoView.stopPlayback()
            previewLivePhotoView.startPlayback(with: .full)
        }
    }

    private func selectMapBackground() {
        selectedPhotoIndex = nil
        previewBackground = .map
        applyDefaultColorsForCurrentBackground()
        resetPreviewModuleAdjustments()
        representedPreviewPhotoID = nil
        photoCollectionView.reloadData()
        updatePreviewPhoto()
        updateToolBarVisibility()
    }

    private func presentPhotoPicker() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        pendingUploadedSelectionID = UUID()
        present(picker, animated: true)
    }

    private func applyDefaultColorsForCurrentBackground() {
        switch previewBackground {
        case .map:
            selectedRouteColorIndex = 1
            selectedMetricsColorIndex = 1
        case .photo:
            selectedRouteColorIndex = 0
            selectedMetricsColorIndex = 0
        }
    }

    private func resetPreviewModuleAdjustments() {
        routeModuleScale = 1
        metricsModuleScale = 1
        routeModuleRotation = 0
        metricsModuleRotation = 0
        routeModuleTranslation = .zero
        metricsModuleTranslation = .zero
        applyModuleTransform(.route)
        applyModuleTransform(.metrics)
        selectedPreviewModule = nil
        updatePreviewSelection()
    }

    @objc private func selectRouteModule() {
        guard !routeModuleView.isHidden else {
            return
        }
        selectedPreviewModule = .route
        previewView.bringSubviewToFront(routeModuleView)
        keepBrandPillOnTop()
        updatePreviewSelection()
    }

    @objc private func selectMetricsModule() {
        guard !metricsModuleView.isHidden else {
            return
        }
        selectedPreviewModule = .metrics
        previewView.bringSubviewToFront(metricsModuleView)
        keepBrandPillOnTop()
        updatePreviewSelection()
    }

    private func selectedColorIndexForCurrentModule() -> Int? {
        switch selectedPreviewModule {
        case .route:
            return selectedRouteColorIndex
        case .metrics:
            return selectedMetricsColorIndex
        case nil:
            return nil
        }
    }

    private func applyColor(at index: Int) {
        switch selectedPreviewModule {
        case .route:
            selectedRouteColorIndex = index
        case .metrics:
            selectedMetricsColorIndex = index
        case nil:
            return
        }
        configureColorToolButton()
    }

    @objc private func deleteSelectedModule() {
        switch selectedPreviewModule {
        case .route:
            isRouteModuleEnabled = false
        case .metrics:
            isMetricsModuleEnabled = false
        case nil:
            return
        }

        selectedPreviewModule = nil
        updatePreviewModuleVisibility()
        updatePreviewSelection()
    }

    @objc private func addRouteModule() {
        isRouteModuleEnabled = true
        routeModuleScale = 1
        routeModuleRotation = 0
        routeModuleTranslation = .zero
        applyModuleTransform(.route)
        selectedPreviewModule = .route
        previewView.bringSubviewToFront(routeModuleView)
        keepBrandPillOnTop()
        updatePreviewModuleVisibility()
        updatePreviewSelection()
    }

    @objc private func addMetricsModule() {
        isMetricsModuleEnabled = true
        metricsModuleScale = 1
        metricsModuleRotation = 0
        metricsModuleTranslation = .zero
        applyModuleTransform(.metrics)
        selectedPreviewModule = .metrics
        previewView.bringSubviewToFront(metricsModuleView)
        keepBrandPillOnTop()
        updatePreviewModuleVisibility()
        updatePreviewSelection()
    }

    @objc private func deleteRouteModuleFromChrome() {
        selectedPreviewModule = .route
        deleteSelectedModule()
    }

    @objc private func deleteMetricsModuleFromChrome() {
        selectedPreviewModule = .metrics
        deleteSelectedModule()
    }

    @objc private func handleModulePan(_ recognizer: UIPanGestureRecognizer) {
        guard let module = previewModule(for: recognizer.view) else {
            return
        }

        selectedPreviewModule = module
        previewView.bringSubviewToFront(moduleView(for: module))
        keepBrandPillOnTop()
        updatePreviewSelection()

        let translation = recognizer.translation(in: previewView)
        if module == .route {
            routeModuleTranslation = clampedModuleTranslation(
                for: module,
                proposed: CGPoint(
                    x: routeModuleTranslation.x + translation.x,
                    y: routeModuleTranslation.y + translation.y
                )
            )
        } else {
            metricsModuleTranslation = clampedModuleTranslation(
                for: module,
                proposed: CGPoint(
                    x: metricsModuleTranslation.x + translation.x,
                    y: metricsModuleTranslation.y + translation.y
                )
            )
        }
        applyModuleTransform(module)
        recognizer.setTranslation(.zero, in: previewView)
    }

    @objc private func handleModulePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let module = previewModule(for: recognizer.view) else {
            return
        }

        selectedPreviewModule = module
        previewView.bringSubviewToFront(moduleView(for: module))
        keepBrandPillOnTop()
        updatePreviewSelection()

        let currentScale = module == .route ? routeModuleScale : metricsModuleScale
        let proposedScale = min(max(currentScale * recognizer.scale, moduleMinimumScale), moduleMaximumScale)
        if module == .route {
            routeModuleScale = proposedScale
        } else {
            metricsModuleScale = proposedScale
        }
        applyModuleTransform(module)
        recognizer.scale = 1
    }

    @objc private func handleModuleRotation(_ recognizer: UIRotationGestureRecognizer) {
        guard let module = previewModule(for: recognizer.view) else {
            return
        }

        selectedPreviewModule = module
        previewView.bringSubviewToFront(moduleView(for: module))
        keepBrandPillOnTop()
        updatePreviewSelection()

        if module == .route {
            routeModuleRotation += recognizer.rotation
        } else {
            metricsModuleRotation += recognizer.rotation
        }
        applyModuleTransform(module)
        recognizer.rotation = 0
    }

    @objc private func handleBrandPillPan(_ recognizer: UIPanGestureRecognizer) {
        selectedPreviewModule = nil
        updatePreviewSelection()
        keepBrandPillOnTop()

        let translation = recognizer.translation(in: previewView)
        brandPillTranslation = clampedBrandPillTranslation(
            proposed: CGPoint(
                x: brandPillTranslation.x + translation.x,
                y: brandPillTranslation.y + translation.y
            )
        )
        applyBrandPillTransform()
        recognizer.setTranslation(.zero, in: previewView)

        if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
            snapBrandPillIntoPreviewBounds(animated: true)
        }
    }

    @objc private func handlePreviewBackgroundTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              selectedPreviewModule != nil else {
            return
        }

        selectedPreviewModule = nil
        updatePreviewSelection()
    }

    private func keepBrandPillOnTop() {
        previewView.bringSubviewToFront(brandPillView)
    }

    private func applyBrandPillTransform() {
        brandPillView.transform = CGAffineTransform(
            translationX: brandPillTranslation.x,
            y: brandPillTranslation.y
        )
    }

    private func clampedBrandPillTranslation(proposed: CGPoint) -> CGPoint {
        guard previewView.bounds.width > 0,
              previewView.bounds.height > 0,
              brandPillView.bounds.width > 0,
              brandPillView.bounds.height > 0 else {
            return proposed
        }

        let center = brandPillView.center
        let halfWidth = brandPillView.bounds.width / 2
        let halfHeight = brandPillView.bounds.height / 2
        let minCenterX = halfWidth + brandPillVisibleInset
        let maxCenterX = max(minCenterX, previewView.bounds.width - halfWidth - brandPillVisibleInset)
        let minCenterY = halfHeight + brandPillVisibleInset
        let maxCenterY = max(minCenterY, previewView.bounds.height - halfHeight - brandPillVisibleInset)
        let clampedCenterX = min(max(center.x + proposed.x, minCenterX), maxCenterX)
        let clampedCenterY = min(max(center.y + proposed.y, minCenterY), maxCenterY)
        return CGPoint(x: clampedCenterX - center.x, y: clampedCenterY - center.y)
    }

    private func snapBrandPillIntoPreviewBounds(animated: Bool) {
        let clampedTranslation = clampedBrandPillTranslation(proposed: brandPillTranslation)
        guard clampedTranslation != brandPillTranslation else {
            return
        }

        brandPillTranslation = clampedTranslation
        let changes = {
            self.applyBrandPillTransform()
        }

        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: changes
            )
        } else {
            changes()
        }
    }

    private func previewModule(for view: UIView?) -> PreviewModule? {
        if view === previewView {
            return selectedPreviewModule
        }
        if view === routeModuleView {
            return .route
        }
        if view === metricsModuleView {
            return .metrics
        }
        return nil
    }

    private func moduleView(for module: PreviewModule) -> UIView {
        switch module {
        case .route:
            return routeModuleView
        case .metrics:
            return metricsModuleView
        }
    }

    private func moduleScale(for module: PreviewModule) -> CGFloat {
        switch module {
        case .route:
            return routeModuleScale
        case .metrics:
            return metricsModuleScale
        }
    }

    private func moduleTranslation(for module: PreviewModule) -> CGPoint {
        switch module {
        case .route:
            return routeModuleTranslation
        case .metrics:
            return metricsModuleTranslation
        }
    }

    private func moduleRotation(for module: PreviewModule) -> CGFloat {
        switch module {
        case .route:
            return routeModuleRotation
        case .metrics:
            return metricsModuleRotation
        }
    }

    private func applyModuleTransform(_ module: PreviewModule) {
        let scale = moduleScale(for: module)
        let rotation = moduleRotation(for: module)
        let translation = moduleTranslation(for: module)
        let cosValue = cos(rotation) * scale
        let sinValue = sin(rotation) * scale
        moduleView(for: module).transform = CGAffineTransform(
            a: cosValue,
            b: sinValue,
            c: -sinValue,
            d: cosValue,
            tx: translation.x,
            ty: translation.y
        )
        updateSelectionChromeFrames()
    }

    private func clampedModuleTranslation(for module: PreviewModule, proposed: CGPoint) -> CGPoint {
        let moduleView = moduleView(for: module)
        guard previewView.bounds.width > 0, previewView.bounds.height > 0 else {
            return proposed
        }

        let scale = moduleScale(for: module)
        let center = moduleView.center
        let halfWidth = moduleView.bounds.width * scale / 2
        let halfHeight = moduleView.bounds.height * scale / 2
        let minimumVisibleLength: CGFloat = 32
        let minCenterX = -halfWidth + minimumVisibleLength
        let maxCenterX = previewView.bounds.width + halfWidth - minimumVisibleLength
        let minCenterY = -halfHeight + minimumVisibleLength
        let maxCenterY = previewView.bounds.height + halfHeight - minimumVisibleLength
        let clampedCenterX = min(max(center.x + proposed.x, minCenterX), maxCenterX)
        let clampedCenterY = min(max(center.y + proposed.y, minCenterY), maxCenterY)
        return CGPoint(x: clampedCenterX - center.x, y: clampedCenterY - center.y)
    }

    private func updatePreviewModuleVisibility() {
        let isPhotoBackground: Bool
        if case .photo = previewBackground {
            isPhotoBackground = true
        } else {
            isPhotoBackground = false
        }

        routeModuleView.isHidden = !isPhotoBackground || !isRouteModuleEnabled
        metricsModuleView.isHidden = !isMetricsModuleEnabled
        if selectedPreviewModule == .route, routeModuleView.isHidden {
            selectedPreviewModule = nil
        }
        if selectedPreviewModule == .metrics, metricsModuleView.isHidden {
            selectedPreviewModule = nil
        }
    }

    private func applyMetricsColor() {
        let color = colorOptions[selectedMetricsColorIndex]
        metricsModuleView.applyColor(color)
    }

    private func applyMapStyle(_ style: AppMapDisplayStyle) {
        selectedMapStyle = style
        selectMapBackground()
        AppMapStyle.apply(style, to: mapView)
        AppMapStyle.setToneOverlay(mapToneOverlay, visible: style == .appDefault, on: mapView)
        configureMapStyleButton()
    }

    private func updateToolBarVisibility() {
        let isMapBackground: Bool
        if case .map = previewBackground {
            isMapBackground = true
        } else {
            isMapBackground = false
        }

        mapStyleToolButton.isHidden = !isMapBackground
        deleteToolButton.isHidden = selectedPreviewModule == nil
        addRouteToolButton.isHidden = isMapBackground || isRouteModuleEnabled
        addMetricsToolButton.isHidden = isMetricsModuleEnabled

        let visibleButtonCount = [
            colorToolButton,
            mapStyleToolButton,
            deleteToolButton,
            addRouteToolButton,
            addMetricsToolButton
        ].filter { !$0.isHidden }.count
        toolsContainerWidthConstraint?.update(offset: CGFloat(max(visibleButtonCount, 1)) * 78)
        UIView.animate(withDuration: 0.18) {
            self.view.layoutIfNeeded()
        }
    }

    private func colorName(for index: Int) -> String {
        switch index {
        case 0:
            return "White"
        case 1:
            return "Black"
        case 2:
            return "Movinn"
        case 3:
            return "Blue"
        case 4:
            return "Orange"
        case 5:
            return "Pink"
        default:
            return AppLocalization.text(.color)
        }
    }

    private func colorSwatchImage(_ color: UIColor) -> UIImage? {
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3)
            color.setFill()
            UIBezierPath(ovalIn: rect).fill()
            UIColor.black.withAlphaComponent(color == .white ? 0.22 : 0).setStroke()
            let strokePath = UIBezierPath(ovalIn: rect)
            strokePath.lineWidth = 1
            strokePath.stroke()
        }
    }

    private func configureMapRouteOverlay() {
        let coordinates = workout.routeDetailDisplayCoordinates
        guard coordinates.count > 1 else {
            return
        }

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        routePolyline = polyline
        mapView.addOverlay(polyline, level: .aboveLabels)
        mapView.removeAnnotations(mapView.annotations)
        mapView.addAnnotations([
            RouteEndpointAnnotation(coordinate: coordinates[0], kind: .start),
            RouteEndpointAnnotation(coordinate: coordinates[coordinates.count - 1], kind: .end)
        ])
        fitMapRouteIfNeeded()
    }

    private func fitMapRouteIfNeeded() {
        guard case .map = previewBackground,
              let routePolyline,
              previewView.bounds.width > 0,
              previewView.bounds.height > 0 else {
            return
        }

        mapView.setVisibleMapRect(
            routePolyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 54, left: 34, bottom: 132, right: 34),
            animated: false
        )
    }

    @objc private func sharePreviewImage() {
        if let livePhotoAsset = selectedLivePhotoAsset() {
            exportAndShareLivePhoto(asset: livePhotoAsset)
            return
        }

        selectedPreviewModule = nil
        updatePreviewSelection()
        showExportLoading(text: AppLocalization.text(.photoSaving))
        view.layoutIfNeeded()
        let image = RouteSharePreviewRenderer.image(
            from: previewView,
            setSelectionChromeHidden: setSelectionChromeHidden,
            restoreSelection: updatePreviewSelection
        )
        RouteSharePhotoLibrarySaver.saveImage(image) { [weak self] result in
            guard let self else {
                return
            }

            hideExportLoading()
            switch result {
            case .success:
                showSavedToPhotosAlert()
            case .failure(let error):
                showAlert(title: AppLocalization.text(.share), message: error.localizedDescription)
            }
        }
    }

    private func selectedLivePhotoAsset() -> PHAsset? {
        guard case .photo(let index) = previewBackground,
              photoItems.indices.contains(index),
              case .routeMedia(let mediaItem) = photoItems[index],
              mediaItem.isLivePhoto else {
            return nil
        }

        return mediaItem.asset
    }

    private func exportAndShareLivePhoto(asset: PHAsset) {
        selectedPreviewModule = nil
        updatePreviewSelection()
        showExportLoading(text: AppLocalization.text(.livePhotoSaving))
        view.layoutIfNeeded()
        let outputSize = RouteSharePreviewRenderer.outputPixelSize(for: previewView.bounds.size)
        let overlayImage = RouteSharePreviewRenderer.overlayImage(
            from: previewView,
            backgroundViews: [
                mapContainerView,
                previewImageView,
                previewLivePhotoView,
                previewPlaceholderView
            ],
            outputSize: outputSize,
            setSelectionChromeHidden: setSelectionChromeHidden,
            restoreSelection: updatePreviewSelection
        )

        livePhotoExporter.export(
            asset: asset,
            overlayImage: overlayImage,
            outputSize: outputSize
        ) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let livePhotoExport):
                RouteSharePhotoLibrarySaver.saveLivePhoto(livePhotoExport) { [weak self] saveResult in
                    guard let self else {
                        return
                    }

                    hideExportLoading()
                    try? FileManager.default.removeItem(at: livePhotoExport.directoryURL)
                    switch saveResult {
                    case .success:
                        showSavedToPhotosAlert()
                    case .failure(let error):
                        showAlert(title: AppLocalization.text(.share), message: error.localizedDescription)
                    }
                }
            case .failure(let error):
                hideExportLoading()
                showAlert(title: AppLocalization.text(.share), message: error.localizedDescription)
            }
        }
    }

    private func showExportLoading(text: String) {
        navigationItem.rightBarButtonItem?.isEnabled = false
        exportLoadingView.show(text: text, in: view)
    }

    private func hideExportLoading() {
        navigationItem.rightBarButtonItem?.isEnabled = true
        exportLoadingView.hide()
    }

    private func showSavedToPhotosAlert() {
        let alertController = UIAlertController(
            title: AppLocalization.text(.livePhotoSaved),
            message: nil,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .cancel))
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.openPhotos), style: .default) { [weak self] _ in
            self?.openPhotosApp()
        })
        present(alertController, animated: true)
    }

    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else {
            return
        }
        UIApplication.shared.open(url)
    }

    private func showAlert(title: String, message: String? = nil) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .default))
        present(alertController, animated: true)
    }

    private func setSelectionChromeHidden(_ hidden: Bool) {
        routeSelectionBorderLayer.isHidden = hidden
        routeDeleteCornerButton.isHidden = hidden
        metricsSelectionBorderLayer.isHidden = hidden
        metricsDeleteCornerButton.isHidden = hidden
    }
}

extension WorkoutRouteShareViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        photoItems.count + 2
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: RouteSharePhotoCell.reuseIdentifier,
            for: indexPath
        )

        guard let cell = cell as? RouteSharePhotoCell else {
            return cell
        }

        if indexPath.item == 0 {
            let isSelected: Bool
            if case .map = previewBackground {
                isSelected = true
            } else {
                isSelected = false
            }
            cell.configureMap(isSelected: isSelected)
        } else if indexPath.item == photoItems.count + 1 {
            cell.configureAdd()
        } else {
            let photoIndex = indexPath.item - 1
            let item = photoItems[photoIndex]
            switch item {
            case .routeMedia(let mediaItem):
                cell.configure(asset: mediaItem.asset, isSelected: selectedPhotoIndex == photoIndex)
            case .uploaded(let image):
                cell.configure(image: image, isSelected: selectedPhotoIndex == photoIndex)
            }
        }

        return cell
    }
}

extension WorkoutRouteShareViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.item == 0 {
            selectMapBackground()
        } else if indexPath.item == photoItems.count + 1 {
            presentPhotoPicker()
        } else {
            selectPhoto(at: indexPath.item - 1)
        }
    }
}

extension WorkoutRouteShareViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        CGSize(width: 72, height: 72)
    }
}

extension WorkoutRouteShareViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard !results.isEmpty else {
            pendingUploadedSelectionID = nil
            return
        }

        let selectionID = pendingUploadedSelectionID
        results.forEach { result in
            guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else {
                return
            }

            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let image = object as? UIImage else {
                    return
                }

                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }

                    let newIndex = self.photoItems.count
                    self.photoItems.append(.uploaded(image))
                    if self.pendingUploadedSelectionID == selectionID {
                        self.selectedPhotoIndex = newIndex
                        self.previewBackground = .photo(newIndex)
                        self.applyDefaultColorsForCurrentBackground()
                        self.resetPreviewModuleAdjustments()
                        self.representedPreviewPhotoID = nil
                        self.pendingUploadedSelectionID = nil
                    }
                    self.photoCollectionView.reloadData()
                    self.updatePreviewPhoto()
                }
            }
        }
    }
}

extension WorkoutRouteShareViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer.view === previewView else {
            return true
        }

        if isPreviewModuleGesture(gestureRecognizer) {
            guard selectedPreviewModule != nil else {
                return false
            }

            return !interactivePreviewElementContains(touch)
        }

        if gestureRecognizer === previewBackgroundTapGesture {
            return !interactivePreviewElementContains(touch)
        }

        return true
    }

    private func interactivePreviewElementContains(_ touch: UITouch) -> Bool {
        let touchLocation = touch.location(in: previewView)
        let interactiveElementViews: [UIView] = [
            routeModuleView,
            metricsModuleView,
            routeDeleteCornerButton,
            metricsDeleteCornerButton,
            brandPillView
        ]
        return interactiveElementViews.contains { elementView in
            !elementView.isHidden && elementView.frame.contains(touchLocation)
        }
    }

    private func isPreviewModuleGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === previewModulePanGesture
            || gestureRecognizer === previewModulePinchGesture
            || gestureRecognizer === previewModuleRotationGesture
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let gestureView = gestureRecognizer.view,
              let otherGestureView = otherGestureRecognizer.view else {
            return false
        }

        if gestureView === previewView, otherGestureView === previewView {
            return isPreviewModuleGesture(gestureRecognizer)
                && isPreviewModuleGesture(otherGestureRecognizer)
        }

        let moduleViews = [routeModuleView, metricsModuleView]
        return moduleViews.contains { $0 === gestureView }
            && moduleViews.contains { $0 === otherGestureView }
    }
}

extension WorkoutRouteShareViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let renderer = AppMapStyle.renderer(for: overlay) {
            return renderer
        }

        guard let polyline = overlay as? MKPolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }

        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.strokeColor = colorOptions[selectedRouteColorIndex]
        renderer.lineWidth = 5
        renderer.lineJoin = .round
        renderer.lineCap = .round
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
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
}
