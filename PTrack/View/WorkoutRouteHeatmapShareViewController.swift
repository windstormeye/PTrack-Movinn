//
//  WorkoutRouteHeatmapShareViewController.swift
//  PTrack
//
//  Created by Codex on 2026/7/6.
//

import CoreLocation
import MapKit
import PhotosUI
import SnapKit
import UIKit

private func heatmapShareWeekCalendar(from calendar: Calendar) -> Calendar {
    var weekCalendar = calendar
    weekCalendar.firstWeekday = 2
    weekCalendar.minimumDaysInFirstWeek = 4
    return weekCalendar
}

final class WorkoutRouteHeatmapShareViewController: UIViewController {
    private enum DataScope: Int, CaseIterable {
        case week
        case month
        case year

        var titleKey: AppTextKey {
            switch self {
            case .week:
                return .heatmapShareWeek
            case .month:
                return .heatmapShareMonth
            case .year:
                return .heatmapShareYear
            }
        }
    }

    private enum DataBrowserItem: Int, CaseIterable {
        case week
        case month
        case year
        case photo

        var scope: DataScope? {
            switch self {
            case .week:
                return .week
            case .month:
                return .month
            case .year:
                return .year
            case .photo:
                return nil
            }
        }

        var titleKey: AppTextKey {
            switch self {
            case .week:
                return .heatmapShareWeek
            case .month:
                return .heatmapShareMonth
            case .year:
                return .heatmapShareYear
            case .photo:
                return .heatmapSharePhoto
            }
        }
    }

    private struct WeekOption: Hashable {
        let startDate: Date
        let endDate: Date
        let yearForWeek: Int
        let weekOfYear: Int
    }

    private struct MonthOption: Hashable {
        let startDate: Date
        let year: Int
        let month: Int
    }

    private struct TimelineWorkoutItem: Hashable {
        let id: String
        let startDate: Date
    }

    fileprivate struct RoutePreviewPath {
        let points: [CGPoint]
        let aspectRatio: CGFloat
    }

    private struct RoutePreviewItem {
        let id: String
        let startDate: Date
        let dateText: String
        let distanceMeters: Double
        let durationSeconds: TimeInterval
        let routePath: RoutePreviewPath
    }

    private struct PreparedWorkoutBatch {
        let routeItems: [RoutePreviewItem]
        let timelineItems: [TimelineWorkoutItem]

        var isEmpty: Bool {
            routeItems.isEmpty && timelineItems.isEmpty
        }
    }

    private enum Layout {
        static let navigationBackgroundHeight: CGFloat = 124
        static let previewHorizontalInset: CGFloat = 16
        static let previewCornerRadius: CGFloat = 18
        static let previewTopInset: CGFloat = 22
        static let previewSideInset: CGFloat = 18
        static let previewHeaderHeight: CGFloat = 72
        static let routeColumnCount = 6
        static let routeCellSpacing: CGFloat = 7
        static let routeCellMinimumSide: CGFloat = 34
        static let defaultRouteCellSide: CGFloat = 44
        static let brandBottomInset: CGFloat = 18
        static let brandPillSize = CGSize(width: 68, height: 21)
        static let routeGridToBrandSpacing: CGFloat = 30
        static let dataBrowserHeight: CGFloat = 70
        static let toolbarHeight: CGFloat = 52
    }

