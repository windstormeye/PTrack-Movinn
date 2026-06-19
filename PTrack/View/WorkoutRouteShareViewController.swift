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
    private typealias CanvasAspectRatio = RouteShareCanvasAspectRatio
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
    private var aspectRatioToolButton: UIButton { toolBarView.aspectRatioButton }
    private var mapStyleToolButton: UIButton { toolBarView.mapStyleButton }
    private var deleteToolButton: UIButton { toolBarView.deleteButton }
    private var addRouteToolButton: UIButton { toolBarView.addRouteButton }
    private var addMetricsToolButton: UIButton { toolBarView.addMetricsButton }
    private let exportLoadingView = RouteShareExportLoadingView()
    private var toolsContainerWidthConstraint: Constraint?
    private weak var previewBackgroundTapGesture: UITapGestureRecognizer?
    private weak var previewBackgroundDoubleTapGesture: UITapGestureRecognizer?
    private weak var previewModulePanGesture: UIPanGestureRecognizer?
    private weak var previewModulePinchGesture: UIPinchGestureRecognizer?
    private weak var previewModuleRotationGesture: UIRotationGestureRecognizer?
    private var interactivePopBlockerGesture: UIScreenEdgePanGestureRecognizer?
    private var hasPlayedEntranceAnimation = false
    private var hasAppliedInitialModuleLayout = false
    private var hasShownAspectRatioAdjustmentToast = false

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
    private var selectedCanvasAspectRatio: CanvasAspectRatio = .followPhoto
    private var previewBackground: PreviewBackground
    private var routePolyline: MKPolyline?
    private var previewImageRequestID: PHImageRequestID?
    private var previewLivePhotoRequestID: PHImageRequestID?
    private var representedPreviewPhotoID: String?
    private var pendingUploadedSelectionID: UUID?
    private var lastSelectedPhotoIndexForAspectRatio: Int?
    private var isRouteModuleEnabled = true
    private var isMetricsModuleEnabled = true
    private var routeModuleScale: CGFloat = 1
    private var metricsModuleScale: CGFloat = 1
    private var routeModuleRotation: CGFloat = 0
    private var metricsModuleRotation: CGFloat = 0
    private var routeModuleTranslation: CGPoint = .zero
    private var metricsModuleTranslation: CGPoint = .zero
    private var brandPillTranslation: CGPoint = .zero
    private var backgroundMediaScale: CGFloat = 1
    private var backgroundMediaRotation: CGFloat = 0
    private var backgroundMediaTranslation: CGPoint = .zero
    private var isBackgroundAdjustmentEnabled = false
    private var hasManualMapAdjustment = false
    private var previousInteractivePopGestureEnabled: Bool?
    private let moduleMinimumScale: CGFloat = 0.35
    private let moduleMaximumScale: CGFloat = 3
    private let backgroundMediaMinimumScale: CGFloat = 0.35
    private let backgroundMediaMaximumScale: CGFloat = 4
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
        layout.minimumLineSpacing = 8
        layout.minimumInteritemSpacing = 8
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
        configureInteractivePopBlockerGesture()
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
        disableInteractivePopGesture()
        playEntranceAnimationIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNavigationBackgroundMask()
        updateSelectionChromeFrames()
        updatePreviewPhotoIfNeeded()
        updatePhotoBackgroundLayout()
        fitMapRouteIfNeeded()
        snapBrandPillIntoPreviewBounds(animated: false)
        applyInitialModuleLayoutIfNeeded()
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

    private func configureInteractivePopBlockerGesture() {
        let gestureRecognizer = UIScreenEdgePanGestureRecognizer(
            target: self,
            action: #selector(handleInteractivePopBlockerGesture(_:))
        )
        gestureRecognizer.edges = .left
        gestureRecognizer.cancelsTouchesInView = true
        gestureRecognizer.delegate = self
        view.addGestureRecognizer(gestureRecognizer)
        interactivePopBlockerGesture = gestureRecognizer
    }

    @objc private func handleInteractivePopBlockerGesture(_ gestureRecognizer: UIScreenEdgePanGestureRecognizer) {
        if gestureRecognizer.state == .began {
            disableInteractivePopGesture()
        }
    }

    private func disableInteractivePopGesture() {
        guard let gestureRecognizer = navigationController?.interactivePopGestureRecognizer else {
            return
        }

        if previousInteractivePopGestureEnabled == nil {
            previousInteractivePopGestureEnabled = gestureRecognizer.isEnabled
        }
        gestureRecognizer.isEnabled = false
        if let interactivePopBlockerGesture {
            gestureRecognizer.require(toFail: interactivePopBlockerGesture)
        }
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
        previewView.backgroundColor = .white
        previewView.layer.cornerRadius = 8
        previewView.layer.masksToBounds = true
        let previewBackgroundTapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePreviewBackgroundTap(_:)))
        previewBackgroundTapGesture.cancelsTouchesInView = false
        previewBackgroundTapGesture.delegate = self
        previewView.addGestureRecognizer(previewBackgroundTapGesture)
        self.previewBackgroundTapGesture = previewBackgroundTapGesture

        let previewBackgroundDoubleTapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handlePreviewBackgroundDoubleTap(_:))
        )
        previewBackgroundDoubleTapGesture.numberOfTapsRequired = 2
        previewBackgroundDoubleTapGesture.cancelsTouchesInView = false
        previewBackgroundDoubleTapGesture.delegate = self
        previewBackgroundTapGesture.require(toFail: previewBackgroundDoubleTapGesture)
        previewView.addGestureRecognizer(previewBackgroundDoubleTapGesture)
        self.previewBackgroundDoubleTapGesture = previewBackgroundDoubleTapGesture

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

        remakePreviewViewConstraints()

        mapContainerView.snp.makeConstraints { make in
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

    private func remakePreviewViewConstraints() {
        previewView.snp.remakeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(previewView.snp.width).multipliedBy(currentCanvasHeightMultiplier())
        }
    }

    private func currentCanvasHeightMultiplier() -> CGFloat {
        selectedCanvasAspectRatio.heightMultiplier(followingPhotoHeightMultiplier: currentPhotoHeightMultiplier())
    }

    private func currentPhotoHeightMultiplier() -> CGFloat? {
        if let selectedPhotoIndex,
           photoItems.indices.contains(selectedPhotoIndex),
           let heightMultiplier = photoItems[selectedPhotoIndex].heightMultiplier {
            return heightMultiplier
        }

        if let lastSelectedPhotoIndexForAspectRatio,
           photoItems.indices.contains(lastSelectedPhotoIndexForAspectRatio),
           let heightMultiplier = photoItems[lastSelectedPhotoIndexForAspectRatio].heightMultiplier {
            return heightMultiplier
        }

        return photoItems.first?.heightMultiplier
    }

    private func updatePreviewCanvasAspectRatio(animated: Bool, resetsModuleLayout: Bool = false) {
        if animated, !previewLivePhotoView.isHidden {
            previewLivePhotoView.stopPlayback()
        }

        remakePreviewViewConstraints()
        configureAspectRatioToolButton()

        let updates = {
            self.view.layoutIfNeeded()
            if resetsModuleLayout {
                self.resetBackgroundAdjustment()
                self.resetPreviewModuleAdjustments()
            }
            self.updatePhotoBackgroundLayout()
            self.fitMapRouteIfNeeded()
            self.updateSelectionChromeFrames()
            self.snapBrandPillIntoPreviewBounds(animated: false)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            updates()
        }
        CATransaction.commit()
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
            make.top.equalTo(previewView.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(66)
        }
    }

    private func configureToolsView() {
        configureColorToolButton()
        configureAspectRatioToolButton()
        configureDeleteToolButton()
        configureAddToolButtons()
        aspectRatioToolButton.showsMenuAsPrimaryAction = true
        mapStyleToolButton.showsMenuAsPrimaryAction = true
        configureMapStyleButton()

        contentView.addSubview(toolBarView)

        toolBarView.snp.makeConstraints { make in
            make.top.equalTo(photoCollectionView.snp.bottom).offset(10)
            make.leading.equalToSuperview().offset(16)
            make.height.equalTo(52)
            toolsContainerWidthConstraint = make.width.equalTo(RouteShareToolBarView.preferredWidth(for: 2)).constraint
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
        configureAspectRatioToolButton()
        configureMapStyleButton()
    }

    private func updateLocalizedText() {
        title = AppLocalization.text(.share)
        metricsModuleView.updateLocalizedText(for: workout)
        configureColorToolButton()
        configureAspectRatioToolButton()
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

    private func applyInitialModuleLayoutIfNeeded() {
        guard !hasAppliedInitialModuleLayout,
              previewView.bounds.width > 0,
              previewView.bounds.height > 0 else {
            return
        }

        hasAppliedInitialModuleLayout = true
        resetPreviewModuleAdjustments()
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

    private func configureAspectRatioToolButton() {
        aspectRatioToolButton.configuration = toolButtonConfiguration(
            title: AppLocalization.text(.aspectRatio),
            imageName: "aspectratio"
        )
        aspectRatioToolButton.menu = UIMenu(children: CanvasAspectRatio.allCases.map { aspectRatio in
            UIAction(
                title: aspectRatio.title,
                state: aspectRatio == selectedCanvasAspectRatio ? .on : .off
            ) { [weak self] _ in
                self?.applyCanvasAspectRatio(aspectRatio)
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
        configuration.imagePadding = 2
        configuration.title = title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 10, weight: .semibold)
            return outgoing
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 3, bottom: 5, trailing: 3)
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
                photoCollectionView.reloadData()
                updatePreviewCanvasAspectRatio(animated: true, resetsModuleLayout: true)
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
                updatePhotoBackgroundLayout()
            case .routeMedia(let mediaItem):
                if mediaItem.isLivePhoto {
                    previewImageView.isHidden = true
                    previewLivePhotoView.isHidden = false
                    updatePhotoBackgroundLayout()
                    requestPreviewLivePhoto(for: mediaItem.asset, representedID: item.id, playWhenReady: true)
                } else {
                    previewImageView.isHidden = false
                    previewLivePhotoView.isHidden = true
                    updatePhotoBackgroundLayout()
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
            updatePhotoBackgroundLayout()
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
            updatePhotoBackgroundLayout()
            if livePhoto != nil, playWhenReady {
                previewLivePhotoView.startPlayback(with: .full)
            }
        }
    }

    private func updatePhotoBackgroundLayout() {
        guard case .photo = previewBackground,
              let naturalSize = currentPhotoNaturalSize(),
              previewView.bounds.width > 0,
              previewView.bounds.height > 0 else {
            return
        }

        let baseSize = aspectFillSize(for: naturalSize, in: previewView.bounds.size)

        [previewImageView, previewLivePhotoView].forEach { backgroundView in
            backgroundView.bounds = CGRect(origin: .zero, size: baseSize)
            backgroundView.center = CGPoint(x: previewView.bounds.midX, y: previewView.bounds.midY)
            backgroundView.transform = CGAffineTransform(translationX: backgroundMediaTranslation.x, y: backgroundMediaTranslation.y)
                .rotated(by: backgroundMediaRotation)
                .scaledBy(x: backgroundMediaScale, y: backgroundMediaScale)
        }
    }

    private func currentPhotoNaturalSize() -> CGSize? {
        guard case .photo(let selectedPhotoIndex) = previewBackground,
              photoItems.indices.contains(selectedPhotoIndex) else {
            return nil
        }

        switch photoItems[selectedPhotoIndex] {
        case .routeMedia(let mediaItem):
            return CGSize(width: mediaItem.asset.pixelWidth, height: mediaItem.asset.pixelHeight)
        case .uploaded(let image):
            return image.size
        }
    }

    private func aspectFillSize(for contentSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard contentSize.width > 0,
              contentSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return containerSize
        }

        let scale = max(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        return CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    }

    private func clampedBackgroundMediaTranslation(
        proposed: CGPoint,
        scale: CGFloat,
        baseSize: CGSize? = nil
    ) -> CGPoint {
        guard previewView.bounds.width > 0,
              previewView.bounds.height > 0 else {
            return proposed
        }

        let resolvedBaseSize = baseSize ?? currentPhotoNaturalSize().map {
            aspectFillSize(for: $0, in: previewView.bounds.size)
        } ?? previewView.bounds.size
        let scaledSize = CGSize(
            width: resolvedBaseSize.width * scale,
            height: resolvedBaseSize.height * scale
        )
        let maxX = max((scaledSize.width - previewView.bounds.width) / 2, 0)
        let maxY = max((scaledSize.height - previewView.bounds.height) / 2, 0)
        return CGPoint(
            x: min(max(proposed.x, -maxX), maxX),
            y: min(max(proposed.y, -maxY), maxY)
        )
    }

    private func resetBackgroundAdjustment() {
        isBackgroundAdjustmentEnabled = false
        backgroundMediaScale = 1
        backgroundMediaRotation = 0
        backgroundMediaTranslation = .zero
        hasManualMapAdjustment = false
        resetMapCameraHeading()
        updatePhotoBackgroundLayout()
    }

    private func selectPhoto(at index: Int) {
        guard photoItems.indices.contains(index) else {
            return
        }

        if selectedPhotoIndex == index {
            lastSelectedPhotoIndexForAspectRatio = index
            if photoItems[index].isLivePhoto {
                replayPreviewLivePhoto()
            }
            return
        }

        selectedPhotoIndex = index
        lastSelectedPhotoIndexForAspectRatio = index
        previewBackground = .photo(index)
        applyDefaultColorsForCurrentBackground()
        representedPreviewPhotoID = nil
        photoCollectionView.reloadData()
        updatePreviewCanvasAspectRatio(animated: true, resetsModuleLayout: true)
        updatePreviewPhoto()
        updateToolBarVisibility()

    }

    private func replayPreviewLivePhoto() {
        guard previewLivePhotoView.livePhoto != nil else {
            return
        }

        previewLivePhotoView.stopPlayback()
        previewLivePhotoView.startPlayback(with: .full)
    }

    private func selectMapBackground(usesDefaultMapAspectRatio: Bool = true) {
        selectedPhotoIndex = nil
        if usesDefaultMapAspectRatio {
            selectedCanvasAspectRatio = .portrait3x4
        }
        previewBackground = .map
        applyDefaultColorsForCurrentBackground()
        representedPreviewPhotoID = nil
        photoCollectionView.reloadData()
        updatePreviewCanvasAspectRatio(animated: true, resetsModuleLayout: true)
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
        routeModuleScale = defaultModuleScale(for: .route)
        metricsModuleScale = defaultModuleScale(for: .metrics)
        routeModuleRotation = 0
        metricsModuleRotation = 0
        routeModuleTranslation = defaultModuleTranslation(for: .route, scale: routeModuleScale)
        metricsModuleTranslation = defaultModuleTranslation(for: .metrics, scale: metricsModuleScale)
        brandPillTranslation = .zero
        applyModuleTransform(.route)
        applyModuleTransform(.metrics)
        applyBrandPillTransform()
        isBackgroundAdjustmentEnabled = false
        selectedPreviewModule = nil
        updatePreviewSelection()
    }

    private func resetPreviewModuleAdjustment(for module: PreviewModule) {
        let scale = defaultModuleScale(for: module)
        switch module {
        case .route:
            routeModuleScale = scale
            routeModuleRotation = 0
            routeModuleTranslation = defaultModuleTranslation(for: module, scale: scale)
        case .metrics:
            metricsModuleScale = scale
            metricsModuleRotation = 0
            metricsModuleTranslation = defaultModuleTranslation(for: module, scale: scale)
        }
        applyModuleTransform(module)
    }

    private func defaultModuleScale(for module: PreviewModule) -> CGFloat {
        let heightMultiplier = currentRenderedCanvasHeightMultiplier()
        switch module {
        case .route:
            if heightMultiplier <= 0.62 {
                return 0.48
            }
            if heightMultiplier < 0.92 {
                return 0.64
            }
            return 1
        case .metrics:
            if heightMultiplier <= 0.62 {
                return 0.66
            }
            if heightMultiplier < 0.92 {
                return 0.78
            }
            return 1
        }
    }

    private func currentRenderedCanvasHeightMultiplier() -> CGFloat {
        guard previewView.bounds.width > 0, previewView.bounds.height > 0 else {
            return currentCanvasHeightMultiplier()
        }
        return previewView.bounds.height / previewView.bounds.width
    }

    private func defaultModuleTranslation(for module: PreviewModule, scale: CGFloat) -> CGPoint {
        guard previewView.bounds.width > 0, previewView.bounds.height > 0 else {
            return .zero
        }

        let moduleView = moduleView(for: module)
        let center = moduleView.center
        let scaledSize = CGSize(
            width: moduleView.bounds.width * scale,
            height: moduleView.bounds.height * scale
        )
        let heightMultiplier = currentRenderedCanvasHeightMultiplier()

        switch module {
        case .route:
            let margin: CGFloat = heightMultiplier < 0.92 ? 14 : 22
            let targetCenter = CGPoint(
                x: margin + scaledSize.width / 2,
                y: margin + scaledSize.height / 2
            )
            return CGPoint(x: targetCenter.x - center.x, y: targetCenter.y - center.y)
        case .metrics:
            let margin: CGFloat = heightMultiplier < 0.92 ? 14 : 22
            let targetCenter = CGPoint(
                x: previewView.bounds.midX,
                y: previewView.bounds.height - margin - scaledSize.height / 2
            )
            return CGPoint(x: targetCenter.x - center.x, y: targetCenter.y - center.y)
        }
    }

    @objc private func selectRouteModule() {
        guard !routeModuleView.isHidden else {
            return
        }
        isBackgroundAdjustmentEnabled = false
        selectedPreviewModule = .route
        previewView.bringSubviewToFront(routeModuleView)
        keepBrandPillOnTop()
        updatePreviewSelection()
    }

    @objc private func selectMetricsModule() {
        guard !metricsModuleView.isHidden else {
            return
        }
        isBackgroundAdjustmentEnabled = false
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
        resetPreviewModuleAdjustment(for: .route)
        isBackgroundAdjustmentEnabled = false
        selectedPreviewModule = .route
        previewView.bringSubviewToFront(routeModuleView)
        keepBrandPillOnTop()
        updatePreviewModuleVisibility()
        updatePreviewSelection()
    }

    @objc private func addMetricsModule() {
        isMetricsModuleEnabled = true
        resetPreviewModuleAdjustment(for: .metrics)
        isBackgroundAdjustmentEnabled = false
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
        if recognizer.view === previewView, isBackgroundAdjustmentEnabled {
            handleBackgroundPan(recognizer)
            return
        }

        guard let module = previewModule(for: recognizer.view) else {
            return
        }

        isBackgroundAdjustmentEnabled = false
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
        if recognizer.view === previewView, isBackgroundAdjustmentEnabled {
            handleBackgroundPinch(recognizer)
            return
        }

        guard let module = previewModule(for: recognizer.view) else {
            return
        }

        isBackgroundAdjustmentEnabled = false
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
        if recognizer.view === previewView, isBackgroundAdjustmentEnabled {
            handleBackgroundRotation(recognizer)
            return
        }

        guard let module = previewModule(for: recognizer.view) else {
            return
        }

        isBackgroundAdjustmentEnabled = false
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
        isBackgroundAdjustmentEnabled = false
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

    private func handleBackgroundPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: previewView)
        switch previewBackground {
        case .photo:
            backgroundMediaTranslation = CGPoint(
                x: backgroundMediaTranslation.x + translation.x,
                y: backgroundMediaTranslation.y + translation.y
            )
            updatePhotoBackgroundLayout()
        case .map:
            panMapBackground(by: translation)
        }
        recognizer.setTranslation(.zero, in: previewView)
    }

    private func handleBackgroundPinch(_ recognizer: UIPinchGestureRecognizer) {
        switch previewBackground {
        case .photo:
            backgroundMediaScale = min(
                max(backgroundMediaScale * recognizer.scale, backgroundMediaMinimumScale),
                backgroundMediaMaximumScale
            )
            updatePhotoBackgroundLayout()
        case .map:
            zoomMapBackground(by: recognizer.scale)
        }
        recognizer.scale = 1
    }

    private func handleBackgroundRotation(_ recognizer: UIRotationGestureRecognizer) {
        switch previewBackground {
        case .photo:
            backgroundMediaRotation += recognizer.rotation
            updatePhotoBackgroundLayout()
        case .map:
            rotateMapBackground(by: recognizer.rotation)
        }
        recognizer.rotation = 0
    }

    private func panMapBackground(by translation: CGPoint) {
        guard translation != .zero,
              previewView.bounds.width > 0,
              previewView.bounds.height > 0 else {
            return
        }

        let centerPoint = mapView.convert(mapView.centerCoordinate, toPointTo: mapView)
        let adjustedPoint = CGPoint(
            x: centerPoint.x - translation.x,
            y: centerPoint.y - translation.y
        )
        mapView.setCenter(mapView.convert(adjustedPoint, toCoordinateFrom: mapView), animated: false)
        hasManualMapAdjustment = true
    }

    private func zoomMapBackground(by scale: CGFloat) {
        guard scale > 0,
              mapView.visibleMapRect.size.width > 0,
              mapView.visibleMapRect.size.height > 0 else {
            return
        }

        let currentMapRect = mapView.visibleMapRect
        let zoomFactor = 1 / scale
        let minDimension: Double = 20
        let maxDimension = MKMapRect.world.size.width
        let targetWidth = min(max(currentMapRect.size.width * zoomFactor, minDimension), maxDimension)
        let targetHeight = min(max(currentMapRect.size.height * zoomFactor, minDimension), maxDimension)
        let targetRect = MKMapRect(
            x: currentMapRect.midX - targetWidth / 2,
            y: currentMapRect.midY - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )
        mapView.setVisibleMapRect(targetRect, animated: false)
        hasManualMapAdjustment = true
    }

    private func rotateMapBackground(by rotation: CGFloat) {
        guard rotation != 0 else {
            return
        }

        let camera = mapView.camera
        camera.heading = normalizedMapHeading(camera.heading + CLLocationDirection(rotation * 180 / .pi))
        mapView.setCamera(camera, animated: false)
        hasManualMapAdjustment = true
    }

    private func normalizedMapHeading(_ heading: CLLocationDirection) -> CLLocationDirection {
        let normalizedHeading = heading.truncatingRemainder(dividingBy: 360)
        return normalizedHeading >= 0 ? normalizedHeading : normalizedHeading + 360
    }

    private func resetMapCameraHeading() {
        let camera = mapView.camera
        guard camera.heading != 0 else {
            return
        }

        camera.heading = 0
        mapView.setCamera(camera, animated: false)
    }

    @objc private func handlePreviewBackgroundTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              selectedPreviewModule != nil || isBackgroundAdjustmentEnabled else {
            return
        }

        isBackgroundAdjustmentEnabled = false
        selectedPreviewModule = nil
        updatePreviewSelection()
    }

    @objc private func handlePreviewBackgroundDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        selectedPreviewModule = nil
        isBackgroundAdjustmentEnabled = true
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
        if case .map = previewBackground {
            isBackgroundAdjustmentEnabled = false
            selectedPreviewModule = nil
            updatePreviewSelection()
        } else {
            selectMapBackground(usesDefaultMapAspectRatio: false)
        }
        AppMapStyle.apply(style, to: mapView)
        AppMapStyle.setToneOverlay(mapToneOverlay, visible: style == .appDefault, on: mapView)
        configureMapStyleButton()
    }

    private func applyCanvasAspectRatio(_ aspectRatio: CanvasAspectRatio) {
        selectedCanvasAspectRatio = aspectRatio
        updatePreviewCanvasAspectRatio(animated: true, resetsModuleLayout: true)
        showAspectRatioAdjustmentToastIfNeeded()
    }

    private func showAspectRatioAdjustmentToastIfNeeded() {
        guard !hasShownAspectRatioAdjustmentToast else {
            return
        }

        hasShownAspectRatioAdjustmentToast = true
        Toast.show(AppLocalization.text(.photoBackgroundAdjustmentHint), in: view)
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
            aspectRatioToolButton,
            mapStyleToolButton,
            deleteToolButton,
            addRouteToolButton,
            addMetricsToolButton
        ].filter { !$0.isHidden }.count
        toolsContainerWidthConstraint?.update(offset: RouteShareToolBarView.preferredWidth(for: visibleButtonCount))
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
              !hasManualMapAdjustment,
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
            outputSize: outputSize,
            backgroundTransform: currentBackgroundRenderTransform(outputSize: outputSize)
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

    private func currentBackgroundRenderTransform(outputSize: CGSize) -> RouteShareBackgroundRenderTransform {
        guard previewView.bounds.width > 0 else {
            return RouteShareBackgroundRenderTransform(
                scale: backgroundMediaScale,
                translation: .zero,
                rotation: backgroundMediaRotation
            )
        }

        let outputScale = outputSize.width / previewView.bounds.width
        return RouteShareBackgroundRenderTransform(
            scale: backgroundMediaScale,
            translation: CGPoint(
                x: backgroundMediaTranslation.x * outputScale,
                y: backgroundMediaTranslation.y * outputScale
            ),
            rotation: backgroundMediaRotation
        )
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
        CGSize(width: 58, height: 58)
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
                        self.lastSelectedPhotoIndexForAspectRatio = newIndex
                        self.previewBackground = .photo(newIndex)
                        self.applyDefaultColorsForCurrentBackground()
                        self.representedPreviewPhotoID = nil
                        self.pendingUploadedSelectionID = nil
                        self.updatePreviewCanvasAspectRatio(animated: true, resetsModuleLayout: true)
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
            if selectedPreviewModule != nil {
                return !interactivePreviewElementContains(touch)
            }

            guard isBackgroundAdjustmentEnabled else {
                return false
            }

            return !interactivePreviewElementContains(touch)
        }

        if gestureRecognizer === previewBackgroundTapGesture
            || gestureRecognizer === previewBackgroundDoubleTapGesture {
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
            if isBackgroundAdjustmentEnabled {
                return isPreviewModuleGesture(gestureRecognizer)
                    && isPreviewModuleGesture(otherGestureRecognizer)
            }

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
