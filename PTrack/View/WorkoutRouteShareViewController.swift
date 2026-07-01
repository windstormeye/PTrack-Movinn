//
//  WorkoutRouteShareViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/19.
//

import AVFoundation
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

    private enum LivePhotoExportSource {
        case photo(PHAsset)
        case collage([CollageLivePhotoExportSource])
    }

    private struct CollageLivePhotoExportSource {
        let asset: PHAsset
        let tileIndex: Int
    }

    private struct CollageLivePhotoPreviewInfo {
        let freezeImage: UIImage?
        let duration: TimeInterval
    }

    private let workout: TrackedWorkout
    private let mediaStore = RouteMediaStore()
    private let livePhotoExporter = RouteShareLivePhotoExporter()
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let previewContainerView = UIView()
    private let previewView = UIView()
    private let bottomControlsView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let mapContainerView = AppMapContainerView()
    private var mapView: MKMapView { mapContainerView.mapView }
    private let mapToneOverlay = AppMapStyle.makeToneOverlay()
    private let previewImageView = UIImageView()
    private let previewLivePhotoView = PHLivePhotoView()
    private let collageView = RouteShareCollageView()
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
    private let toolBarScrollView = UIScrollView()
    private let toolBarView = RouteShareToolBarView()
    private var canvasColorToolButton: UIButton { toolBarView.canvasColorButton }
    private var colorToolButton: UIButton { toolBarView.colorButton }
    private var calorieFoodToolButton: UIButton { toolBarView.calorieFoodButton }
    private var aspectRatioToolButton: UIButton { toolBarView.aspectRatioButton }
    private var mapStyleToolButton: UIButton { toolBarView.mapStyleButton }
    private var collageToolButton: UIButton { toolBarView.collageButton }
    private var collageStyleToolButton: UIButton { toolBarView.collageStyleButton }
    private var deleteToolButton: UIButton { toolBarView.deleteButton }
    private var addRouteToolButton: UIButton { toolBarView.addRouteButton }
    private var addMetricsToolButton: UIButton { toolBarView.addMetricsButton }
    private var livePhotoToolButton: UIButton { toolBarView.livePhotoButton }
    private let exportLoadingView = RouteShareExportLoadingView()
    private lazy var exportBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "checkmark"),
        style: .done,
        target: self,
        action: #selector(sharePreviewImage)
    )
    private lazy var resetBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "arrow.counterclockwise"),
        style: .plain,
        target: self,
        action: #selector(resetShareCanvas)
    )
    private var toolsContainerWidthConstraint: Constraint?
    private weak var previewBackgroundTapGesture: UITapGestureRecognizer?
    private weak var previewBackgroundDoubleTapGesture: UITapGestureRecognizer?
    private weak var previewContainerTapGesture: UITapGestureRecognizer?
    private weak var previewModulePanGesture: UIPanGestureRecognizer?
    private weak var previewModulePinchGesture: UIPinchGestureRecognizer?
    private weak var previewModuleRotationGesture: UIRotationGestureRecognizer?
    private var interactivePopBlockerGesture: UIScreenEdgePanGestureRecognizer?
    private var hasPlayedEntranceAnimation = false
    private var hasAppliedInitialModuleLayout = false
    private var hasShownInitialBackgroundAdjustmentToast = false
    private var isExportChromeHidden = false
    private var hasPreparedForPermanentDismissal = false

    private var photoItems: [SharePhotoItem]
    private var selectedPhotoIndex: Int?
    private var collagePhotoIndices: [Int] = []
    private var selectedCollageStyleIndex = 0
    private var selectedCollageLayout: RouteShareCollageLayout?
    private var selectedPreviewModule: PreviewModule?
    private var selectedRouteColorIndex = 0 {
        didSet {
            routePathView.setStrokeColor(effectiveRouteColor)
            mapView.removeOverlays(mapView.overlays.filter { !($0 is AppMapToneTileOverlay) })
            configureMapRouteOverlay()
        }
    }
    private var selectedMetricsColorIndex = 0 {
        didSet {
            applyMetricsColor()
        }
    }
    private var selectedRouteCustomColor: UIColor? {
        didSet {
            routePathView.setStrokeColor(effectiveRouteColor)
            mapView.removeOverlays(mapView.overlays.filter { !($0 is AppMapToneTileOverlay) })
            configureMapRouteOverlay()
        }
    }
    private var selectedMetricsCustomColor: UIColor? {
        didSet {
            applyMetricsColor()
        }
    }
    private var selectedMapStyle = AppMapDisplayStyleStore.shared.routeDetailStyle()
    private var selectedCanvasAspectRatio: CanvasAspectRatio = .followPhoto
    private var selectedCanvasColor: UIColor = .white {
        didSet {
            applySelectedCanvasColor()
            configureCanvasColorToolButton()
        }
    }
    private var previewBackground: PreviewBackground
    private var routePolyline: MKPolyline?
    private var previewImageRequestID: PHImageRequestID?
    private var previewLivePhotoRequestID: PHImageRequestID?
    private var collageLivePhotoRequestIDs: [PHImageRequestID] = []
    private var collageLivePhotoFrameTasks: [Task<Void, Never>] = []
    private var collageLivePhotoPlaybackToken = UUID()
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
    private weak var previousInteractivePopGestureDelegate: UIGestureRecognizerDelegate?
    private let moduleMinimumScale: CGFloat = 0.35
    private let moduleMaximumScale: CGFloat = 3
    private let backgroundMediaMinimumScale: CGFloat = 0.35
    private let backgroundMediaMaximumScale: CGFloat = 4
    private let routeModuleBaseSize: CGFloat = 196
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
    private let canvasColorOptions: [(nameKey: AppTextKey, color: UIColor)] = [
        (.colorWhite, .white),
        (.colorGray, UIColor(white: 0.94, alpha: 1)),
        (.colorBlack, .black),
        (.colorBlue, .systemBlue),
        (.colorOrange, .systemOrange),
        (.colorPink, .systemPink)
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

    private var isMapPreviewBackground: Bool {
        if case .map = previewBackground {
            return true
        }
        return false
    }

    private var mapPreviewContentColor: UIColor {
        selectedMapStyle == .dark ? .white : .black
    }

    private var effectiveRouteColor: UIColor {
        isMapPreviewBackground ? mapPreviewContentColor : routeModuleColor
    }

    private var effectiveMetricsColor: UIColor {
        isMapPreviewBackground ? mapPreviewContentColor : metricsModuleColor
    }

    private var routeModuleColor: UIColor {
        selectedRouteCustomColor ?? colorOptions[selectedRouteColorIndex]
    }

    private var metricsModuleColor: UIColor {
        selectedMetricsCustomColor ?? colorOptions[selectedMetricsColorIndex]
    }

    private var mapPreviewContentColorIndex: Int {
        selectedMapStyle == .dark ? 0 : 1
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        prepareForPermanentDismissal()
        NotificationCenter.default.removeObserver(self)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppAppearanceStore.shared.preferredStatusBarStyle(for: traitCollection)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureInteractivePopBlockerGesture()
        configureScrollView()
        configureBottomControlsView()
        configurePreviewView()
        configurePhotoCollectionView()
        configureToolsView()
        configureNavigationBackgroundView()
        configureExportLoadingView()
        registerObservers()
        registerTraitChangeHandler()
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isPermanentlyLeaving {
            prepareForPermanentDismissal()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        disableInteractivePopGesture()
        DispatchQueue.main.async { [weak self] in
            self?.disableInteractivePopGesture()
        }
        playEntranceAnimationIfNeeded()
        showInitialBackgroundAdjustmentToastIfNeeded()
    }

    private var isPermanentlyLeaving: Bool {
        isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true
    }

    private func prepareForPermanentDismissal() {
        guard !hasPreparedForPermanentDismissal else {
            return
        }

        hasPreparedForPermanentDismissal = true
        restoreInteractivePopGesture()
        cancelPreviewMediaRequests()
        cancelCollageLivePhotoRequest()
        collageView.clear()
        previewImageView.image = nil
        previewLivePhotoView.stopPlayback()
        previewLivePhotoView.livePhoto = nil
        photoCollectionView.dataSource = nil
        photoCollectionView.delegate = nil
        mapView.delegate = nil
        if !mapView.overlays.isEmpty {
            mapView.removeOverlays(mapView.overlays)
        }
        if !mapView.annotations.isEmpty {
            mapView.removeAnnotations(mapView.annotations)
        }
        routePolyline = nil
        mapView.layer.removeAllAnimations()
        mapContainerView.layer.removeAllAnimations()
        view.layer.removeAllAnimations()
        AppMapContainerView.retainForMetalDrain(mapContainerView)
    }

    private func cancelPreviewMediaRequests() {
        if let previewImageRequestID {
            PHImageManager.default().cancelImageRequest(previewImageRequestID)
            self.previewImageRequestID = nil
        }
        if let previewLivePhotoRequestID {
            PHImageManager.default().cancelImageRequest(previewLivePhotoRequestID)
            self.previewLivePhotoRequestID = nil
        }
        previewLivePhotoView.stopPlayback()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSelectionChromeFrames()
        updatePreviewPhotoIfNeeded()
        updatePhotoBackgroundLayout()
        fitMapRouteIfNeeded()
        snapBrandPillIntoPreviewBounds(animated: false)
        applyInitialModuleLayoutIfNeeded()
    }

    private func configureNavigationItem() {
        view.backgroundColor = AppColors.sharePageBackground
        navigationItem.largeTitleDisplayMode = .never
        exportBarButtonItem.tintColor = AppColors.movinnGreen
        resetBarButtonItem.tintColor = AppColors.solidForeground
        resetBarButtonItem.isEnabled = true
        navigationItem.rightBarButtonItems = [exportBarButtonItem, resetBarButtonItem]
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
        exportBarButtonItem.tintColor = AppColors.movinnGreen
        resetBarButtonItem.tintColor = AppColors.solidForeground
    }

    @objc private func resetShareCanvas() {
        let currentBackground = previewBackground

        clearPreviewSelections()
        cancelCollageLivePhotoRequest()
        collageView.stopLivePhotoPlayback()
        collageView.resetCropAdjustments()

        selectedCanvasAspectRatio = .followPhoto
        selectedCanvasColor = .white
        selectedMapStyle = AppMapDisplayStyleStore.shared.routeDetailStyle()
        collagePhotoIndices = defaultCollagePhotoIndices()
        selectedCollageStyleIndex = 0
        selectedCollageLayout = collageLayoutForCurrentStyle(photoCount: collageSlotCount())
        representedPreviewPhotoID = nil

        switch currentBackground {
        case .map:
            selectedPhotoIndex = nil
            lastSelectedPhotoIndexForAspectRatio = nil
            selectedCanvasAspectRatio = .portrait3x4
            previewBackground = .map
        case .collage where photoItems.count >= 2:
            selectedPhotoIndex = nil
            lastSelectedPhotoIndexForAspectRatio = nil
            previewBackground = .collage
        case .photo, .collage:
            selectedPhotoIndex = photoItems.isEmpty ? nil : 0
            lastSelectedPhotoIndexForAspectRatio = selectedPhotoIndex
            previewBackground = photoItems.isEmpty ? .map : .photo(0)
        }

        applyDefaultColorsForCurrentBackground()

        isRouteModuleEnabled = true
        isMetricsModuleEnabled = true
        isBackgroundAdjustmentEnabled = false
        hasManualMapAdjustment = false
        selectedPreviewModule = nil

        AppMapStyle.apply(selectedMapStyle, to: mapView)
        AppMapStyle.setToneOverlay(mapToneOverlay, visible: selectedMapStyle == .appDefault, on: mapView)
        configureMapStyleButton()
        configureAspectRatioToolButton()

        photoCollectionView.reloadData()
        updatePreviewCanvasAspectRatio(animated: true, resetsModuleLayout: true)
        updatePreviewPhoto()
        updatePreviewSelection()
        updateToolBarVisibility()
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
            previousInteractivePopGestureDelegate = gestureRecognizer.delegate
        }
        gestureRecognizer.isEnabled = false
        gestureRecognizer.delegate = self
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
        gestureRecognizer.delegate = previousInteractivePopGestureDelegate
        self.previousInteractivePopGestureEnabled = nil
        previousInteractivePopGestureDelegate = nil
    }

    private func configureScrollView() {
        scrollView.backgroundColor = AppColors.sharePageBackground
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.contentInset = UIEdgeInsets(
            top: navigationBackgroundHeight,
            left: 0,
            bottom: 190,
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

    private func configureBottomControlsView() {
        updateInterfaceAppearanceColors()

        view.addSubview(bottomControlsView)

        bottomControlsView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    private func configurePreviewView() {
        previewContainerView.backgroundColor = .clear
        let previewContainerTapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePreviewContainerTap(_:)))
        previewContainerTapGesture.cancelsTouchesInView = false
        previewContainerTapGesture.delegate = self
        previewContainerView.addGestureRecognizer(previewContainerTapGesture)
        self.previewContainerTapGesture = previewContainerTapGesture

        previewView.backgroundColor = selectedCanvasColor
        previewView.clipsToBounds = true
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

        collageView.isHidden = true
        collageView.setCanvasColor(selectedCanvasColor)
        collageView.onLayoutChanged = { [weak self] layout in
            self?.selectedCollageLayout = layout
        }
        collageView.onCanvasTap = { [weak self] in
            self?.clearPreviewSelections()
        }
        collageView.onCropInteraction = { [weak self] in
            self?.clearElementSelectionForPreviewInteraction()
            self?.updateVisiblePhotoBrowserCellStates()
        }

        previewPlaceholderView.backgroundColor = AppColors.placeholderBackground
        previewPlaceholderIconView.image = UIImage(
            systemName: "photo",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        )
        previewPlaceholderIconView.tintColor = AppColors.foreground(alpha: 0.22)
        previewPlaceholderIconView.contentMode = .scaleAspectFit

        routeModuleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectRouteModule)))
        routeModuleView.configure(with: workout, color: effectiveRouteColor)

        metricsModuleView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectMetricsModule)))
        metricsModuleView.configure(with: workout, color: effectiveMetricsColor)
        configureModuleGestures()
        configureBrandPillGestures()
        configureModuleSelectionChrome()

        contentView.addSubview(previewContainerView)
        previewContainerView.addSubview(previewView)
        previewView.addSubview(mapContainerView)
        previewView.addSubview(previewImageView)
        previewView.addSubview(previewLivePhotoView)
        previewView.addSubview(collageView)
        previewView.addSubview(previewPlaceholderView)
        previewPlaceholderView.addSubview(previewPlaceholderIconView)
        previewView.addSubview(routeModuleView)
        previewView.addSubview(metricsModuleView)
        previewView.addSubview(routeDeleteCornerButton)
        previewView.addSubview(metricsDeleteCornerButton)
        previewView.addSubview(brandPillView)

        previewContainerView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(previewContainerView.snp.width).multipliedBy(CanvasAspectRatio.fallbackHeightMultiplier)
            make.bottom.equalToSuperview().inset(24)
        }

        remakePreviewViewConstraints()

        mapContainerView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        collageView.snp.makeConstraints { make in
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
            make.width.height.equalTo(routeModuleBaseSize)
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
        let canvasHeightMultiplier = currentCanvasHeightMultiplier()
        previewView.snp.remakeConstraints { make in
            make.center.equalToSuperview()
            if canvasHeightMultiplier <= CanvasAspectRatio.fallbackHeightMultiplier {
                make.leading.trailing.equalToSuperview()
                make.height.equalTo(previewView.snp.width).multipliedBy(canvasHeightMultiplier)
            } else {
                make.top.bottom.equalToSuperview()
                make.width.equalTo(previewView.snp.height).multipliedBy(1 / canvasHeightMultiplier)
            }
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
        let chromeRect = selectionChromeRect(for: moduleView)
        deleteButton.center = moduleView.convert(
            CGPoint(x: chromeRect.maxX, y: chromeRect.minY),
            to: previewView
        )
    }

    private func selectionBorderPath(for moduleView: UIView) -> CGPath {
        let chromeRect = selectionChromeRect(for: moduleView)
        let corners = [
            CGPoint(x: chromeRect.minX, y: chromeRect.minY),
            CGPoint(x: chromeRect.maxX, y: chromeRect.minY),
            CGPoint(x: chromeRect.maxX, y: chromeRect.maxY),
            CGPoint(x: chromeRect.minX, y: chromeRect.maxY)
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

    private func selectionChromeRect(for moduleView: UIView) -> CGRect {
        if let routeModuleView = moduleView as? RouteShareRouteModuleView {
            return routeModuleView.selectionChromeRect()
        }

        if let metricsModuleView = moduleView as? RouteShareMetricsModuleView {
            return metricsModuleView.selectionChromeRect()
        }

        return moduleView.bounds
    }

    private func configurePhotoCollectionView() {
        photoCollectionView.backgroundColor = .clear
        photoCollectionView.showsHorizontalScrollIndicator = false
        photoCollectionView.alwaysBounceHorizontal = true
        photoCollectionView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        photoCollectionView.dataSource = self
        photoCollectionView.delegate = self
        photoCollectionView.register(RouteSharePhotoCell.self, forCellWithReuseIdentifier: RouteSharePhotoCell.reuseIdentifier)

        bottomControlsView.contentView.addSubview(photoCollectionView)

        photoCollectionView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(66)
        }
    }

    private func configureToolsView() {
        configureCanvasColorToolButton()
        configureColorToolButton()
        configureAspectRatioToolButton()
        configureCalorieFoodToolButton()
        configureDeleteToolButton()
        configureAddToolButtons()
        configureCollageToolButton()
        configureCollageStyleToolButton()
        configureLivePhotoToolButton()
        aspectRatioToolButton.showsMenuAsPrimaryAction = true
        calorieFoodToolButton.showsMenuAsPrimaryAction = true
        mapStyleToolButton.showsMenuAsPrimaryAction = true
        configureMapStyleButton()

        toolBarScrollView.backgroundColor = .clear
        toolBarScrollView.showsHorizontalScrollIndicator = false
        toolBarScrollView.alwaysBounceHorizontal = false
        toolBarScrollView.contentInsetAdjustmentBehavior = .never
        toolBarScrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        toolBarScrollView.clipsToBounds = true

        bottomControlsView.contentView.addSubview(toolBarScrollView)
        toolBarScrollView.addSubview(toolBarView)

        toolBarScrollView.snp.makeConstraints { make in
            make.top.equalTo(photoCollectionView.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(52)
            make.bottom.equalTo(bottomControlsView.safeAreaLayoutGuide.snp.bottom).inset(8)
        }

        toolBarView.snp.makeConstraints { make in
            make.top.bottom.equalTo(toolBarScrollView.contentLayoutGuide)
            make.leading.trailing.equalTo(toolBarScrollView.contentLayoutGuide)
            make.height.equalTo(toolBarScrollView.frameLayoutGuide)
            toolsContainerWidthConstraint = make.width.equalTo(RouteShareToolBarView.preferredWidth(for: 2)).constraint
        }
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

    private func updateNavigationBackgroundColors() {
        navigationBackgroundView.effect = nil
        navigationBackgroundView.contentView.backgroundColor = .clear
        navigationBackgroundView.layer.mask = nil
    }

    private func registerTraitChangeHandler() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (viewController: Self, _) in
            viewController.updateNavigationBackgroundColors()
            viewController.updateInterfaceAppearanceColors()
            viewController.updateLocalizedText()
            viewController.setNeedsStatusBarAppearanceUpdate()
        }
    }

    private func updateInterfaceAppearanceColors() {
        view.backgroundColor = AppColors.sharePageBackground
        scrollView.backgroundColor = AppColors.sharePageBackground
        contentView.backgroundColor = AppColors.sharePageBackground
        bottomControlsView.effect = UIBlurEffect(style: .systemThinMaterial)
        bottomControlsView.contentView.backgroundColor = AppColors.sharePageBackground.withAlphaComponent(0.82)
        toolBarView.backgroundColor = AppColors.toolbarBackground
        resetBarButtonItem.tintColor = AppColors.solidForeground
        applySelectedCanvasColor()
        previewPlaceholderView.backgroundColor = AppColors.placeholderBackground
        previewPlaceholderIconView.tintColor = AppColors.foreground(alpha: 0.22)
    }

    @objc private func handleLanguageDidChange() {
        updateLocalizedText()
        configureCanvasColorToolButton()
        configureColorToolButton()
        configureAspectRatioToolButton()
        configureCalorieFoodToolButton()
        configureMapStyleButton()
    }

    private func updateLocalizedText() {
        title = AppLocalization.text(.share)
        metricsModuleView.updateLocalizedText(for: workout)
        configureCanvasColorToolButton()
        configureColorToolButton()
        configureAspectRatioToolButton()
        configureCalorieFoodToolButton()
        configureDeleteToolButton()
        configureAddToolButtons()
        configureCollageToolButton()
        configureCollageStyleToolButton()
        configureLivePhotoToolButton()
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
            previewContainerView,
            bottomControlsView
        ]
    }

    private func configureCanvasColorToolButton() {
        canvasColorToolButton.configuration = toolButtonConfiguration(
            title: AppLocalization.text(.canvas),
            imageName: traitCollection.userInterfaceStyle == .dark ? "light.panel.fill" : "light.panel"
        )
        canvasColorToolButton.isEnabled = true
        canvasColorToolButton.alpha = 1
        canvasColorToolButton.showsMenuAsPrimaryAction = true
        let colorActions = canvasColorOptions.map { option in
            UIAction(
                title: AppLocalization.text(option.nameKey),
                image: colorSwatchImage(option.color),
                state: colorsMatch(selectedCanvasColor, option.color) ? .on : .off
            ) { [weak self] _ in
                self?.selectedCanvasColor = option.color
            }
        }
        let customAction = UIAction(
            title: AppLocalization.text(.colorCustom),
            image: UIImage(systemName: "eyedropper")
        ) { [weak self] _ in
            self?.presentCanvasColorPicker()
        }
        canvasColorToolButton.menu = UIMenu(children: colorActions + [customAction])
    }

    private func applySelectedCanvasColor() {
        previewView.backgroundColor = selectedCanvasColor
        collageView.setCanvasColor(selectedCanvasColor)
    }

    private func presentCanvasColorPicker() {
        presentColorPicker(
            initialColor: selectedCanvasColor
        ) { [weak self] color in
            self?.selectedCanvasColor = color
        }
    }

    private func presentModuleColorPicker() {
        guard let selectedPreviewModule else {
            return
        }

        presentColorPicker(
            initialColor: colorForModule(selectedPreviewModule)
        ) { [weak self] color in
            self?.applyCustomColor(color, to: selectedPreviewModule)
        }
    }

    private func presentColorPicker(
        initialColor: UIColor,
        colorChanged: @escaping (UIColor) -> Void
    ) {
        let colorPickerViewController = RouteShareColorPickerViewController(
            initialColor: initialColor,
            onColorChanged: colorChanged
        )
        colorPickerViewController.modalPresentationStyle = .overFullScreen
        colorPickerViewController.modalTransitionStyle = .coverVertical
        present(colorPickerViewController, animated: true)
    }

    private func colorsMatch(_ lhs: UIColor, _ rhs: UIColor) -> Bool {
        let lhsColor = lhs.resolvedColor(with: traitCollection)
        let rhsColor = rhs.resolvedColor(with: traitCollection)
        var lhsRed: CGFloat = 0
        var lhsGreen: CGFloat = 0
        var lhsBlue: CGFloat = 0
        var lhsAlpha: CGFloat = 0
        var rhsRed: CGFloat = 0
        var rhsGreen: CGFloat = 0
        var rhsBlue: CGFloat = 0
        var rhsAlpha: CGFloat = 0
        guard lhsColor.getRed(&lhsRed, green: &lhsGreen, blue: &lhsBlue, alpha: &lhsAlpha),
              rhsColor.getRed(&rhsRed, green: &rhsGreen, blue: &rhsBlue, alpha: &rhsAlpha) else {
            return lhsColor.isEqual(rhsColor)
        }

        return abs(lhsRed - rhsRed) < 0.01
            && abs(lhsGreen - rhsGreen) < 0.01
            && abs(lhsBlue - rhsBlue) < 0.01
            && abs(lhsAlpha - rhsAlpha) < 0.01
    }

    private func configureColorToolButton() {
        let hasSelection = selectedPreviewModule != nil
        colorToolButton.configuration = toolButtonConfiguration(
            title: AppLocalization.text(.color),
            imageName: "paintpalette"
        )
        colorToolButton.isEnabled = hasSelection
        colorToolButton.alpha = 1
        colorToolButton.showsMenuAsPrimaryAction = true
        let colorActions = colorOptions.enumerated().map { index, color in
            UIAction(
                title: colorName(for: index),
                image: colorSwatchImage(color),
                attributes: hasSelection ? [] : [.disabled],
                state: selectedColorIndexForCurrentModule() == index ? .on : .off
            ) { [weak self] _ in
                self?.applyColor(at: index)
            }
        }
        let paletteAction = UIAction(
            title: AppLocalization.text(.colorCustom),
            image: UIImage(systemName: "eyedropper"),
            attributes: hasSelection ? [] : [.disabled],
            state: hasCustomColorForCurrentModule() ? .on : .off
        ) { [weak self] _ in
            self?.presentModuleColorPicker()
        }
        colorToolButton.menu = UIMenu(children: colorActions + [paletteAction])
    }

    private func configureCalorieFoodToolButton() {
        let hasMetricsSelection = selectedPreviewModule == .metrics && !metricsModuleView.isHidden
        let hasCalories = workout.displayEnergyBurnedKilocalories.map {
            $0.isFinite && $0 > 0
        } ?? false
        var configuration = toolButtonConfiguration(
            title: AppLocalization.text(.calories),
            imageName: "flame"
        )
        if metricsModuleView.calorieFoodOption != nil {
            configuration.baseForegroundColor = AppColors.movinnGreen
        }

        calorieFoodToolButton.configuration = configuration
        calorieFoodToolButton.isEnabled = hasMetricsSelection && hasCalories
        calorieFoodToolButton.alpha = hasMetricsSelection && hasCalories ? 1 : 0.38
        calorieFoodToolButton.showsMenuAsPrimaryAction = true

        let disabledAttributes: UIMenuElement.Attributes = hasMetricsSelection && hasCalories ? [] : [.disabled]
        let hideAction = UIAction(
            title: AppLocalization.text(.disable),
            attributes: disabledAttributes,
            state: metricsModuleView.calorieFoodOption == nil ? .on : .off
        ) { [weak self] _ in
            self?.applyCalorieFoodOption(nil)
        }
        let foodActions = RouteShareCalorieFoodOption.allCases.map { option in
            UIAction(
                title: option.menuTitle,
                attributes: disabledAttributes,
                state: metricsModuleView.calorieFoodOption == option ? .on : .off
            ) { [weak self] _ in
                self?.applyCalorieFoodOption(option)
            }
        }

        calorieFoodToolButton.menu = UIMenu(children: [hideAction] + foodActions)
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

    private func configureCollageToolButton() {
        var configuration = toolButtonConfiguration(
            title: AppLocalization.text(.collage),
            imageName: "square.grid.2x2"
        )
        if case .collage = previewBackground {
            configuration.baseForegroundColor = AppColors.movinnGreen
        }
        collageToolButton.configuration = configuration
        collageToolButton.removeTarget(nil, action: nil, for: .touchUpInside)
        collageToolButton.addTarget(self, action: #selector(toggleCollageBackground), for: .touchUpInside)
    }

    private func configureCollageStyleToolButton() {
        collageStyleToolButton.configuration = toolButtonConfiguration(
            title: AppLocalization.text(.collageStyle),
            imageName: "rectangle.split.3x1"
        )
        collageStyleToolButton.removeTarget(nil, action: nil, for: .touchUpInside)
        collageStyleToolButton.addTarget(self, action: #selector(cycleCollageLayout), for: .touchUpInside)
    }

    private func configureLivePhotoToolButton() {
        var configuration = toolButtonConfiguration(
            title: "Live",
            imageName: "livephoto"
        )
        configuration.baseForegroundColor = AppColors.movinnGreen
        livePhotoToolButton.configuration = configuration
        livePhotoToolButton.removeTarget(nil, action: nil, for: .touchUpInside)
        livePhotoToolButton.addTarget(self, action: #selector(playCollageLivePhoto), for: .touchUpInside)
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
        configuration.baseForegroundColor = AppColors.solidForeground
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
            guard let self,
                  !self.hasPreparedForPermanentDismissal else {
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
        collageView.setCropSelectionChromeHidden(isExportChromeHidden)
        collageView.setDividerInteractionEnabled(selectedPreviewModule == nil && !isBackgroundAdjustmentEnabled)
        applySelectionStyle(to: routeModuleView, isSelected: selectedPreviewModule == .route)
        applySelectionStyle(to: metricsModuleView, isSelected: selectedPreviewModule == .metrics)
        configureColorToolButton()
        configureCalorieFoodToolButton()
        updateToolBarVisibility()
    }

    private func clearCollageCropSelectionForElementEditing() {
        let hadCropSelection = collageView.hasActiveCropSelection
        collageView.clearCropSelection()
        if hadCropSelection {
            updateVisiblePhotoBrowserCellStates()
        }
    }

    private func applySelectionStyle(to view: UIView, isSelected: Bool) {
        let isRouteView = view === routeModuleView
        let borderLayer = isRouteView ? routeSelectionBorderLayer : metricsSelectionBorderLayer
        let deleteButton = isRouteView ? routeDeleteCornerButton : metricsDeleteCornerButton
        let shouldShowChrome = isSelected && !isExportChromeHidden
        borderLayer.isHidden = !shouldShowChrome
        deleteButton.isHidden = !shouldShowChrome
        if shouldShowChrome {
            borderLayer.removeFromSuperlayer()
            previewView.layer.addSublayer(borderLayer)
            updateSelectionChrome(borderLayer: borderLayer, deleteButton: deleteButton, for: view)
            keepBrandPillOnTop()
            previewView.bringSubviewToFront(deleteButton)
        } else {
            borderLayer.removeFromSuperlayer()
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
        if case .collage = previewBackground {
        } else {
            cancelCollageLivePhotoRequest()
            collageView.stopLivePhotoPlayback()
        }

        switch previewBackground {
        case .map:
            representedPreviewPhotoID = nil
            previewImageView.image = nil
            previewImageView.isHidden = true
            previewLivePhotoView.isHidden = true
            collageView.isHidden = true
            collageView.clear()
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
                collageView.isHidden = true
                previewPlaceholderView.isHidden = false
                mapView.isHidden = true
                return
            }

            let item = photoItems[selectedPhotoIndex]
            representedPreviewPhotoID = item.id
            mapView.isHidden = true
            collageView.isHidden = true
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
        case .collage:
            guard let collageLayout = activeCollageLayout() else {
                representedPreviewPhotoID = nil
                previewImageView.image = nil
                previewImageView.isHidden = true
                previewLivePhotoView.isHidden = true
                collageView.isHidden = true
                previewPlaceholderView.isHidden = false
                mapView.isHidden = true
                return
            }

            representedPreviewPhotoID = collageRepresentationID()
            previewImageView.image = nil
            previewImageView.isHidden = true
            previewLivePhotoView.isHidden = true
            previewPlaceholderView.isHidden = true
            mapView.isHidden = true
            collageView.isHidden = false
            collageView.configure(items: selectedCollageItems(), layout: collageLayout)
            updatePreviewModuleVisibility()
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
                  !self.hasPreparedForPermanentDismissal,
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
                  !self.hasPreparedForPermanentDismissal,
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

    private func requestCollageLivePhotoPlayback(
        for sources: [(tileIndex: Int, item: SharePhotoItem, asset: PHAsset)]
    ) {
        cancelCollageLivePhotoRequest()
        guard !sources.isEmpty else {
            return
        }

        let playbackToken = UUID()
        collageLivePhotoPlaybackToken = playbackToken
        let scale = max(UIScreen.main.scale, 2)
        let targetWidth = max(previewView.bounds.width, 720) * scale
        let targetHeight = max(previewView.bounds.height, 900) * scale
        var pendingCount = sources.count
        var playbacks: [Int: RouteShareCollageLivePhotoPlayback] = [:]

        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        let completePlayback: (
            (tileIndex: Int, item: SharePhotoItem, asset: PHAsset),
            PHLivePhoto?,
            CollageLivePhotoPreviewInfo?
        ) -> Void = { [weak self] source, livePhoto, previewInfo in
            guard let self,
                  !self.hasPreparedForPermanentDismissal,
                  self.collageLivePhotoPlaybackToken == playbackToken,
                  case .collage = self.previewBackground else {
                return
            }

            let collageItems = self.selectedCollageItems()
            if let livePhoto,
               collageItems.indices.contains(source.tileIndex),
               collageItems[source.tileIndex].id == source.item.id {
                playbacks[source.tileIndex] = RouteShareCollageLivePhotoPlayback(
                    livePhoto: livePhoto,
                    tileIndex: source.tileIndex,
                    representedID: source.item.id,
                    duration: previewInfo?.duration ?? Self.fallbackLivePhotoPreviewDuration(for: source.asset),
                    freezeImage: previewInfo?.freezeImage
                )
            }

            pendingCount -= 1
            guard pendingCount == 0 else {
                return
            }

            let orderedPlaybacks = sources.compactMap { playbacks[$0.tileIndex] }
            guard !orderedPlaybacks.isEmpty else {
                return
            }
            let playbackDuration = orderedPlaybacks.map(\.duration).max() ?? Self.defaultLivePhotoPreviewDuration
            self.collageView.playLivePhotos(orderedPlaybacks, playbackDuration: playbackDuration)
        }

        sources.forEach { source in
            let requestID = PHImageManager.default().requestLivePhoto(
                for: source.asset,
                targetSize: CGSize(width: targetWidth, height: targetHeight),
                contentMode: .aspectFill,
                options: options
            ) { [weak self] livePhoto, info in
                guard let self,
                      !self.hasPreparedForPermanentDismissal,
                      collageLivePhotoPlaybackToken == playbackToken else {
                    return
                }

                if (info?[PHImageCancelledKey] as? Bool) == true
                    || (info?[PHImageResultIsDegradedKey] as? Bool) == true {
                    return
                }

                guard let livePhoto else {
                    DispatchQueue.main.async {
                        completePlayback(source, nil, nil)
                    }
                    return
                }

                let task = Task { [weak self] in
                    let previewInfo = await Self.previewInfo(forLivePhotoAsset: source.asset)
                    await MainActor.run {
                        guard let self,
                              !self.hasPreparedForPermanentDismissal,
                              self.collageLivePhotoPlaybackToken == playbackToken else {
                            return
                        }
                        completePlayback(source, livePhoto, previewInfo)
                    }
                }
                collageLivePhotoFrameTasks.append(task)
            }
            collageLivePhotoRequestIDs.append(requestID)
        }
    }

    private func cancelCollageLivePhotoRequest() {
        collageLivePhotoPlaybackToken = UUID()
        collageLivePhotoRequestIDs.forEach { requestID in
            PHImageManager.default().cancelImageRequest(requestID)
        }
        collageLivePhotoRequestIDs.removeAll()
        collageLivePhotoFrameTasks.forEach { $0.cancel() }
        collageLivePhotoFrameTasks.removeAll()
    }

    nonisolated private static var defaultLivePhotoPreviewDuration: TimeInterval {
        3
    }

    nonisolated private static func fallbackLivePhotoPreviewDuration(for asset: PHAsset) -> TimeInterval {
        asset.duration > 0.2 ? asset.duration : defaultLivePhotoPreviewDuration
    }

    nonisolated private static func previewInfo(forLivePhotoAsset asset: PHAsset) async -> CollageLivePhotoPreviewInfo {
        guard let pairedVideoResource = pairedVideoResource(for: asset) else {
            return CollageLivePhotoPreviewInfo(
                freezeImage: nil,
                duration: fallbackLivePhotoPreviewDuration(for: asset)
            )
        }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovinnLivePreview-\(UUID().uuidString)", isDirectory: true)
        let videoURL = directoryURL.appendingPathComponent("source-live-photo.mov")

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: directoryURL)
            }

            try await writePairedVideoResource(pairedVideoResource, to: videoURL)
            let videoAsset = AVAsset(url: videoURL)
            let duration = try await videoAsset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            let resolvedDuration = durationSeconds.isFinite && durationSeconds > 0.2
                ? durationSeconds
                : fallbackLivePhotoPreviewDuration(for: asset)
            let generator = AVAssetImageGenerator(asset: videoAsset)
            generator.appliesPreferredTrackTransform = true
            let frameTimeSeconds = max(resolvedDuration - 0.05, 0)
            let frameTime = CMTime(seconds: frameTimeSeconds, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: frameTime, actualTime: nil)
            return CollageLivePhotoPreviewInfo(
                freezeImage: UIImage(cgImage: cgImage),
                duration: resolvedDuration
            )
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            return CollageLivePhotoPreviewInfo(
                freezeImage: nil,
                duration: fallbackLivePhotoPreviewDuration(for: asset)
            )
        }
    }

    nonisolated private static func pairedVideoResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first(where: { $0.type == .fullSizePairedVideo })
            ?? resources.first(where: { $0.type == .pairedVideo })
    }

    nonisolated private static func writePairedVideoResource(
        _ pairedVideoResource: PHAssetResource,
        to sourceVideoURL: URL
    ) async throws {
        try? FileManager.default.removeItem(at: sourceVideoURL)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(
                for: pairedVideoResource,
                toFile: sourceVideoURL,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
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

    private func selectedCollageItems() -> [SharePhotoItem] {
        collagePhotoIndices.compactMap { index in
            photoItems.indices.contains(index) ? photoItems[index] : nil
        }
    }

    private func selectedCollageLivePhotoSources() -> [(tileIndex: Int, item: SharePhotoItem, asset: PHAsset)] {
        var sources: [(tileIndex: Int, item: SharePhotoItem, asset: PHAsset)] = []
        for (tileIndex, item) in selectedCollageItems().enumerated() {
            guard item.isLivePhoto,
                  let asset = item.asset else {
                continue
            }
            sources.append((tileIndex: tileIndex, item: item, asset: asset))
        }
        return sources
    }

    private func livePhotoCount(inCollagePhotoIndices indices: [Int]) -> Int {
        indices.reduce(0) { count, index in
            guard photoItems.indices.contains(index),
                  photoItems[index].isLivePhoto else {
                return count
            }
            return count + 1
        }
    }

    private func requiresMultiLivePhotoExportUnlock(forCollagePhotoIndices indices: [Int]) -> Bool {
        livePhotoCount(inCollagePhotoIndices: indices) > 1
            && !ProSubscriptionManager.shared.isProUser
    }

    private func requiresMultiLivePhotoExportUnlock(for source: LivePhotoExportSource) -> Bool {
        switch source {
        case .photo:
            return false
        case .collage(let sources):
            return sources.count > 1 && !ProSubscriptionManager.shared.isProUser
        }
    }

    private func requestMultiLivePhotoExportAccess(onUnlocked: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await ProSubscriptionManager.shared.ensureAccessResolved()
            guard ProSubscriptionManager.shared.isProUser else {
                presentProPaywall(onPurchaseCompleted: onUnlocked)
                return
            }

            onUnlocked()
        }
    }

    private func collageRepresentationID() -> String {
        let itemIDs = selectedCollageItems().map(\.id).joined(separator: "|")
        let layoutID = selectedCollageLayout.map { "\($0.kind.rawValue)-\($0.dividers)" } ?? "none"
        return "collage-\(collageSlotCount())-\(itemIDs)-\(layoutID)"
    }

    private func activeCollageLayout() -> RouteShareCollageLayout? {
        let photoCount = collageSlotCount()
        if let selectedCollageLayout, selectedCollageLayout.matches(photoCount: photoCount) {
            return selectedCollageLayout
        }

        selectedCollageLayout = collageLayoutForCurrentStyle(photoCount: photoCount)
        return selectedCollageLayout
    }

    private func collageSlotCount() -> Int {
        min(max(collagePhotoIndices.count, 2), 4)
    }

    private func collageLayoutForCurrentStyle(photoCount: Int) -> RouteShareCollageLayout? {
        let library = RouteShareCollageLayout.library(for: photoCount)
        guard !library.isEmpty else {
            return nil
        }

        return library[selectedCollageStyleIndex % library.count]
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

    @objc private func enterCollageBackground() {
        guard photoItems.count >= 2 else {
            return
        }

        selectedPhotoIndex = nil
        collagePhotoIndices = defaultCollagePhotoIndices()
        selectedCollageStyleIndex = 0
        selectedCollageLayout = collageLayoutForCurrentStyle(photoCount: collageSlotCount())
        previewBackground = .collage
        applyDefaultColorsForCurrentBackground()
        representedPreviewPhotoID = nil
        isBackgroundAdjustmentEnabled = false
        photoCollectionView.reloadData()
        updatePreviewCanvasAspectRatio(animated: true, resetsModuleLayout: true)
        updatePreviewPhoto()
        configureCollageToolButton()
        configureCollageStyleToolButton()
        updateToolBarVisibility()
    }

    @objc private func toggleCollageBackground() {
        if case .collage = previewBackground {
            selectDefaultPhotoBackground()
            return
        }

        enterCollageBackground()
    }

    private func selectDefaultPhotoBackground() {
        guard !photoItems.isEmpty else {
            return
        }

        collageView.clearCropSelection()
        cancelCollageLivePhotoRequest()
        collageView.stopLivePhotoPlayback()
        selectPhoto(at: 0)
    }

    private func defaultCollagePhotoIndices() -> [Int] {
        let targetCount = min(2, photoItems.count)
        if ProSubscriptionManager.shared.isProUser {
            return Array(photoItems.indices.prefix(targetCount))
        }

        var indices: [Int] = []
        var hasLivePhoto = false
        for index in photoItems.indices {
            let isLivePhoto = photoItems[index].isLivePhoto
            if isLivePhoto && hasLivePhoto {
                continue
            }

            indices.append(index)
            hasLivePhoto = hasLivePhoto || isLivePhoto
            if indices.count == targetCount {
                break
            }
        }
        return indices
    }

    private func toggleCollagePhoto(at index: Int) {
        guard photoItems.indices.contains(index) else {
            return
        }

        let previousSlotCount = collageSlotCount()
        let proposedSelection = proposedCollageSelection(togglingPhotoAt: index)
        if requiresMultiLivePhotoExportUnlock(forCollagePhotoIndices: proposedSelection.indices) {
            requestMultiLivePhotoExportAccess { [weak self] in
                self?.toggleCollagePhoto(at: index)
            }
            return
        }

        collagePhotoIndices = proposedSelection.indices
        if proposedSelection.clearsCropSelection {
            collageView.clearCropSelection()
        }
        if previousSlotCount != collageSlotCount() {
            selectedCollageLayout = collageLayoutForCurrentStyle(photoCount: collageSlotCount())
        }

        representedPreviewPhotoID = nil
        updateVisiblePhotoBrowserCellStates()
        updatePreviewPhoto()
        configureCollageStyleToolButton()
        updateToolBarVisibility()
    }

    private func proposedCollageSelection(
        togglingPhotoAt index: Int
    ) -> (indices: [Int], clearsCropSelection: Bool) {
        var proposedIndices = collagePhotoIndices
        if let activeCropSelectionIndex = collageView.activeCropSelectionIndex,
           proposedIndices.indices.contains(activeCropSelectionIndex) {
            proposedIndices = replacingCollagePhotoIndices(
                proposedIndices,
                at: activeCropSelectionIndex,
                with: index
            )
            return (proposedIndices, true)
        }

        if let existingIndex = proposedIndices.firstIndex(of: index) {
            proposedIndices.remove(at: existingIndex)
        } else if proposedIndices.count < 4 {
            proposedIndices.append(index)
        } else {
            proposedIndices.removeFirst()
            proposedIndices.append(index)
        }

        return (proposedIndices, false)
    }

    private func replacingCollagePhotoIndices(
        _ indices: [Int],
        at slotIndex: Int,
        with photoIndex: Int
    ) -> [Int] {
        guard indices.indices.contains(slotIndex),
              photoItems.indices.contains(photoIndex) else {
            return indices
        }

        var proposedIndices = indices
        if let duplicateIndex = proposedIndices.firstIndex(of: photoIndex),
           duplicateIndex != slotIndex {
            proposedIndices.remove(at: duplicateIndex)
            let adjustedSlotIndex = duplicateIndex < slotIndex ? slotIndex - 1 : slotIndex
            if proposedIndices.indices.contains(adjustedSlotIndex) {
                proposedIndices[adjustedSlotIndex] = photoIndex
            }
        } else {
            proposedIndices[slotIndex] = photoIndex
        }
        return proposedIndices
    }

    @objc private func cycleCollageLayout() {
        guard case .collage = previewBackground else {
            enterCollageBackground()
            return
        }

        let library = RouteShareCollageLayout.library(for: collageSlotCount())
        guard !library.isEmpty else {
            return
        }

        selectedCollageStyleIndex = (selectedCollageStyleIndex + 1) % library.count
        selectedCollageLayout = library[selectedCollageStyleIndex]
        representedPreviewPhotoID = nil
        updatePreviewPhoto()
        configureCollageStyleToolButton()
    }

    private func selectPhoto(at index: Int) {
        guard photoItems.indices.contains(index) else {
            return
        }

        let wasPhotoBackground = isPhotoAdjustmentHintBackground
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
        if !wasPhotoBackground {
            showBackgroundAdjustmentToast(for: .photoBackgroundAdjustmentHint)
        }

    }

    private func replayPreviewLivePhoto() {
        guard previewLivePhotoView.livePhoto != nil else {
            return
        }

        previewLivePhotoView.stopPlayback()
        previewLivePhotoView.startPlayback(with: .full)
    }

    @objc private func playCollageLivePhoto() {
        guard case .collage = previewBackground else {
            return
        }

        let livePhotoSources = selectedCollageLivePhotoSources()
        guard !livePhotoSources.isEmpty else {
            return
        }

        requestCollageLivePhotoPlayback(for: livePhotoSources)
    }

    private func selectMapBackground(usesDefaultMapAspectRatio: Bool = true) {
        let wasMapBackground = isMapAdjustmentHintBackground
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
        if !wasMapBackground {
            showBackgroundAdjustmentToast(for: .mapBackgroundAdjustmentHint)
        }
    }

    private func toggleMapBackground() {
        if case .map = previewBackground {
            selectDefaultPhotoBackground()
            return
        }

        selectMapBackground()
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
        selectedRouteCustomColor = nil
        selectedMetricsCustomColor = nil
        switch previewBackground {
        case .map:
            selectedRouteColorIndex = mapPreviewContentColorIndex
            selectedMetricsColorIndex = mapPreviewContentColorIndex
        case .photo, .collage:
            selectedRouteColorIndex = 0
            selectedMetricsColorIndex = 0
        }
        updateMapPreviewContentColors()
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
        updateVisiblePhotoBrowserCellStates()
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
                return 0.64
            }
            if heightMultiplier < 0.92 {
                return 0.84
            }
            return 1.16
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
        clearCollageCropSelectionForElementEditing()
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
        clearCollageCropSelectionForElementEditing()
        isBackgroundAdjustmentEnabled = false
        selectedPreviewModule = .metrics
        previewView.bringSubviewToFront(metricsModuleView)
        keepBrandPillOnTop()
        updatePreviewSelection()
    }

    private func selectedColorIndexForCurrentModule() -> Int? {
        switch selectedPreviewModule {
        case .route:
            return selectedRouteCustomColor == nil ? selectedRouteColorIndex : nil
        case .metrics:
            return selectedMetricsCustomColor == nil ? selectedMetricsColorIndex : nil
        case nil:
            return nil
        }
    }

    private func hasCustomColorForCurrentModule() -> Bool {
        switch selectedPreviewModule {
        case .route:
            return selectedRouteCustomColor != nil
        case .metrics:
            return selectedMetricsCustomColor != nil
        case nil:
            return false
        }
    }

    private func colorForModule(_ module: PreviewModule) -> UIColor {
        switch module {
        case .route:
            return routeModuleColor
        case .metrics:
            return metricsModuleColor
        }
    }

    private func applyColor(at index: Int) {
        switch selectedPreviewModule {
        case .route:
            selectedRouteCustomColor = nil
            selectedRouteColorIndex = index
        case .metrics:
            selectedMetricsCustomColor = nil
            selectedMetricsColorIndex = index
        case nil:
            return
        }
        configureColorToolButton()
    }

    private func applyCustomColor(_ color: UIColor, to module: PreviewModule) {
        switch module {
        case .route:
            selectedRouteCustomColor = color
        case .metrics:
            selectedMetricsCustomColor = color
        }
        configureColorToolButton()
        updateSelectionChromeFrames()
    }

    private func applyCalorieFoodOption(_ option: RouteShareCalorieFoodOption?) {
        guard selectedPreviewModule == .metrics else {
            return
        }

        metricsModuleView.setCalorieFoodOption(option)
        configureCalorieFoodToolButton()
        updateSelectionChromeFrames()
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
        clearCollageCropSelectionForElementEditing()
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
        clearCollageCropSelectionForElementEditing()
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

        clearCollageCropSelectionForElementEditing()
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

        clearCollageCropSelectionForElementEditing()
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

        clearCollageCropSelectionForElementEditing()
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
        case .collage:
            break
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
        case .collage:
            break
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
        case .collage:
            break
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
              selectedPreviewModule != nil
                || isBackgroundAdjustmentEnabled
                || collageView.hasActiveCropSelection else {
            return
        }

        clearPreviewSelections()
    }

    @objc private func handlePreviewContainerTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        let location = recognizer.location(in: previewContainerView)
        guard !previewView.frame.contains(location) else {
            return
        }

        clearPreviewSelections()
    }

    private func clearPreviewSelections() {
        let hadCropSelection = collageView.hasActiveCropSelection
        collageView.clearCropSelection()
        guard selectedPreviewModule != nil || isBackgroundAdjustmentEnabled || hadCropSelection else {
            return
        }

        isBackgroundAdjustmentEnabled = false
        selectedPreviewModule = nil
        updatePreviewSelection()
    }

    private func clearElementSelectionForPreviewInteraction() {
        guard selectedPreviewModule != nil || isBackgroundAdjustmentEnabled else {
            return
        }

        selectedPreviewModule = nil
        isBackgroundAdjustmentEnabled = false
        updatePreviewSelection()
        updateVisiblePhotoBrowserCellStates()
    }

    @objc private func handlePreviewBackgroundDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }
        guard case .collage = previewBackground else {
            selectedPreviewModule = nil
            isBackgroundAdjustmentEnabled = true
            updatePreviewSelection()
            return
        }
        selectedPreviewModule = nil
        isBackgroundAdjustmentEnabled = false
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
        } else if case .collage = previewBackground {
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
        metricsModuleView.applyColor(effectiveMetricsColor)
    }

    private func applyMapStyle(_ style: AppMapDisplayStyle) {
        selectedMapStyle = style
        if case .map = previewBackground {
            isBackgroundAdjustmentEnabled = false
            selectedPreviewModule = nil
            updatePreviewSelection()
            applyDefaultColorsForCurrentBackground()
        } else {
            selectMapBackground(usesDefaultMapAspectRatio: false)
        }
        AppMapStyle.apply(style, to: mapView)
        AppMapStyle.setToneOverlay(mapToneOverlay, visible: style == .appDefault, on: mapView)
        updateMapPreviewContentColors()
        configureMapStyleButton()
    }

    private func updateMapPreviewContentColors() {
        routePathView.setStrokeColor(effectiveRouteColor)
        applyMetricsColor()
        refreshMapRouteOverlayColor()
        configureColorToolButton()
    }

    private func refreshMapRouteOverlayColor() {
        guard let routePolyline,
              let renderer = mapView.renderer(for: routePolyline) as? MKPolylineRenderer else {
            return
        }

        renderer.strokeColor = effectiveRouteColor
        renderer.setNeedsDisplay()
    }

    private func applyCanvasAspectRatio(_ aspectRatio: CanvasAspectRatio) {
        selectedCanvasAspectRatio = aspectRatio
        updatePreviewCanvasAspectRatio(animated: true, resetsModuleLayout: true)
    }

    private var isMapAdjustmentHintBackground: Bool {
        if case .map = previewBackground {
            return true
        }
        return false
    }

    private var isPhotoAdjustmentHintBackground: Bool {
        if case .photo = previewBackground {
            return true
        }
        return false
    }

    private func showInitialBackgroundAdjustmentToastIfNeeded() {
        guard !hasShownInitialBackgroundAdjustmentToast,
              let textKey = currentBackgroundAdjustmentToastKey else {
            return
        }

        hasShownInitialBackgroundAdjustmentToast = true
        showBackgroundAdjustmentToast(for: textKey)
    }

    private var currentBackgroundAdjustmentToastKey: AppTextKey? {
        switch previewBackground {
        case .map:
            return .mapBackgroundAdjustmentHint
        case .photo:
            return .photoBackgroundAdjustmentHint
        case .collage:
            return nil
        }
    }

    private func showBackgroundAdjustmentToast(for textKey: AppTextKey) {
        Toast.show(AppLocalization.text(textKey), in: view)
    }

    private func updateToolBarVisibility() {
        let isMapBackground: Bool
        if case .map = previewBackground {
            isMapBackground = true
        } else {
            isMapBackground = false
        }
        let isCollageBackground: Bool
        if case .collage = previewBackground {
            isCollageBackground = true
        } else {
            isCollageBackground = false
        }

        canvasColorToolButton.isHidden = false
        colorToolButton.isHidden = selectedPreviewModule == nil
        mapStyleToolButton.isHidden = !isMapBackground
        calorieFoodToolButton.isHidden = selectedPreviewModule != .metrics
        collageToolButton.isHidden = true
        collageStyleToolButton.isHidden = !isCollageBackground
        deleteToolButton.isHidden = true
        addRouteToolButton.isHidden = isMapBackground || isRouteModuleEnabled
        addMetricsToolButton.isHidden = isMetricsModuleEnabled
        livePhotoToolButton.isHidden = !(isCollageBackground && !selectedCollageLivePhotoSources().isEmpty)
        configureCollageToolButton()
        configureLivePhotoToolButton()

        let visibleButtonCount = [
            aspectRatioToolButton,
            canvasColorToolButton,
            colorToolButton,
            calorieFoodToolButton,
            mapStyleToolButton,
            collageToolButton,
            collageStyleToolButton,
            deleteToolButton,
            addRouteToolButton,
            addMetricsToolButton,
            livePhotoToolButton
        ].filter { !$0.isHidden }.count
        toolsContainerWidthConstraint?.update(offset: RouteShareToolBarView.preferredWidth(for: visibleButtonCount))
        toolBarScrollView.setContentOffset(
            CGPoint(x: -toolBarScrollView.adjustedContentInset.left, y: 0),
            animated: false
        )
        UIView.animate(withDuration: 0.18) {
            self.view.layoutIfNeeded()
        }
    }

    private func colorName(for index: Int) -> String {
        switch index {
        case 0:
            return AppLocalization.text(.colorWhite)
        case 1:
            return AppLocalization.text(.colorBlack)
        case 2:
            return "Movinn"
        case 3:
            return AppLocalization.text(.colorBlue)
        case 4:
            return AppLocalization.text(.colorOrange)
        case 5:
            return AppLocalization.text(.colorPink)
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
        if let livePhotoSource = selectedLivePhotoExportSource() {
            if requiresMultiLivePhotoExportUnlock(for: livePhotoSource) {
                requestMultiLivePhotoExportAccess { [weak self] in
                    self?.sharePreviewImage()
                }
                return
            }
            exportAndShareLivePhoto(source: livePhotoSource)
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

    private func selectedLivePhotoExportSource() -> LivePhotoExportSource? {
        switch previewBackground {
        case .photo(let index):
            guard photoItems.indices.contains(index),
                  case .routeMedia(let mediaItem) = photoItems[index],
                  mediaItem.isLivePhoto else {
                return nil
            }
            return .photo(mediaItem.asset)
        case .collage:
            let livePhotoSources = selectedCollageLivePhotoSources().map { source in
                CollageLivePhotoExportSource(asset: source.asset, tileIndex: source.tileIndex)
            }
            guard !livePhotoSources.isEmpty else {
                return nil
            }
            return .collage(livePhotoSources)
        case .map:
            return nil
        }
    }

    private func exportAndShareLivePhoto(source: LivePhotoExportSource) {
        selectedPreviewModule = nil
        updatePreviewSelection()
        showExportLoading(text: AppLocalization.text(.livePhotoSaving))
        view.layoutIfNeeded()
        let outputSize = RouteSharePreviewRenderer.outputPixelSize(for: previewView.bounds.size)
        let completion: (Result<RouteShareLivePhotoExport, Error>) -> Void = { [weak self] result in
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
                        showAlert(title: AppLocalization.text(.share), message: detailedErrorMessage(error))
                    }
                }
            case .failure(let error):
                hideExportLoading()
                showAlert(title: AppLocalization.text(.share), message: detailedErrorMessage(error))
            }
        }

        switch source {
        case .photo(let asset):
            let overlayImage = RouteSharePreviewRenderer.overlayImage(
                from: previewView,
                backgroundViews: [
                    mapContainerView,
                    previewImageView,
                    previewLivePhotoView,
                    collageView,
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
                backgroundTransform: currentBackgroundRenderTransform(outputSize: outputSize),
                canvasColor: selectedCanvasColor,
                includesAudio: true,
                completion: completion
            )
        case .collage(let sources):
            guard let source = sources.first else {
                completion(.failure(RouteShareLivePhotoExportError.missingResources))
                return
            }

            if sources.count == 1 {
                let overlayImage = collageLivePhotoOverlayImage(
                    hidingTilesAt: [source.tileIndex],
                    outputSize: outputSize
                )
                livePhotoExporter.export(
                    asset: source.asset,
                    overlayImage: overlayImage,
                    outputSize: outputSize,
                    backgroundTransform: collageLivePhotoBackgroundTransform(
                        asset: source.asset,
                        tileIndex: source.tileIndex,
                        outputSize: outputSize
                    ),
                    canvasColor: selectedCanvasColor,
                    includesAudio: true,
                    completion: completion
                )
                return
            }

            let hidingTileIndices = sources.map(\.tileIndex)
            let overlayImage = collageLivePhotoOverlayImage(
                hidingTilesAt: hidingTileIndices,
                outputSize: outputSize
            )
            let stillImage = livePhotoStillImage(outputSize: outputSize)
            let videoSources = sources.map { source in
                RouteShareLivePhotoVideoSource(
                    asset: source.asset,
                    backgroundTransform: collageLivePhotoBackgroundTransform(
                        asset: source.asset,
                        tileIndex: source.tileIndex,
                        outputSize: outputSize
                    ),
                    clippingPath: collageLivePhotoClippingPath(
                        tileIndex: source.tileIndex,
                        outputSize: outputSize
                    )
                )
            }
            livePhotoExporter.export(
                sources: videoSources,
                stillImage: stillImage,
                overlayImage: overlayImage,
                outputSize: outputSize,
                canvasColor: selectedCanvasColor,
                includesAudio: true,
                completion: completion
            )
        }
    }

    private func livePhotoStillImage(outputSize: CGSize) -> UIImage {
        let shouldHideCollagePlayback: Bool
        if case .collage = previewBackground {
            shouldHideCollagePlayback = true
        } else {
            shouldHideCollagePlayback = false
        }

        if shouldHideCollagePlayback {
            collageView.setLivePhotoPlaybackHiddenForRendering(true)
        }
        setSelectionChromeHidden(true)
        preparePreviewForExportCapture()
        defer {
            if shouldHideCollagePlayback {
                collageView.setLivePhotoPlaybackHiddenForRendering(false)
            }
            setSelectionChromeHidden(false)
            updatePreviewSelection()
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            previewView.drawHierarchy(
                in: CGRect(origin: .zero, size: outputSize),
                afterScreenUpdates: false
            )
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

    private func collageLivePhotoOverlayImage(
        hidingTilesAt tileIndices: [Int],
        outputSize: CGSize
    ) -> UIImage {
        let previewBackgroundColor = previewView.backgroundColor
        let collageBackgroundColor = collageView.backgroundColor
        let tileHiddenStates = tileIndices.map { tileIndex in
            (tileIndex, collageView.isTileHiddenForRendering(at: tileIndex))
        }
        let livePhotoWasHidden = collageView.isLivePhotoPlaybackHiddenForRendering

        collageView.backgroundColor = .clear
        previewView.backgroundColor = .clear
        setSelectionChromeHidden(true)
        preparePreviewForExportCapture()

        tileIndices.forEach { tileIndex in
            collageView.setTileHiddenForRendering(at: tileIndex, hidden: true)
        }
        collageView.setLivePhotoPlaybackHiddenForRendering(true)
        CATransaction.flush()
        defer {
            tileHiddenStates.forEach { tileIndex, wasHidden in
                collageView.setTileHiddenForRendering(at: tileIndex, hidden: wasHidden)
            }
            collageView.setLivePhotoPlaybackHiddenForRendering(livePhotoWasHidden)
            collageView.backgroundColor = collageBackgroundColor
            previewView.backgroundColor = previewBackgroundColor
            setSelectionChromeHidden(false)
            updatePreviewSelection()
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            previewView.drawHierarchy(
                in: CGRect(origin: .zero, size: outputSize),
                afterScreenUpdates: false
            )
        }
    }

    private func preparePreviewForExportCapture() {
        previewView.setNeedsLayout()
        previewView.layoutIfNeeded()
        previewView.layer.setNeedsDisplay()
        previewView.layer.displayIfNeeded()
        CATransaction.flush()
    }

    private func collageLivePhotoBackgroundTransform(
        asset: PHAsset,
        tileIndex: Int,
        outputSize: CGSize
    ) -> RouteShareBackgroundRenderTransform {
        guard previewView.bounds.width > 0,
              let renderInfo = collageView.renderInfoForTile(at: tileIndex) else {
            return RouteShareBackgroundRenderTransform(scale: 1, translation: .zero, rotation: 0)
        }

        let outputScale = outputSize.width / previewView.bounds.width
        let tileFrameInPreview = collageView.convert(renderInfo.tileFrame, to: previewView)
        let tileFrame = CGRect(
            x: tileFrameInPreview.minX * outputScale,
            y: tileFrameInPreview.minY * outputScale,
            width: tileFrameInPreview.width * outputScale,
            height: tileFrameInPreview.height * outputScale
        )
        let sourceSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        let tileBaseSize = aspectFillSize(for: sourceSize, in: tileFrame.size)
        let outputBaseSize = aspectFillSize(for: sourceSize, in: outputSize)
        guard outputBaseSize.width > 0,
              outputBaseSize.height > 0 else {
            return RouteShareBackgroundRenderTransform(scale: 1, translation: .zero, rotation: 0)
        }

        let liveScale = (tileBaseSize.width * renderInfo.cropScale) / outputBaseSize.width
        let liveCenter = CGPoint(
            x: tileFrame.midX + renderInfo.cropTranslation.x * outputScale,
            y: tileFrame.midY + renderInfo.cropTranslation.y * outputScale
        )
        return RouteShareBackgroundRenderTransform(
            scale: liveScale,
            translation: CGPoint(
                x: liveCenter.x - outputSize.width / 2,
                y: liveCenter.y - outputSize.height / 2
            ),
            rotation: renderInfo.cropRotation
        )
    }

    private func collageLivePhotoClippingPath(
        tileIndex: Int,
        outputSize: CGSize
    ) -> UIBezierPath? {
        guard previewView.bounds.width > 0,
              let renderInfo = collageView.renderInfoForTile(at: tileIndex),
              let path = renderInfo.tilePath.copy() as? UIBezierPath else {
            return nil
        }

        let outputScale = outputSize.width / previewView.bounds.width
        let collageOrigin = collageView.convert(CGPoint.zero, to: previewView)
        path.apply(CGAffineTransform(translationX: collageOrigin.x, y: collageOrigin.y))
        path.apply(CGAffineTransform(scaleX: outputScale, y: outputScale))
        return path
    }

    private func showExportLoading(text: String) {
        exportBarButtonItem.isEnabled = false
        resetBarButtonItem.isEnabled = false
        exportLoadingView.show(text: text, in: view)
    }

    private func hideExportLoading() {
        exportBarButtonItem.isEnabled = true
        resetBarButtonItem.isEnabled = true
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
        isExportChromeHidden = hidden
        if hidden {
            [routeSelectionBorderLayer, metricsSelectionBorderLayer].forEach { borderLayer in
                borderLayer.isHidden = true
                borderLayer.removeFromSuperlayer()
            }
            [routeDeleteCornerButton, metricsDeleteCornerButton].forEach { deleteButton in
                deleteButton.isHidden = true
            }
        } else {
            updatePreviewSelection()
        }
        collageView.setCropSelectionChromeHidden(hidden)
    }
}

extension WorkoutRouteShareViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        photoItems.count + 2 + (isCollageEntranceVisible ? 1 : 0)
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

        let item = photoBrowserItem(at: indexPath.item)
        switch item {
        case .map:
            let isSelected: Bool
            if case .map = previewBackground {
                isSelected = true
            } else {
                isSelected = false
            }
            cell.configureMap(isSelected: isSelected)
        case .collage:
            let isSelected: Bool
            if case .collage = previewBackground {
                isSelected = true
            } else {
                isSelected = false
            }
            cell.configureCollage(isSelected: isSelected)
        case .add:
            cell.configureAdd()
        case .photo(let photoIndex):
            let photoItem = photoItems[photoIndex]
            let isSelected = isPhotoSelectedInBrowser(at: photoIndex)
            switch photoItem {
            case .routeMedia(let mediaItem):
                cell.configure(asset: mediaItem.asset, isSelected: isSelected)
            case .uploaded(let image):
                cell.configure(image: image, isSelected: isSelected)
            }
        }
        cell.setDisabled(isPhotoBrowserItemDisabled(item))

        return cell
    }

    private enum PhotoBrowserItem {
        case map
        case collage
        case photo(Int)
        case add
    }

    private var isCollageEntranceVisible: Bool {
        photoItems.count >= 2
    }

    private func photoBrowserItem(at item: Int) -> PhotoBrowserItem {
        if item == 0 {
            return .map
        }

        if isCollageEntranceVisible {
            if item == 1 {
                return .collage
            }

            let photoIndex = item - 2
            return photoItems.indices.contains(photoIndex) ? .photo(photoIndex) : .add
        }

        let photoIndex = item - 1
        return photoItems.indices.contains(photoIndex) ? .photo(photoIndex) : .add
    }

    private func isPhotoBrowserItemDisabled(_ item: PhotoBrowserItem) -> Bool {
        return false
    }

    private func isPhotoSelectedInBrowser(at index: Int) -> Bool {
        if case .collage = previewBackground {
            return collagePhotoIndices.contains(index)
        }

        return selectedPhotoIndex == index
    }

    private func updateVisiblePhotoBrowserCellStates() {
        for indexPath in photoCollectionView.indexPathsForVisibleItems {
            guard let cell = photoCollectionView.cellForItem(at: indexPath) as? RouteSharePhotoCell else {
                continue
            }

            let item = photoBrowserItem(at: indexPath.item)
            let isSelected: Bool
            switch item {
            case .map:
                if case .map = previewBackground {
                    isSelected = true
                } else {
                    isSelected = false
                }
            case .collage:
                if case .collage = previewBackground {
                    isSelected = true
                } else {
                    isSelected = false
                }
            case .photo(let index):
                isSelected = isPhotoSelectedInBrowser(at: index)
            case .add:
                isSelected = false
            }

            cell.setSelectionHighlighted(isSelected)
            cell.setDisabled(isPhotoBrowserItemDisabled(item))
        }
    }
}

extension WorkoutRouteShareViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = photoBrowserItem(at: indexPath.item)
        guard !isPhotoBrowserItemDisabled(item) else {
            return
        }

        switch item {
        case .map:
            toggleMapBackground()
        case .collage:
            toggleCollageBackground()
        case .add:
            presentPhotoPicker()
        case .photo(let photoIndex):
            if case .collage = previewBackground {
                toggleCollagePhoto(at: photoIndex)
            } else {
                selectPhoto(at: photoIndex)
            }
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
                    let shouldShowPhotoAdjustmentToast: Bool
                    if self.pendingUploadedSelectionID == selectionID {
                        let wasPhotoBackground = self.isPhotoAdjustmentHintBackground
                        self.selectedPhotoIndex = newIndex
                        self.lastSelectedPhotoIndexForAspectRatio = newIndex
                        self.previewBackground = .photo(newIndex)
                        self.applyDefaultColorsForCurrentBackground()
                        self.representedPreviewPhotoID = nil
                        self.pendingUploadedSelectionID = nil
                        self.updatePreviewCanvasAspectRatio(animated: true, resetsModuleLayout: true)
                        shouldShowPhotoAdjustmentToast = !wasPhotoBackground
                    } else {
                        shouldShowPhotoAdjustmentToast = false
                    }
                    self.photoCollectionView.reloadData()
                    self.updatePreviewPhoto()
                    self.updateToolBarVisibility()
                    if shouldShowPhotoAdjustmentToast {
                        self.showBackgroundAdjustmentToast(for: .photoBackgroundAdjustmentHint)
                    }
                }
            }
        }
    }
}