    private var routePreviewItems: [RoutePreviewItem]
    private var displayedRouteItems: [RoutePreviewItem] = []
    private var knownSourceWorkoutIDs: Set<String>
    private var timelineItems: [TimelineWorkoutItem]
    private var knownTimelineWorkoutIDs: Set<String>
    private let selectedFilters: Set<HeatmapFilter>
    private let selectedYearFilter: Int?
    private let referenceDate: Date
    private let cacheStore = WorkoutCacheStore()
    private let cacheLoadQueue = DispatchQueue(label: "studio.pj.PTrack.heatmap-share-cache-load", qos: .userInitiated)
    private let allowsCacheAugmentation: Bool
    private let allowsPhotoBackground: Bool
    private let allowsPhotoLibrarySaving: Bool
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let navigationTitleLabel = UILabel()
    private let cacheLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var navigationTitleView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [navigationTitleLabel, cacheLoadingIndicator])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 7
        return stackView
    }()
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let previewContainerView = UIView()
    private let previewView = UIView()
    private let gradientView = AnimatedProGradientView()
    private let photoBackgroundView = HeatmapSharePhotoBackgroundView()
    private let photoBackgroundOverlayView = UIView()
    private let brandPillView = RouteShareBrandPillView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let emptyLabel = UILabel()
    private let bottomControlsView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let dataBrowserCollectionView: UICollectionView
    private let routeCollectionView: UICollectionView
    private let routeCollectionLayout = UICollectionViewFlowLayout()
    private let toolBarScrollView = UIScrollView()
    private let toolBarView = RouteShareToolBarView()
    private var maskToolButton: UIButton { toolBarView.canvasColorButton }
    private var colorToolButton: UIButton { toolBarView.colorButton }
    private let exportLoadingView = RouteShareExportLoadingView()
    private lazy var exportBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "checkmark"),
        style: .done,
        target: self,
        action: #selector(savePreviewImage)
    )
    private lazy var resetBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "arrow.counterclockwise"),
        style: .plain,
        target: self,
        action: #selector(resetPreviewContent)
    )

    private var routeCollectionHeightConstraint: Constraint?
    private var previewHeightConstraint: Constraint?
    private var previewContainerMinimumHeightConstraint: Constraint?
    private var toolBarWidthConstraint: Constraint?
    private var selectedScope: DataScope = .month
    private var selectedWeekStartDate: Date
    private var selectedMonthStartDate: Date
    private var selectedYear: Int
    private var removedWorkoutIDs = Set<String>()
    private var routeColorsByWorkoutID: [String: UIColor] = [:]
    private var selectedWorkoutID: String?
    private var applyColorToAllRoutes = false
    private var photoBackgroundImages: [UIImage] = []
    private var photoBackgroundOverlayOpacity: CGFloat = 0.38
    private var pendingPhotoSelectionID: UUID?
    private var isPhotoBackgroundAdjustmentEnabled = false
    private var photoBackgroundScale: CGFloat = 1
    private var photoBackgroundTranslation: CGPoint = .zero
    private weak var photoBackgroundPanGesture: UIPanGestureRecognizer?
    private weak var photoBackgroundPinchGesture: UIPinchGestureRecognizer?
    private weak var photoBackgroundDoubleTapGesture: UITapGestureRecognizer?
    private weak var previewBlankTapGesture: UITapGestureRecognizer?
    private var currentColumnCount = 0
    private var routeCellSide = Layout.defaultRouteCellSide
    private var timeOptionsMenuView: HeatmapShareTimeOptionsMenuView?
    private var cacheLoadGeneration = 0
    private var isLoadingCachedWorkouts = false
    private var hasCompletedCachedWorkoutLoad = false
    private var didInitializeDateFromLoadedWorkouts: Bool
    private var pendingPreviewReloadWorkItem: DispatchWorkItem?
    private let cacheLoadBatchSize = 128
    private let previewReloadThrottleInterval: TimeInterval = 0.22
    private let photoBackgroundMinimumScale: CGFloat = 1
    private let photoBackgroundMaximumScale: CGFloat = 4
    private var dataBrowserItems: [DataBrowserItem] {
        allowsPhotoBackground ? DataBrowserItem.allCases : DataBrowserItem.allCases.filter { $0 != .photo }
    }

    init(
        workouts: [TrackedWorkout],
        referenceDate: Date? = nil,
        timelineWorkouts: [TrackedWorkout]? = nil,
        selectedFilters: Set<HeatmapFilter> = Set(HeatmapFilter.allCases),
        selectedYear: Int? = nil,
        allowsCacheAugmentation: Bool = true,
        allowsPhotoBackground: Bool = true,
        allowsPhotoLibrarySaving: Bool = true
    ) {
        self.allowsCacheAugmentation = allowsCacheAugmentation
        self.allowsPhotoBackground = allowsPhotoBackground
        self.allowsPhotoLibrarySaving = allowsPhotoLibrarySaving
        self.selectedFilters = selectedFilters
        selectedYearFilter = selectedYear
        let routeItems = Self.routePreviewItems(
            for: workouts,
            selectedFilters: selectedFilters,
            selectedYear: selectedYear
        )
        routePreviewItems = routeItems
        knownSourceWorkoutIDs = Set(routeItems.map(\.id))
        let resolvedTimelineItems = Self.timelineItems(
            for: timelineWorkouts ?? workouts,
            selectedFilters: selectedFilters,
            selectedYear: selectedYear
        )
        self.timelineItems = resolvedTimelineItems
        knownTimelineWorkoutIDs = Set(resolvedTimelineItems.map(\.id))
        didInitializeDateFromLoadedWorkouts = !routeItems.isEmpty || !resolvedTimelineItems.isEmpty
        let resolvedReferenceDate = referenceDate
            ?? resolvedTimelineItems.map(\.startDate).max()
            ?? routeItems.map(\.startDate).max()
            ?? Date()
        self.referenceDate = resolvedReferenceDate

        let weekCalendar = heatmapShareWeekCalendar(from: .current)
        selectedWeekStartDate = weekCalendar.dateInterval(of: .weekOfYear, for: resolvedReferenceDate)?.start
            ?? resolvedReferenceDate
        let calendar = Calendar.current
        selectedMonthStartDate = calendar.date(
            from: calendar.dateComponents([.year, .month], from: resolvedReferenceDate)
        ) ?? resolvedReferenceDate
        self.selectedYear = calendar.component(.year, from: resolvedReferenceDate)

        let dataLayout = UICollectionViewFlowLayout()
        dataLayout.scrollDirection = .horizontal
        dataLayout.minimumLineSpacing = 8
        dataLayout.minimumInteritemSpacing = 8
        dataBrowserCollectionView = UICollectionView(frame: .zero, collectionViewLayout: dataLayout)

        routeCollectionLayout.scrollDirection = .vertical
        routeCollectionLayout.minimumLineSpacing = Layout.routeCellSpacing
        routeCollectionLayout.minimumInteritemSpacing = Layout.routeCellSpacing
        routeCollectionView = UICollectionView(frame: .zero, collectionViewLayout: routeCollectionLayout)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cacheLoadGeneration += 1
        pendingPreviewReloadWorkItem?.cancel()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        AppAppearanceStore.shared.preferredStatusBarStyle(for: traitCollection)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureNavigationBar()
        configureScrollView()
        configurePreviewView()
        configureDataBrowser()
        configureRouteCollectionView()
        configureBottomControls()
        configureNavigationBackgroundView()
        configureExportLoadingView()
        updateLocalizedText()
        reloadPreviewContent()
        startCachedWorkoutLoading()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        configureNavigationBar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateRouteCollectionLayoutIfNeeded()
        updatePreviewContainerMinimumHeight()
        applyPhotoBackgroundAdjustment()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dismissTimeOptionsMenu(animated: false)
    }

    private func configureNavigationItem() {
        view.backgroundColor = AppColors.sharePageBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.titleView = navigationTitleView
        navigationTitleLabel.textColor = .label
        navigationTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        navigationTitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        cacheLoadingIndicator.color = .secondaryLabel
        cacheLoadingIndicator.hidesWhenStopped = true
        exportBarButtonItem.tintColor = AppColors.movinnGreen
        resetBarButtonItem.tintColor = AppColors.solidForeground
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

    private func configureScrollView() {
        scrollView.backgroundColor = AppColors.sharePageBackground
        contentView.backgroundColor = AppColors.sharePageBackground
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.contentInset = UIEdgeInsets(
            top: Layout.navigationBackgroundHeight,
            left: 0,
            bottom: 170,
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
        previewView.layer.cornerRadius = Layout.previewCornerRadius
        previewView.layer.cornerCurve = .continuous
        previewView.layer.masksToBounds = true
        previewView.backgroundColor = .black

        gradientView.apply(style: .paywallBackground, traitCollection: UITraitCollection(userInterfaceStyle: .dark))
        photoBackgroundView.isHidden = true
        photoBackgroundOverlayView.isHidden = true
        photoBackgroundOverlayView.isUserInteractionEnabled = false
        photoBackgroundOverlayView.backgroundColor = UIColor.black.withAlphaComponent(photoBackgroundOverlayOpacity)

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 24, weight: .heavy)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.72
        titleLabel.numberOfLines = 1

        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        subtitleLabel.adjustsFontSizeToFitWidth = true
        subtitleLabel.minimumScaleFactor = 0.72
        subtitleLabel.numberOfLines = 1

        emptyLabel.textColor = UIColor.white.withAlphaComponent(0.58)
        emptyLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 2

        configurePhotoBackgroundGestures()

        contentView.addSubview(previewContainerView)
        previewContainerView.addSubview(previewView)
        previewView.addSubview(gradientView)
        previewView.addSubview(photoBackgroundView)
        previewView.addSubview(photoBackgroundOverlayView)
        previewView.addSubview(titleLabel)
        previewView.addSubview(subtitleLabel)
        previewView.addSubview(brandPillView)
        previewView.addSubview(emptyLabel)
        previewView.addSubview(routeCollectionView)

        previewContainerView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.trailing.equalToSuperview()
            previewContainerMinimumHeightConstraint = make.height.greaterThanOrEqualTo(1).constraint
            make.bottom.equalToSuperview().inset(24)
        }
        previewView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(Layout.previewHorizontalInset)
            previewHeightConstraint = make.height.equalTo(1).constraint
            make.top.greaterThanOrEqualToSuperview().offset(6)
            make.bottom.lessThanOrEqualToSuperview().inset(6)
        }
        gradientView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        photoBackgroundView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        photoBackgroundOverlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Layout.previewTopInset)
            make.leading.equalToSuperview().offset(Layout.previewSideInset)
            make.trailing.equalToSuperview().inset(Layout.previewSideInset)
        }
        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(3)
            make.leading.equalTo(titleLabel)
            make.trailing.equalTo(titleLabel)
        }
        brandPillView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(Layout.brandBottomInset)
            make.size.equalTo(Layout.brandPillSize)
        }
        routeCollectionView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Layout.previewHeaderHeight)
            make.leading.trailing.equalToSuperview().inset(Layout.previewSideInset)
            routeCollectionHeightConstraint = make.height.equalTo(1).constraint
            make.bottom.lessThanOrEqualTo(brandPillView.snp.top).offset(-Layout.routeGridToBrandSpacing)
        }
        emptyLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(routeCollectionView).offset(42)
            make.leading.trailing.equalTo(routeCollectionView).inset(16)
        }
    }

    private func configureDataBrowser() {
        dataBrowserCollectionView.backgroundColor = .clear
        dataBrowserCollectionView.showsHorizontalScrollIndicator = false
        dataBrowserCollectionView.alwaysBounceHorizontal = true
        dataBrowserCollectionView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        dataBrowserCollectionView.dataSource = self
        dataBrowserCollectionView.delegate = self
        dataBrowserCollectionView.register(
            HeatmapShareDataScopeCell.self,
            forCellWithReuseIdentifier: HeatmapShareDataScopeCell.reuseIdentifier
        )
    }

    private func configureRouteCollectionView() {
        routeCollectionView.backgroundColor = .clear
        routeCollectionView.isScrollEnabled = false
        routeCollectionView.showsVerticalScrollIndicator = false
        routeCollectionView.dataSource = self
        routeCollectionView.delegate = self
        routeCollectionView.register(
            HeatmapShareRouteCell.self,
            forCellWithReuseIdentifier: HeatmapShareRouteCell.reuseIdentifier
        )

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleRouteLongPress(_:)))
        routeCollectionView.addGestureRecognizer(longPressGesture)
    }

    private func configurePhotoBackgroundGestures() {
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePhotoBackgroundDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.cancelsTouchesInView = false
        doubleTapGesture.delegate = self
        previewView.addGestureRecognizer(doubleTapGesture)
        photoBackgroundDoubleTapGesture = doubleTapGesture

        let blankTapGesture = UITapGestureRecognizer(target: self, action: #selector(handlePreviewBlankTap(_:)))
        blankTapGesture.cancelsTouchesInView = false
        blankTapGesture.delegate = self
        blankTapGesture.require(toFail: doubleTapGesture)
        previewView.addGestureRecognizer(blankTapGesture)
        previewBlankTapGesture = blankTapGesture

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePhotoBackgroundPan(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        previewView.addGestureRecognizer(panGesture)
        photoBackgroundPanGesture = panGesture

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePhotoBackgroundPinch(_:)))
        pinchGesture.cancelsTouchesInView = false
        pinchGesture.delegate = self
        previewView.addGestureRecognizer(pinchGesture)
        photoBackgroundPinchGesture = pinchGesture
    }

    private func configureBottomControls() {
        bottomControlsView.effect = nil
        bottomControlsView.backgroundColor = .clear
        bottomControlsView.contentView.backgroundColor = .clear
        toolBarView.backgroundColor = AppColors.toolbarBackground
        toolBarScrollView.backgroundColor = .clear
        toolBarScrollView.showsHorizontalScrollIndicator = false
        toolBarScrollView.alwaysBounceHorizontal = true
        toolBarScrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        colorToolButton.addTarget(self, action: #selector(presentRouteColorPicker), for: .touchUpInside)
        maskToolButton.addTarget(self, action: #selector(presentPhotoMaskOpacitySlider), for: .touchUpInside)

        [
            toolBarView.aspectRatioButton,
            toolBarView.calorieFoodButton,
            toolBarView.mapStyleButton,
            toolBarView.collageButton,
            toolBarView.collageStyleButton,
            toolBarView.deleteButton,
            toolBarView.addRouteButton,
            toolBarView.addMetricsButton,
            toolBarView.livePhotoButton
        ].forEach { $0.isHidden = true }

        view.addSubview(bottomControlsView)
        bottomControlsView.contentView.addSubview(dataBrowserCollectionView)
        bottomControlsView.contentView.addSubview(toolBarScrollView)
        toolBarScrollView.addSubview(toolBarView)

        bottomControlsView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
        dataBrowserCollectionView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(10)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(Layout.dataBrowserHeight)
        }
        toolBarScrollView.snp.makeConstraints { make in
            make.top.equalTo(dataBrowserCollectionView.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(Layout.toolbarHeight)
            make.bottom.equalTo(bottomControlsView.safeAreaLayoutGuide).inset(12)
        }
        toolBarView.snp.makeConstraints { make in
            make.top.bottom.equalTo(toolBarScrollView.contentLayoutGuide)
            make.leading.trailing.equalTo(toolBarScrollView.contentLayoutGuide)
            make.height.equalTo(Layout.toolbarHeight)
            toolBarWidthConstraint = make.width.equalTo(RouteShareToolBarView.preferredWidth(for: 1)).constraint
        }
    }

    private func configureNavigationBackgroundView() {
        navigationBackgroundView.isUserInteractionEnabled = false
        navigationBackgroundView.effect = nil
        navigationBackgroundView.backgroundColor = .clear
        navigationBackgroundView.contentView.backgroundColor = .clear
        view.addSubview(navigationBackgroundView)
        navigationBackgroundView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(Layout.navigationBackgroundHeight)
        }
    }

    private func configureExportLoadingView() {
        view.addSubview(exportLoadingView)
        exportLoadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func updateLocalizedText() {
        let titleText = AppLocalization.text(.heatmapShareTitle)
        title = titleText
        navigationTitleLabel.text = titleText
        emptyLabel.text = emptyMessageText()
        configureToolButtons()
    }

    private func configureToolButtons() {
        maskToolButton.configuration = toolButtonConfiguration(
            title: AppLocalization.text(.heatmapShareMask),
            imageName: "circle.lefthalf.filled"
        )
        maskToolButton.isHidden = !hasPhotoBackground
        maskToolButton.isEnabled = hasPhotoBackground
        maskToolButton.alpha = hasPhotoBackground ? 1 : 0.45

        colorToolButton.configuration = toolButtonConfiguration(
            title: AppLocalization.text(.color),
            imageName: "paintpalette"
        )
        colorToolButton.isEnabled = selectedWorkoutID != nil
        colorToolButton.alpha = selectedWorkoutID == nil ? 0.45 : 1
        toolBarWidthConstraint?.update(offset: RouteShareToolBarView.preferredWidth(for: toolBarView.visibleButtonCount()))
    }

    private func toolButtonConfiguration(title: String, imageName: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: imageName)
        configuration.imagePlacement = .top
        configuration.imagePadding = 4
        configuration.title = title
        configuration.baseForegroundColor = AppColors.solidForeground
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 5, trailing: 4)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 11, weight: .semibold)
            return outgoing
        }
        return configuration
    }

    private func reloadPreviewContent() {
        let items = routeItemsForCurrentScope()
        displayedRouteItems = items
        selectedWorkoutID = selectedWorkoutID.flatMap { id in
            items.contains { $0.id == id } ? id : nil
        }
        titleLabel.text = titleTextForCurrentScope()
        subtitleLabel.text = metricsText(for: items)
        emptyLabel.text = emptyMessageText()
        emptyLabel.isHidden = !items.isEmpty
        UIView.performWithoutAnimation {
            routeCollectionView.reloadData()
            dataBrowserCollectionView.reloadData()
        }
        configureToolButtons()
        updateRouteCollectionLayoutIfNeeded()
    }

    private var hasPhotoBackground: Bool {
        !photoBackgroundImages.isEmpty
    }

    private func updatePhotoBackground() {
        let hasPhotoBackground = hasPhotoBackground
        photoBackgroundView.images = photoBackgroundImages
        photoBackgroundView.isHidden = !hasPhotoBackground
        photoBackgroundOverlayView.isHidden = !hasPhotoBackground
        photoBackgroundOverlayView.backgroundColor = UIColor.black.withAlphaComponent(photoBackgroundOverlayOpacity)
        gradientView.isHidden = hasPhotoBackground
        if !hasPhotoBackground {
            isPhotoBackgroundAdjustmentEnabled = false
            resetPhotoBackgroundAdjustment()
        }
        configureToolButtons()
        dataBrowserCollectionView.reloadData()
    }

    private func resetPhotoBackgroundAdjustment() {
        photoBackgroundScale = 1
        photoBackgroundTranslation = .zero
        applyPhotoBackgroundAdjustment()
    }

    private func applyPhotoBackgroundAdjustment() {
        photoBackgroundTranslation = clampedPhotoBackgroundTranslation(photoBackgroundTranslation)
        photoBackgroundView.contentScale = photoBackgroundScale
        photoBackgroundView.contentTranslation = photoBackgroundTranslation
    }

    private func clampedPhotoBackgroundTranslation(_ translation: CGPoint) -> CGPoint {
        let bounds = previewView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return translation
        }

        let scaledWidth = bounds.width * photoBackgroundScale
        let maxX = max((scaledWidth - bounds.width) / 2, 0)
        let maxY = max(bounds.height, 1)
        return CGPoint(
            x: min(max(translation.x, -maxX), maxX),
            y: min(max(translation.y, -maxY), maxY)
        )
    }

    private func schedulePreviewReload() {
        guard pendingPreviewReloadWorkItem == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            pendingPreviewReloadWorkItem = nil
            reloadPreviewContent()
        }
        pendingPreviewReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + previewReloadThrottleInterval, execute: workItem)
    }

    private func flushScheduledPreviewReload() {
        pendingPreviewReloadWorkItem?.cancel()
        pendingPreviewReloadWorkItem = nil
        reloadPreviewContent()
    }

    private func startCachedWorkoutLoading() {
        guard allowsCacheAugmentation else {
            hasCompletedCachedWorkoutLoad = true
            setCachedWorkoutLoading(false)
            return
        }

        guard !isLoadingCachedWorkouts, !hasCompletedCachedWorkoutLoad else {
            return
        }

        cacheLoadGeneration += 1
        let generation = cacheLoadGeneration
        setCachedWorkoutLoading(true)
        let cacheStore = cacheStore
        let batchSize = cacheLoadBatchSize
        let selectedFilters = selectedFilters
        let selectedYear = selectedYearFilter

        cacheLoadQueue.async { [weak self, cacheStore, batchSize, selectedFilters, selectedYear] in
            cacheStore.loadProgressively(
                batchSize: batchSize,
                onBatch: { [weak self] batch in
                    let preparedBatch = Self.preparedWorkoutBatch(
                        from: batch,
                        selectedFilters: selectedFilters,
                        selectedYear: selectedYear
                    )
                    guard !preparedBatch.isEmpty else {
                        return
                    }

                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              self.cacheLoadGeneration == generation else {
                            return
                        }

                        self.mergeCachedWorkoutBatch(preparedBatch)
                    }
                }
            )

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.cacheLoadGeneration == generation else {
                    return
                }

                self.hasCompletedCachedWorkoutLoad = true
                self.setCachedWorkoutLoading(false)
                self.flushScheduledPreviewReload()
            }
        }
    }

    private func setCachedWorkoutLoading(_ isLoading: Bool) {
        guard isLoadingCachedWorkouts != isLoading else {
            return
        }

        isLoadingCachedWorkouts = isLoading
        if isLoading {
            cacheLoadingIndicator.startAnimating()
        } else {
            cacheLoadingIndicator.stopAnimating()
        }
        emptyLabel.text = emptyMessageText()
    }

    private func mergeCachedWorkoutBatch(_ batch: PreparedWorkoutBatch) {
        var didInsertTimelineItem = false
        timelineItems.reserveCapacity(timelineItems.count + batch.timelineItems.count)
        for item in batch.timelineItems where knownTimelineWorkoutIDs.insert(item.id).inserted {
            timelineItems.append(item)
            didInsertTimelineItem = true
        }
        if didInsertTimelineItem {
            timelineItems.sort { $0.startDate < $1.startDate }
        }

        var didInsertRouteItem = false
        routePreviewItems.reserveCapacity(routePreviewItems.count + batch.routeItems.count)
        let inheritedRouteColor = routeColorsByWorkoutID[selectedWorkoutID ?? ""]
            ?? routeColorsByWorkoutID.values.first
            ?? UIColor.white
        for item in batch.routeItems where knownSourceWorkoutIDs.insert(item.id).inserted {
            routePreviewItems.append(item)
            if applyColorToAllRoutes {
                routeColorsByWorkoutID[item.id] = inheritedRouteColor
            }
            didInsertRouteItem = true
        }

        guard didInsertTimelineItem || didInsertRouteItem else {
            return
        }

        if didInsertRouteItem {
            routePreviewItems.sort { $0.startDate < $1.startDate }
        }

        if !didInitializeDateFromLoadedWorkouts,
           let latestDate = (routePreviewItems.map(\.startDate) + timelineItems.map(\.startDate)).max() {
            didInitializeDateFromLoadedWorkouts = true
            updateSelectedDates(with: latestDate)
        }
        schedulePreviewReload()
    }

    private func updateSelectedDates(with date: Date) {
        let weekCalendar = heatmapShareWeekCalendar(from: .current)
        selectedWeekStartDate = weekCalendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let calendar = Calendar.current
        selectedMonthStartDate = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? date
        selectedYear = calendar.component(.year, from: date)
    }

    private func emptyMessageText() -> String {
        isLoadingCachedWorkouts
            ? AppLocalization.text(.routeLoading)
            : AppLocalization.text(.heatmapShareNoRoutes)
    }

    private func routeItemsForCurrentScope() -> [RoutePreviewItem] {
        guard let interval = dateIntervalForCurrentScope() else {
            return []
        }

        return routePreviewItems
            .filter { item in
                !removedWorkoutIDs.contains(item.id)
                    && item.startDate >= interval.start
                    && item.startDate < interval.end
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private func dateIntervalForCurrentScope() -> DateInterval? {
        let calendar = Calendar.current
        switch selectedScope {
        case .week:
            let weekCalendar = heatmapShareWeekCalendar(from: calendar)
            guard let endDate = weekCalendar.date(byAdding: .day, value: 7, to: selectedWeekStartDate) else {
                return nil
            }
            return DateInterval(start: selectedWeekStartDate, end: endDate)
        case .month:
            guard let endDate = calendar.date(byAdding: .month, value: 1, to: selectedMonthStartDate) else {
                return nil
            }
            return DateInterval(start: selectedMonthStartDate, end: endDate)
        case .year:
            let components = DateComponents(calendar: calendar, year: selectedYear, month: 1, day: 1)
            guard let startDate = calendar.date(from: components),
                  let endDate = calendar.date(byAdding: .year, value: 1, to: startDate) else {
                return nil
            }
            return DateInterval(start: startDate, end: endDate)
        }
    }

    private func titleTextForCurrentScope() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguageStore.shared.language.rawValue)
        switch selectedScope {
        case .week:
            let weekCalendar = heatmapShareWeekCalendar(from: .current)
            let week = min(max(weekCalendar.component(.weekOfYear, from: selectedWeekStartDate), 1), 53)
            return AppLocalization.format(.sportsCareerWeekTitleWithRangeFormat, week, shortDateText(selectedWeekStartDate), shortDateText(weekEndDate()))
        case .month:
            formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
            return formatter.string(from: selectedMonthStartDate)
        case .year:
            formatter.setLocalizedDateFormatFromTemplate("yyyy")
            let components = DateComponents(calendar: .current, year: selectedYear, month: 1, day: 1)
            return components.date.map(formatter.string(from:)) ?? "\(selectedYear) 年"
        }
    }

    private func shortDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguageStore.shared.language.rawValue)
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    private func weekEndDate() -> Date {
        let weekCalendar = heatmapShareWeekCalendar(from: .current)
        return weekCalendar.date(byAdding: .day, value: 6, to: selectedWeekStartDate) ?? selectedWeekStartDate
    }

    private func metricsText(for items: [RoutePreviewItem]) -> String {
        let distance = items.reduce(0) { $0 + $1.distanceMeters }
        let duration = items.reduce(0) { $0 + $1.durationSeconds }
        return "\(distanceText(distance)) · \(durationText(duration))"
    }

    private func distanceText(_ value: Double) -> String {
        String(format: "%.1f km", max(value, 0) / 1_000)
    }

    private func durationText(_ value: Double) -> String {
        AppLocalization.format(.durationHoursFormat, max(Int(value / 3_600), 0))
    }

    private func updateRouteCollectionLayoutIfNeeded() {
        guard isViewLoaded else {
            return
        }

        let availableWidth = max(routeCollectionView.bounds.width, previewView.bounds.width - Layout.previewSideInset * 2)
        guard availableWidth > 0 else {
            return
        }

        let spacing = Layout.routeCellSpacing
        let columnCount = Layout.routeColumnCount
        let side = max(
            floor((availableWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)),
            Layout.routeCellMinimumSide
        )
        let cellSize = CGSize(width: side, height: side)
        let cellWidth = cellSize.width
        let totalCellWidth = CGFloat(columnCount) * cellWidth + CGFloat(max(columnCount - 1, 0)) * spacing
        let horizontalInset = max((availableWidth - totalCellWidth) / 2, 0)
        if columnCount != currentColumnCount
            || routeCellSide != side
            || routeCollectionLayout.sectionInset.left != horizontalInset {
            currentColumnCount = columnCount
            routeCellSide = side
            routeCollectionLayout.itemSize = cellSize
            routeCollectionLayout.minimumLineSpacing = spacing
            routeCollectionLayout.minimumInteritemSpacing = spacing
            routeCollectionLayout.sectionInset = UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
            routeCollectionLayout.invalidateLayout()
        }

        let itemCount = displayedRouteItems.count
        let rowCount = max(Int(ceil(Double(itemCount) / Double(columnCount))), itemCount == 0 ? 1 : 0)
        let height = itemCount == 0
            ? 128
            : CGFloat(rowCount) * side + CGFloat(max(rowCount - 1, 0)) * spacing
        routeCollectionHeightConstraint?.update(offset: height)
        updatePreviewHeight(routeCollectionHeight: height)
    }

    private func updatePreviewHeight(routeCollectionHeight: CGFloat) {
        let previewWidth = max(
            previewView.bounds.width,
            view.bounds.width - Layout.previewHorizontalInset * 2
        )
        guard previewWidth > 0 else {
            return
        }

        let contentHeight = Layout.previewHeaderHeight
            + routeCollectionHeight
            + Layout.routeGridToBrandSpacing
            + Layout.brandPillSize.height
            + Layout.brandBottomInset
        previewHeightConstraint?.update(offset: max(previewWidth, contentHeight))
    }

    private func updatePreviewContainerMinimumHeight() {
        let bottomControlsHeight = bottomControlsView.bounds.height > 0
            ? bottomControlsView.bounds.height
            : 170
        let availableHeight = view.bounds.height
            - Layout.navigationBackgroundHeight
            - bottomControlsHeight
            - 12
        previewContainerMinimumHeightConstraint?.update(offset: max(availableHeight, 1))
    }

    private func presentTimeOptions(for scope: DataScope, sourceView: UIView) {
        let options = timeMenuOptions(for: scope)
        guard !options.isEmpty else {
            Toast.show(AppLocalization.text(.heatmapShareNoRoutes), in: view)
            return
        }

        dismissTimeOptionsMenu(animated: false)
        let menuView = HeatmapShareTimeOptionsMenuView(options: options)
        timeOptionsMenuView = menuView
        menuView.onDismiss = { [weak self, weak menuView] in
            guard let self,
                  self.timeOptionsMenuView === menuView else {
                return
            }

            self.timeOptionsMenuView = nil
        }
        menuView.present(in: view, sourceRect: sourceView.convert(sourceView.bounds, to: view))
    }

    private func timeMenuOptions(for scope: DataScope) -> [HeatmapShareTimeMenuOption] {
        switch scope {
        case .week:
            return availableWeekOptions().map { option in
                HeatmapShareTimeMenuOption(
                    title: weekOptionTitle(option),
                    isSelected: Calendar.current.isDate(option.startDate, inSameDayAs: selectedWeekStartDate),
                    textAlignment: .left
                ) { [weak self] in
                    self?.selectedWeekStartDate = option.startDate
                    self?.selectedWorkoutID = nil
                    self?.reloadPreviewContent()
                }
            }
        case .month:
            return availableMonthOptions().map { option in
                HeatmapShareTimeMenuOption(
                    title: monthOptionTitle(option),
                    isSelected: Calendar.current.isDate(option.startDate, inSameDayAs: selectedMonthStartDate)
                ) { [weak self] in
                    self?.selectedMonthStartDate = option.startDate
                    self?.selectedWorkoutID = nil
                    self?.reloadPreviewContent()
                }
            }
        case .year:
            return availableYearOptions().map { year in
                HeatmapShareTimeMenuOption(
                    title: "\(year)",
                    isSelected: year == selectedYear
                ) { [weak self] in
                    self?.selectedYear = year
                    self?.selectedWorkoutID = nil
                    self?.reloadPreviewContent()
                }
            }
        }
    }

    private func dismissTimeOptionsMenu(animated: Bool) {
        timeOptionsMenuView?.dismiss(animated: animated)
        timeOptionsMenuView = nil
    }

    private func availableWeekOptions() -> [WeekOption] {
        let calendar = heatmapShareWeekCalendar(from: .current)
        let options = Set(timelineItems.compactMap { item -> WeekOption? in
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: item.startDate),
                  let endDate = calendar.date(byAdding: .day, value: 6, to: interval.start) else {
                return nil
            }
            return WeekOption(
                startDate: interval.start,
                endDate: endDate,
                yearForWeek: calendar.component(.yearForWeekOfYear, from: item.startDate),
                weekOfYear: calendar.component(.weekOfYear, from: item.startDate)
            )
        })

        return options.sorted { $0.startDate > $1.startDate }
    }

    private func availableMonthOptions() -> [MonthOption] {
        let calendar = Calendar.current
        let options = Set(timelineItems.compactMap { item -> MonthOption? in
            let components = calendar.dateComponents([.year, .month], from: item.startDate)
            guard let year = components.year,
                  let month = components.month,
                  let startDate = calendar.date(from: components) else {
                return nil
            }
            return MonthOption(startDate: startDate, year: year, month: month)
        })

        return options.sorted { $0.startDate > $1.startDate }
    }

    private func availableYearOptions() -> [Int] {
        Array(Set(timelineItems.map { Calendar.current.component(.year, from: $0.startDate) })).sorted(by: >)
    }

    private func weekOptionTitle(_ option: WeekOption) -> String {
        let weekText = AppLocalization.format(
            .sportsCareerWeekTitleWithRangeFormat,
            min(max(option.weekOfYear, 1), 53),
            shortDateText(option.startDate),
            shortDateText(option.endDate)
        )
        return "\(option.yearForWeek) 年 · \(weekText)"
    }

    private func monthOptionTitle(_ option: MonthOption) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguageStore.shared.language.rawValue)
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
        return formatter.string(from: option.startDate)
    }

    @objc private func resetPreviewContent() {
        removedWorkoutIDs.removeAll()
        routeColorsByWorkoutID.removeAll()
        selectedWorkoutID = nil
        applyColorToAllRoutes = false
        photoBackgroundImages.removeAll()
        pendingPhotoSelectionID = nil
        photoBackgroundOverlayOpacity = 0.38
        updatePhotoBackground()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reloadPreviewContent()
    }

    @objc private func handlePhotoBackgroundDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended,
              hasPhotoBackground else {
            return
        }

        isPhotoBackgroundAdjustmentEnabled = true
        selectedWorkoutID = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        routeCollectionView.reloadData()
        configureToolButtons()
    }

    @objc private func handlePreviewBlankTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended,
              selectedWorkoutID != nil || isPhotoBackgroundAdjustmentEnabled else {
            return
        }

        selectedWorkoutID = nil
        isPhotoBackgroundAdjustmentEnabled = false
        UISelectionFeedbackGenerator().selectionChanged()
        routeCollectionView.reloadData()
        configureToolButtons()
    }

    @objc private func handlePhotoBackgroundPan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard hasPhotoBackground,
              isPhotoBackgroundAdjustmentEnabled else {
            return
        }

        let translation = gestureRecognizer.translation(in: previewView)
        photoBackgroundTranslation = clampedPhotoBackgroundTranslation(
            CGPoint(
                x: photoBackgroundTranslation.x + translation.x,
                y: photoBackgroundTranslation.y + translation.y
            )
        )
        applyPhotoBackgroundAdjustment()
        gestureRecognizer.setTranslation(.zero, in: previewView)
    }

    @objc private func handlePhotoBackgroundPinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
        guard hasPhotoBackground,
              isPhotoBackgroundAdjustmentEnabled else {
            return
        }

        photoBackgroundScale = min(
            max(photoBackgroundScale * gestureRecognizer.scale, photoBackgroundMinimumScale),
            photoBackgroundMaximumScale
        )
        applyPhotoBackgroundAdjustment()
        gestureRecognizer.scale = 1
    }

    private func presentPhotoBackgroundPicker() {
        guard allowsPhotoBackground else {
            return
        }

        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = estimatedPhotoBackgroundSelectionLimit()
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        pendingPhotoSelectionID = UUID()
        present(picker, animated: true)
    }

    private func estimatedPhotoBackgroundSelectionLimit() -> Int {
        view.layoutIfNeeded()
        let fallbackWidth = max(view.bounds.width - Layout.previewHorizontalInset * 2, 1)
        let previewWidth = max(previewView.bounds.width, fallbackWidth)
        let previewHeight = max(previewView.bounds.height, previewWidth)
        let estimatedPortraitPhotoHeight = previewWidth * 4 / 3
        return min(max(Int(ceil(previewHeight / max(estimatedPortraitPhotoHeight, 1))), 1), 12)
    }

    @objc private func presentPhotoMaskOpacitySlider() {
        guard hasPhotoBackground else {
            return
        }

        let viewController = HeatmapShareMaskOpacityViewController(
            initialOpacity: photoBackgroundOverlayOpacity
        ) { [weak self] opacity in
            guard let self else {
                return
            }

            photoBackgroundOverlayOpacity = opacity
            photoBackgroundOverlayView.backgroundColor = UIColor.black.withAlphaComponent(opacity)
        }
        viewController.modalPresentationStyle = .overFullScreen
        viewController.modalTransitionStyle = .crossDissolve
        present(viewController, animated: true)
    }

    @objc private func presentRouteColorPicker() {
        guard let selectedWorkoutID else {
            Toast.show(AppLocalization.text(.heatmapShareSelectRouteForColor), in: view)
            return
        }

        let colorPickerViewController = RouteShareColorPickerViewController(
            initialColor: routeColorsByWorkoutID[selectedWorkoutID] ?? .white,
            applyToAllInitiallyOn: applyColorToAllRoutes,
            onApplyToAllChanged: { [weak self] isOn in
                guard let self else {
                    return
                }

                applyColorToAllRoutes = isOn
                if isOn {
                    applyRouteColor(routeColorsByWorkoutID[selectedWorkoutID] ?? .white, toAllRoutes: true)
                } else {
                    routeColorsByWorkoutID.removeAll()
                }
                routeCollectionView.reloadData()
            }
        ) { [weak self] color in
            guard let self else {
                return
            }

            applyRouteColor(color, toAllRoutes: applyColorToAllRoutes, selectedWorkoutID: selectedWorkoutID)
        }
        colorPickerViewController.modalPresentationStyle = .overFullScreen
        colorPickerViewController.modalTransitionStyle = .coverVertical
        present(colorPickerViewController, animated: true)
    }

    private func applyRouteColor(
        _ color: UIColor,
        toAllRoutes: Bool,
        selectedWorkoutID: String? = nil
    ) {
        if toAllRoutes {
            routePreviewItems.forEach { routeColorsByWorkoutID[$0.id] = color }
        } else if let selectedWorkoutID {
            routeColorsByWorkoutID[selectedWorkoutID] = color
        }
        routeCollectionView.reloadData()
    }

    @objc private func savePreviewImage() {
        let previouslySelectedWorkoutID = selectedWorkoutID
        selectedWorkoutID = nil
        routeCollectionView.reloadData()
        configureToolButtons()
        showExportLoading()
        view.layoutIfNeeded()
        previewView.layoutIfNeeded()

        let image = RouteSharePreviewRenderer.image(
            from: previewView,
            setSelectionChromeHidden: { _ in },
            restoreSelection: {}
        )

        guard allowsPhotoLibrarySaving else {
            hideExportLoading()
            selectedWorkoutID = previouslySelectedWorkoutID.flatMap { id in
                displayedRouteItems.contains { $0.id == id } ? id : nil
            }
            routeCollectionView.reloadData()
            configureToolButtons()
            presentPreviewImageShareSheet(image)
            return
        }

        RouteSharePhotoLibrarySaver.saveImage(image) { [weak self] result in
            guard let self else {
                return
            }

            hideExportLoading()
            selectedWorkoutID = previouslySelectedWorkoutID.flatMap { id in
                self.displayedRouteItems.contains { $0.id == id } ? id : nil
            }
            routeCollectionView.reloadData()
            configureToolButtons()

            switch result {
            case .success:
                showSavedToPhotosAlert()
            case .failure(let error):
                showAlert(title: AppLocalization.text(.share), message: detailedErrorMessage(error))
            }
        }
    }

    private func presentPreviewImageShareSheet(_ image: UIImage) {
        let activityViewController = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activityViewController.popoverPresentationController?.barButtonItem = exportBarButtonItem
        present(activityViewController, animated: true)
    }

    private func showExportLoading() {
        exportBarButtonItem.isEnabled = false
        resetBarButtonItem.isEnabled = false
        exportLoadingView.show(text: AppLocalization.text(.photoSaving), in: view)
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
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.openPhotos), style: .default) { _ in
            guard let url = URL(string: "photos-redirect://") else {
                return
            }
            UIApplication.shared.open(url)
        })
        present(alertController, animated: true)
    }

    private func showAlert(title: String, message: String? = nil) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .default))
        present(alertController, animated: true)
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

    @objc private func handleRouteLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began else {
            return
        }

        let location = gestureRecognizer.location(in: routeCollectionView)
        guard let indexPath = routeCollectionView.indexPathForItem(at: location),
              displayedRouteItems.indices.contains(indexPath.item) else {
            return
        }

        let item = displayedRouteItems[indexPath.item]
        let alertController = UIAlertController(
            title: AppLocalization.text(.delete),
            message: item.dateText,
            preferredStyle: .actionSheet
        )
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.cancel), style: .cancel))
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.delete), style: .destructive) { [weak self] _ in
            guard let self else {
                return
            }

            removedWorkoutIDs.insert(item.id)
            routeColorsByWorkoutID.removeValue(forKey: item.id)
            if selectedWorkoutID == item.id {
                selectedWorkoutID = nil
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            reloadPreviewContent()
        })
        if let cell = routeCollectionView.cellForItem(at: indexPath) {
            alertController.popoverPresentationController?.sourceView = cell
            alertController.popoverPresentationController?.sourceRect = cell.bounds
        }
        present(alertController, animated: true)
    }

    private static func routeCoordinates(for workout: TrackedWorkout) -> [CLLocationCoordinate2D] {
        let sourceCoordinates = workout.fullCoordinates?.isEmpty == false
            ? workout.fullCoordinates ?? workout.coordinates
            : workout.coordinates
        return sourceCoordinates.map(\.coordinate).filter(CLLocationCoordinate2DIsValid)
    }

    private static func preparedWorkoutBatch(
        from workouts: [TrackedWorkout],
        selectedFilters: Set<HeatmapFilter>,
        selectedYear: Int?
    ) -> PreparedWorkoutBatch {
        PreparedWorkoutBatch(
            routeItems: routePreviewItems(
                for: workouts,
                selectedFilters: selectedFilters,
                selectedYear: selectedYear
            ),
            timelineItems: timelineItems(
                for: workouts,
                selectedFilters: selectedFilters,
                selectedYear: selectedYear
            )
        )
    }

    private static func routePreviewItems(
        _ workouts: [TrackedWorkout],
        selectedFilters: Set<HeatmapFilter>,
        selectedYear: Int?
    ) -> [RoutePreviewItem] {
        workouts
            .compactMap { workout -> RoutePreviewItem? in
                guard isWorkoutIncluded(
                    workout,
                    selectedFilters: selectedFilters,
                    selectedYear: selectedYear
                ) else {
                    return nil
                }

                let coordinates = sampledRouteCoordinates(routeCoordinates(for: workout))
                guard let routePath = routePreviewPath(for: coordinates) else {
                    return nil
                }

                return RoutePreviewItem(
                    id: workout.id,
                    startDate: workout.startDate,
                    dateText: workout.dateText,
                    distanceMeters: workout.distanceMeters,
                    durationSeconds: workout.durationSeconds ?? 0,
                    routePath: routePath
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func timelineItems(
        for workouts: [TrackedWorkout],
        selectedFilters: Set<HeatmapFilter>,
        selectedYear: Int?
    ) -> [TimelineWorkoutItem] {
        workouts
            .compactMap { workout -> TimelineWorkoutItem? in
                guard isWorkoutIncluded(
                    workout,
                    selectedFilters: selectedFilters,
                    selectedYear: selectedYear
                ) else {
                    return nil
                }

                return TimelineWorkoutItem(id: workout.id, startDate: workout.startDate)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private static func isWorkoutIncluded(
        _ workout: TrackedWorkout,
        selectedFilters: Set<HeatmapFilter>,
        selectedYear: Int?
    ) -> Bool {
        selectedFilters.contains { filter in
            filter.includes(workout.sportKind)
        }
        && (selectedYear.map {
            Calendar.current.component(.year, from: workout.startDate) == $0
        } ?? true)
    }

    private static func routePreviewItems(
        for workouts: [TrackedWorkout],
        selectedFilters: Set<HeatmapFilter>,
        selectedYear: Int?
    ) -> [RoutePreviewItem] {
        routePreviewItems(
            workouts,
            selectedFilters: selectedFilters,
            selectedYear: selectedYear
        )
    }

    private static func sampledRouteCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        maximumCount: Int = 96
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maximumCount, maximumCount > 2 else {
            return coordinates
        }

        let step = Double(coordinates.count - 1) / Double(maximumCount - 1)
        return (0..<maximumCount).map { index in
            coordinates[min(Int((Double(index) * step).rounded()), coordinates.count - 1)]
        }
    }

    private static func routePreviewPath(for coordinates: [CLLocationCoordinate2D]) -> RoutePreviewPath? {
        guard let firstCoordinate = coordinates.first else {
            return nil
        }

        guard coordinates.count > 1 else {
            return RoutePreviewPath(points: [CGPoint(x: 0.5, y: 0.5)], aspectRatio: 1)
        }

        let bounds = coordinates.dropFirst().reduce(
            (
                minLongitude: firstCoordinate.longitude,
                minLatitude: firstCoordinate.latitude,
                maxLongitude: firstCoordinate.longitude,
                maxLatitude: firstCoordinate.latitude
            )
        ) { partial, coordinate in
            (
                minLongitude: min(partial.minLongitude, coordinate.longitude),
                minLatitude: min(partial.minLatitude, coordinate.latitude),
                maxLongitude: max(partial.maxLongitude, coordinate.longitude),
                maxLatitude: max(partial.maxLatitude, coordinate.latitude)
            )
        }

        let longitudeSpan = max(bounds.maxLongitude - bounds.minLongitude, 0.000_001)
        let latitudeSpan = max(bounds.maxLatitude - bounds.minLatitude, 0.000_001)
        let points = coordinates.map { coordinate in
            CGPoint(
                x: CGFloat((coordinate.longitude - bounds.minLongitude) / longitudeSpan),
                y: CGFloat((coordinate.latitude - bounds.minLatitude) / latitudeSpan)
            )
        }
        return RoutePreviewPath(
            points: points,
            aspectRatio: CGFloat(longitudeSpan / latitudeSpan)
        )
    }

}

extension WorkoutRouteHeatmapShareViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard !results.isEmpty else {
            pendingPhotoSelectionID = nil
            return
        }

        let selectionID = pendingPhotoSelectionID
        var images = Array<UIImage?>(repeating: nil, count: results.count)
        let dispatchGroup = DispatchGroup()

        for (index, result) in results.enumerated() where result.itemProvider.canLoadObject(ofClass: UIImage.self) {
            dispatchGroup.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                defer { dispatchGroup.leave() }
                guard let image = object as? UIImage else {
                    return
                }
                images[index] = Self.downsampledBackgroundImage(image)
            }
        }

        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self,
                  pendingPhotoSelectionID == selectionID else {
                return
            }

            pendingPhotoSelectionID = nil
            let selectedImages = images.compactMap { $0 }
            guard !selectedImages.isEmpty else {
                return
            }

            photoBackgroundImages = selectedImages
            photoBackgroundOverlayOpacity = max(photoBackgroundOverlayOpacity, 0.28)
            isPhotoBackgroundAdjustmentEnabled = false
            resetPhotoBackgroundAdjustment()
            updatePhotoBackground()
            Toast.show(AppLocalization.text(.photoBackgroundAdjustmentHint), in: view)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private static func downsampledBackgroundImage(_ image: UIImage, maximumPixelWidth: CGFloat = 1_600) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        guard pixelWidth > maximumPixelWidth,
              image.size.width > 0,
              image.size.height > 0 else {
            return image
        }

        let targetSize = CGSize(
            width: maximumPixelWidth,
            height: maximumPixelWidth * image.size.height / image.size.width
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

extension WorkoutRouteHeatmapShareViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === previewBlankTapGesture
            || gestureRecognizer === photoBackgroundDoubleTapGesture else {
            return true
        }

        if gestureRecognizer === photoBackgroundDoubleTapGesture,
           !hasPhotoBackground {
            return false
        }

        let routeLocation = touch.location(in: routeCollectionView)
        if routeCollectionView.bounds.contains(routeLocation),
           routeCollectionView.indexPathForItem(at: routeLocation) != nil {
            return false
        }

        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === photoBackgroundPanGesture
            || gestureRecognizer === photoBackgroundPinchGesture {
            return hasPhotoBackground && isPhotoBackgroundAdjustmentEnabled
        }

        if gestureRecognizer === photoBackgroundDoubleTapGesture {
            return hasPhotoBackground
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        isPhotoBackgroundTransformGesture(gestureRecognizer)
            && isPhotoBackgroundTransformGesture(otherGestureRecognizer)
    }

    private func isPhotoBackgroundTransformGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === photoBackgroundPanGesture
            || gestureRecognizer === photoBackgroundPinchGesture
    }
}

extension WorkoutRouteHeatmapShareViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView === dataBrowserCollectionView {
            return dataBrowserItems.count
        }

        return displayedRouteItems.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        if collectionView === dataBrowserCollectionView {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: HeatmapShareDataScopeCell.reuseIdentifier,
                for: indexPath
            ) as? HeatmapShareDataScopeCell,
            dataBrowserItems.indices.contains(indexPath.item) else {
                return UICollectionViewCell()
            }
            let item = dataBrowserItems[indexPath.item]

            cell.configure(
                title: AppLocalization.text(item.titleKey),
                isSelected: item.scope.map { $0 == selectedScope } ?? hasPhotoBackground
            )
            return cell
        }

        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HeatmapShareRouteCell.reuseIdentifier,
            for: indexPath
        ) as? HeatmapShareRouteCell,
        displayedRouteItems.indices.contains(indexPath.item) else {
            return UICollectionViewCell()
        }

        let item = displayedRouteItems[indexPath.item]
        cell.configure(
            routePath: item.routePath,
            routeColor: routeColorsByWorkoutID[item.id] ?? .white,
            isSelected: item.id == selectedWorkoutID
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === dataBrowserCollectionView {
            guard dataBrowserItems.indices.contains(indexPath.item) else {
                return
            }
            let item = dataBrowserItems[indexPath.item]

            guard let scope = item.scope else {
                presentPhotoBackgroundPicker()
                return
            }

            if scope == selectedScope {
                if let cell = collectionView.cellForItem(at: indexPath) {
                    presentTimeOptions(for: scope, sourceView: cell)
                }
                return
            }

            selectedScope = scope
            selectedWorkoutID = nil
            UISelectionFeedbackGenerator().selectionChanged()
            reloadPreviewContent()
            return
        }

        guard displayedRouteItems.indices.contains(indexPath.item) else {
            return
        }

        isPhotoBackgroundAdjustmentEnabled = false
        selectedWorkoutID = displayedRouteItems[indexPath.item].id
        UISelectionFeedbackGenerator().selectionChanged()
        routeCollectionView.reloadData()
        configureToolButtons()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        if collectionView === dataBrowserCollectionView {
            return CGSize(width: 78, height: 52)
        }

        return CGSize(width: routeCellSide, height: routeCellSide)
    }
}

private final class HeatmapShareDataScopeCell: UICollectionViewCell {
    static let reuseIdentifier = "HeatmapShareDataScopeCell"

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(title: String, isSelected: Bool) {
        titleLabel.text = title
        contentView.backgroundColor = isSelected ? AppColors.movinnGreen : AppColors.toolbarBackground
        titleLabel.textColor = isSelected ? .black : AppColors.solidForeground
        contentView.layer.borderWidth = isSelected ? 0 : 1
        contentView.layer.borderColor = AppColors.foreground(alpha: 0.08).cgColor
    }

    private func configureViews() {
        contentView.layer.cornerRadius = 14
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textAlignment = .center

        contentView.addSubview(titleLabel)

        titleLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(8)
        }
    }
}

private struct HeatmapShareTimeMenuOption {
    let title: String
    let isSelected: Bool
    let textAlignment: NSTextAlignment
    let action: () -> Void

    init(
        title: String,
        isSelected: Bool,
        textAlignment: NSTextAlignment = .center,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.textAlignment = textAlignment
        self.action = action
    }
}

private final class HeatmapShareTimeOptionsMenuView: UIControl {
    var onDismiss: (() -> Void)?

    private enum Layout {
        static let horizontalMargin: CGFloat = 12
        static let anchorSpacing: CGFloat = 8
        static let minWidth: CGFloat = 104
        static let maxWidth: CGFloat = 306
        static let horizontalTextPadding: CGFloat = 28
        static let rowHeight: CGFloat = 34
        static let verticalInset: CGFloat = 6
        static let maxVisibleRows: CGFloat = 6
        static let cornerRadius: CGFloat = 14
    }