extension WorkoutRouteShareViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === navigationController?.interactivePopGestureRecognizer
            || gestureRecognizer === interactivePopBlockerGesture {
            return false
        }

        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer.view === previewView else {
            return true
        }

        if isPreviewModuleGesture(gestureRecognizer) {
            if selectedPreviewModule != nil {
                return !interactivePreviewElementContains(touch, includesCollageInteractions: false)
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

    private func interactivePreviewElementContains(
        _ touch: UITouch,
        includesCollageInteractions: Bool = true
    ) -> Bool {
        let touchLocation = touch.location(in: previewView)
        if includesCollageInteractions,
           case .collage = previewBackground,
           !collageView.isHidden {
            let collageLocation = touch.location(in: collageView)
            if collageView.containsAdjustableDivider(at: collageLocation)
                || collageView.containsAdjustableTile(at: collageLocation) {
                return true
            }
        }

        let interactiveElementViews: [UIView] = [
            routeDeleteCornerButton,
            metricsDeleteCornerButton,
            brandPillView
        ]
        if interactiveElementViews.contains(where: { elementView in
            !elementView.isHidden && elementView.frame.contains(touchLocation)
        }) {
            return true
        }

        let moduleViews = [routeModuleView, metricsModuleView]
        return moduleViews.contains { moduleView in
            guard !moduleView.isHidden else {
                return false
            }
            let moduleLocation = previewView.convert(touchLocation, to: moduleView)
            return selectionChromeRect(for: moduleView).contains(moduleLocation)
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

    private func detailedErrorMessage(_ error: Error) -> String {
        #if DEBUG
        let nsError = error as NSError
        return """
        \(nsError.localizedDescription)

        \(nsError.domain)(\(nsError.code))
        \(nsError.userInfo)
        """
        #else
        return error.localizedDescription
        #endif
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
        renderer.strokeColor = effectiveRouteColor
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