    private let options: [HeatmapShareTimeMenuOption]
    private let panelView = UIView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var sourceRect: CGRect = .zero
    private var didScrollToSelectedOption = false

    init(options: [HeatmapShareTimeMenuOption]) {
        self.options = options
        super.init(frame: .zero)
        configureViews()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (menuView: Self, _) in
            menuView.updateColors()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutPanel()
    }

    func present(in containerView: UIView, sourceRect: CGRect) {
        self.sourceRect = sourceRect
        frame = containerView.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        alpha = 0
        containerView.addSubview(self)
        setNeedsLayout()
        layoutIfNeeded()
        scrollToSelectedOptionIfNeeded()
        tableView.flashScrollIndicators()

        panelView.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.alpha = 1
            self.panelView.transform = .identity
        }
    }

    func dismiss(animated: Bool) {
        let finish = {
            self.removeFromSuperview()
            self.onDismiss?()
        }

        guard animated else {
            finish()
            return
        }

        UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.alpha = 0
            self.panelView.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        } completion: { _ in
            finish()
        }
    }

    private func configureViews() {
        backgroundColor = .clear
        addTarget(self, action: #selector(handleOutsideTap), for: .touchUpInside)

        panelView.layer.cornerRadius = Layout.cornerRadius
        panelView.layer.cornerCurve = .continuous
        panelView.layer.masksToBounds = false
        panelView.layer.borderWidth = 1
        panelView.layer.shadowColor = UIColor.black.cgColor
        panelView.layer.shadowOpacity = 0.18
        panelView.layer.shadowRadius = 16
        panelView.layer.shadowOffset = CGSize(width: 0, height: 8)

        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = Layout.rowHeight
        tableView.estimatedRowHeight = Layout.rowHeight
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = true
        tableView.verticalScrollIndicatorInsets = UIEdgeInsets(
            top: Layout.verticalInset,
            left: 0,
            bottom: Layout.verticalInset,
            right: 2
        )
        tableView.contentInset = UIEdgeInsets(
            top: Layout.verticalInset,
            left: 0,
            bottom: Layout.verticalInset,
            right: 0
        )
        tableView.register(
            HeatmapShareTimeOptionCell.self,
            forCellReuseIdentifier: HeatmapShareTimeOptionCell.reuseIdentifier
        )

        addSubview(panelView)
        panelView.addSubview(tableView)
        updateColors()
    }

    private func updateColors() {
        panelView.backgroundColor = AppColors.solidBackground
        panelView.layer.borderColor = AppColors.foreground(alpha: 0.10)
            .resolvedColor(with: traitCollection)
            .cgColor
        tableView.indicatorStyle = traitCollection.userInterfaceStyle == .dark ? .white : .black
        tableView.reloadData()
    }

    private func layoutPanel() {
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }

        let menuWidth = preferredMenuWidth()
        let menuHeight = preferredMenuHeight()
        let boundsRect = bounds.insetBy(
            dx: Layout.horizontalMargin,
            dy: Layout.horizontalMargin
        )
        let safeTop = safeAreaInsets.top + Layout.horizontalMargin
        let safeBottom = bounds.height - safeAreaInsets.bottom - Layout.horizontalMargin
        let minX = boundsRect.minX
        let maxX = boundsRect.maxX - menuWidth
        let originX = min(max(sourceRect.midX - menuWidth / 2, minX), maxX)
        let spaceAbove = sourceRect.minY - safeTop - Layout.anchorSpacing
        let spaceBelow = safeBottom - sourceRect.maxY - Layout.anchorSpacing
        let originY: CGFloat

        if spaceAbove >= menuHeight || spaceAbove >= spaceBelow {
            originY = max(sourceRect.minY - menuHeight - Layout.anchorSpacing, safeTop)
        } else {
            originY = min(sourceRect.maxY + Layout.anchorSpacing, safeBottom - menuHeight)
        }

        panelView.frame = CGRect(
            x: originX,
            y: originY,
            width: menuWidth,
            height: menuHeight
        )
        panelView.layer.shadowPath = UIBezierPath(
            roundedRect: panelView.bounds,
            cornerRadius: Layout.cornerRadius
        ).cgPath
        tableView.frame = panelView.bounds
        tableView.isScrollEnabled = CGFloat(options.count) > Layout.maxVisibleRows
        tableView.layoutIfNeeded()
    }

    private func preferredMenuWidth() -> CGFloat {
        let font = HeatmapShareTimeOptionCell.titleFont
        let maxTitleWidth = options
            .map { ($0.title as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return min(
            max(maxTitleWidth + Layout.horizontalTextPadding, Layout.minWidth),
            Layout.maxWidth
        )
    }

    private func preferredMenuHeight() -> CGFloat {
        let visibleRows = min(CGFloat(options.count), Layout.maxVisibleRows)
        return visibleRows * Layout.rowHeight + Layout.verticalInset * 2
    }

    private func scrollToSelectedOptionIfNeeded() {
        guard !didScrollToSelectedOption,
              let selectedIndex = options.firstIndex(where: \.isSelected),
              options.count > Int(Layout.maxVisibleRows) else {
            return
        }

        didScrollToSelectedOption = true
        tableView.scrollToRow(
            at: IndexPath(row: selectedIndex, section: 0),
            at: .middle,
            animated: false
        )
    }

    @objc private func handleOutsideTap() {
        dismiss(animated: true)
    }
}

extension HeatmapShareTimeOptionsMenuView: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: HeatmapShareTimeOptionCell.reuseIdentifier,
            for: indexPath
        ) as? HeatmapShareTimeOptionCell,
        options.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }

        cell.configure(option: options[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard options.indices.contains(indexPath.row) else {
            return
        }

        let action = options[indexPath.row].action
        dismiss(animated: true)
        action()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {}
}

private final class HeatmapShareTimeOptionCell: UITableViewCell {
    static let reuseIdentifier = "HeatmapShareTimeOptionCell"
    static let titleFont = UIFont.systemFont(ofSize: 13, weight: .semibold)

    private let titleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        titleLabel.alpha = highlighted ? 0.52 : 1
    }

    func configure(option: HeatmapShareTimeMenuOption) {
        titleLabel.text = option.title
        titleLabel.textColor = option.isSelected ? AppColors.movinnGreen : AppColors.solidForeground
        titleLabel.textAlignment = option.textAlignment
        titleLabel.lineBreakMode = option.textAlignment == .left ? .byTruncatingTail : .byTruncatingMiddle
    }

    private func configureViews() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectedBackgroundView = UIView()
        selectedBackgroundView?.backgroundColor = .clear
        selectionStyle = .none

        titleLabel.font = Self.titleFont
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingMiddle

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(12)
            make.centerY.equalToSuperview()
        }
    }
}

private final class HeatmapSharePhotoBackgroundView: UIView {
    var images: [UIImage] = [] {
        didSet { setNeedsDisplay() }
    }
    var contentScale: CGFloat = 1 {
        didSet { setNeedsDisplay() }
    }
    var contentTranslation: CGPoint = .zero {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    override func draw(_ rect: CGRect) {
        guard !images.isEmpty,
              rect.width > 0,
              rect.height > 0 else {
            UIColor.black.setFill()
            UIRectFill(rect)
            return
        }

        UIColor.black.setFill()
        UIRectFill(rect)

        let resolvedScale = max(contentScale, 1)
        let drawWidth = rect.width * resolvedScale
        let drawX = rect.midX - drawWidth / 2 + contentTranslation.x
        let imageHeights = images.map { image in
            let ratio = image.size.width > 0 ? image.size.height / image.size.width : 4 / 3
            return max(drawWidth * ratio, 1)
        }
        let cycleHeight = max(imageHeights.reduce(0, +), 1)
        var currentY = contentTranslation.y
        while currentY > 0 {
            currentY -= cycleHeight
        }
        while currentY + cycleHeight < 0 {
            currentY += cycleHeight
        }

        var imageIndex = 0
        let maxDrawCount = 240
        while currentY < rect.height, imageIndex < maxDrawCount {
            let image = images[imageIndex % images.count]
            let imageHeight = imageHeights[imageIndex % imageHeights.count]
            image.draw(in: CGRect(x: drawX, y: currentY, width: drawWidth, height: imageHeight))
            currentY += imageHeight
            imageIndex += 1
        }
    }
}

private final class HeatmapShareMaskOpacityViewController: UIViewController {
    private enum Layout {
        static let panelHeight: CGFloat = 148
        static let panelCornerRadius: CGFloat = 22
    }

    private let dimmingView = UIControl()
    private let panelView = UIView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let slider = UISlider()
    private let onOpacityChanged: (CGFloat) -> Void

    init(initialOpacity: CGFloat, onOpacityChanged: @escaping (CGFloat) -> Void) {
        self.onOpacityChanged = onOpacityChanged
        super.init(nibName: nil, bundle: nil)
        slider.value = Float(min(max(initialOpacity, 0), 0.85))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        updateValueLabel()
    }

    private func configureViews() {
        view.backgroundColor = .clear

        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        dimmingView.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)

        panelView.backgroundColor = AppColors.solidBackground
        panelView.layer.cornerRadius = Layout.panelCornerRadius
        panelView.layer.cornerCurve = .continuous
        panelView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        titleLabel.text = AppLocalization.text(.heatmapShareMaskOpacity)
        titleLabel.textColor = AppColors.solidForeground
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)

        valueLabel.textColor = AppColors.foreground(alpha: 0.58)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.textAlignment = .left

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = AppColors.solidForeground
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)

        slider.minimumValue = 0
        slider.maximumValue = 0.85
        slider.minimumTrackTintColor = AppColors.movinnGreen
        slider.maximumTrackTintColor = AppColors.foreground(alpha: 0.16)
        slider.thumbTintColor = AppColors.movinnGreen
        slider.addTarget(self, action: #selector(handleSliderChanged), for: .valueChanged)

        view.addSubview(dimmingView)
        view.addSubview(panelView)
        panelView.addSubview(titleLabel)
        panelView.addSubview(valueLabel)
        panelView.addSubview(closeButton)
        panelView.addSubview(slider)

        dimmingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        panelView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(Layout.panelHeight)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(22)
            make.leading.equalToSuperview().offset(24)
        }
        valueLabel.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.leading.equalTo(titleLabel.snp.trailing).offset(8)
            make.trailing.lessThanOrEqualTo(closeButton.snp.leading).offset(-12)
        }
        closeButton.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.trailing.equalToSuperview().inset(18)
            make.size.equalTo(34)
        }
        slider.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(24)
        }
    }

    private func updateValueLabel() {
        valueLabel.text = "\(Int(round(slider.value * 100)))%"
    }

    @objc private func handleSliderChanged() {
        updateValueLabel()
        onOpacityChanged(CGFloat(slider.value))
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
}

private final class HeatmapShareRouteCell: UICollectionViewCell {
    static let reuseIdentifier = "HeatmapShareRouteCell"

    private let pathView = HeatmapShareRoutePathView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pathView.routePath = nil
    }

    func configure(
        routePath: WorkoutRouteHeatmapShareViewController.RoutePreviewPath,
        routeColor: UIColor,
        isSelected: Bool
    ) {
        pathView.routePath = routePath
        pathView.strokeColor = routeColor
        contentView.layer.borderWidth = isSelected ? 1.5 : 0
        contentView.layer.borderColor = AppColors.movinnGreen.cgColor
    }

    private func configureViews() {
        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 8
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true

        contentView.addSubview(pathView)

        pathView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(4)
        }
    }
}

private final class HeatmapShareRoutePathView: UIView {
    var routePath: WorkoutRouteHeatmapShareViewController.RoutePreviewPath? {
        didSet { setNeedsDisplay() }
    }
    var strokeColor: UIColor = .white {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        contentMode = .redraw
    }

    override func draw(_ rect: CGRect) {
        guard let routePath,
              !routePath.points.isEmpty else {
            return
        }

        let targetRect = rect.insetBy(dx: 5, dy: 5)
        guard routePath.points.count > 1 else {
            strokeColor.setFill()
            let point = CGPoint(x: targetRect.midX, y: targetRect.midY)
            UIBezierPath(ovalIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)).fill()
            return
        }

        let routeAspectRatio = max(routePath.aspectRatio, 0.01)
        let rectAspectRatio = targetRect.width / max(targetRect.height, 1)
        let fittedRect: CGRect
        if routeAspectRatio > rectAspectRatio {
            let height = targetRect.width / routeAspectRatio
            fittedRect = CGRect(
                x: targetRect.minX,
                y: targetRect.midY - height / 2,
                width: targetRect.width,
                height: height
            )
        } else {
            let width = targetRect.height * routeAspectRatio
            fittedRect = CGRect(
                x: targetRect.midX - width / 2,
                y: targetRect.minY,
                width: width,
                height: targetRect.height
            )
        }

        let path = UIBezierPath()
        for (index, normalizedPoint) in routePath.points.enumerated() {
            let point = CGPoint(
                x: fittedRect.minX + normalizedPoint.x * fittedRect.width,
                y: fittedRect.maxY - normalizedPoint.y * fittedRect.height
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        strokeColor.setStroke()
        path.lineWidth = max(1.45, min(rect.width, rect.height) * 0.045)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}
