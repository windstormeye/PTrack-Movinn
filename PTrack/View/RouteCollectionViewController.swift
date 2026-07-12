//
//  RouteCollectionViewController.swift
//  PTrack
//
//  Created by Codex on 2026/6/17.
//

import MapKit
import SnapKit
import UIKit
import UniformTypeIdentifiers

private enum RouteCollectionSectionKind {
    case imported
    case merged
}

private struct RouteCollectionSection {
    let kind: RouteCollectionSectionKind
    let title: String
    let routes: [TrackedWorkout]
}

private struct RouteCollectionICloudSyncFooterConfiguration {
    enum State {
        case syncing
        case complete
        case error
    }

    let text: String
    let state: State
}

final class RouteCollectionViewController: UIViewController {
    private let navigationBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let navigationBackgroundHeight: CGFloat = 124
    private let store = RouteCollectionStore()
    private let navigationTitleStackView = UIStackView()
    private let navigationTitleLabel = UILabel()
    private let navigationSubtitleLabel = UILabel()
    private let emptyLabel = UILabel()
    private let routeGridView = WorkoutRouteGridView()
    private let iCloudSyncFooterView = RouteCollectionICloudSyncFooterView()
    private var collectionView: UICollectionView!
    private var routes: [TrackedWorkout] = []
    private var routeSections: [RouteCollectionSection] = []
    private var loadingIDs: [UUID] = []
    private var iCloudSyncFooterHeightConstraint: Constraint?
    private var isICloudSyncFooterVisible = false

    private let iCloudSyncFooterContentHeight: CGFloat = 48

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationItem()
        configureCollectionView()
        configureEmptyLabel()
        configureNavigationBackgroundView()
        registerObservers()
        registerTraitChangeHandler()
        reloadRoutes(importsPendingSharedRoutes: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        configureNavigationBar()
        reloadRoutes(importsPendingSharedRoutes: true)
        RouteCollectionCloudSyncCoordinator.shared.startIfEnabled(store: store)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateICloudSyncFooterHeight()
    }

    private func configureNavigationItem() {
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        edgesForExtendedLayout = [.top, .bottom]
        configureNavigationTitleView()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.down"),
            style: .plain,
            target: self,
            action: #selector(presentGPXPicker)
        )
        updateLocalizedText()
    }

    private func configureNavigationTitleView() {
        navigationTitleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        navigationTitleLabel.textColor = .label
        navigationTitleLabel.textAlignment = .center
        navigationTitleLabel.adjustsFontSizeToFitWidth = true
        navigationTitleLabel.minimumScaleFactor = 0.86
        navigationTitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        navigationSubtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        navigationSubtitleLabel.textColor = .secondaryLabel
        navigationSubtitleLabel.textAlignment = .center
        navigationSubtitleLabel.adjustsFontSizeToFitWidth = true
        navigationSubtitleLabel.minimumScaleFactor = 0.82
        navigationSubtitleLabel.isHidden = true
        navigationSubtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        navigationTitleStackView.axis = .vertical
        navigationTitleStackView.alignment = .center
        navigationTitleStackView.spacing = 1
        navigationTitleStackView.isUserInteractionEnabled = false
        navigationTitleStackView.addArrangedSubview(navigationTitleLabel)
        navigationTitleStackView.addArrangedSubview(navigationSubtitleLabel)

        navigationItem.titleView = navigationTitleStackView
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
    }

    private func configureCollectionView() {
        routeGridView.configureLayout(
            columns: 3,
            itemSpacing: 12,
            lineSpacing: 2,
            sectionInset: UIEdgeInsets(top: 12, left: 12, bottom: 16, right: 12),
            minimumColumns: 2,
            maximumColumns: 6
        )
        routeGridView.configureSectionHeaders(height: 32)
        routeGridView.numberOfSectionsProvider = { [weak self] in
            guard let self else {
                return 0
            }

            return self.routeSections.count
        }
        routeGridView.numberOfItemsInSectionProvider = { [weak self] section in
            self?.numberOfItems(in: section) ?? 0
        }
        routeGridView.sectionTitleProvider = { [weak self] section in
            guard let self, section >= 0, section < self.routeSections.count else {
                return nil
            }

            return self.routeSections[section].title
        }
        routeGridView.sectionItemProvider = { [weak self] indexPath in
            self?.gridItem(at: indexPath)
        }
        routeGridView.onSelectRoute = { [weak self] workout, _, _ in
            self?.showRouteDetail(workout)
        }
        routeGridView.contextMenuConfigurationProvider = { [weak self] workout, _ in
            self?.makeRouteContextMenuConfiguration(for: workout)
        }

        collectionView = routeGridView.collectionView
        collectionView.contentInset = UIEdgeInsets(
            top: navigationBackgroundHeight,
            left: 0,
            bottom: 28,
            right: 0
        )
        collectionView.scrollIndicatorInsets = collectionView.contentInset

        iCloudSyncFooterView.backgroundColor = .systemBackground
        iCloudSyncFooterView.configure(with: nil)

        view.addSubview(routeGridView)
        view.addSubview(iCloudSyncFooterView)

        routeGridView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(iCloudSyncFooterView.snp.top)
        }

        iCloudSyncFooterView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            iCloudSyncFooterHeightConstraint = make.height.equalTo(0).constraint
        }
    }

    private func configureEmptyLabel() {
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        view.addSubview(emptyLabel)

        emptyLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(view.safeAreaLayoutGuide.snp.centerY).offset(-24)
            make.leading.greaterThanOrEqualToSuperview().offset(24)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
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

    private func updateNavigationBackgroundColors() {
        navigationBackgroundView.effect = nil
        navigationBackgroundView.contentView.backgroundColor = .clear
        navigationBackgroundView.layer.mask = nil
    }

    private func registerTraitChangeHandler() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (viewController: Self, _) in
            viewController.updateNavigationBackgroundColors()
        }
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLanguageDidChange),
            name: AppLanguageStore.languageDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteCollectionDidChange),
            name: RouteCollectionStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePendingSharedRoutesDidChange),
            name: SharedRouteImportInbox.pendingRoutesDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleICloudSyncProgressDidChange),
            name: RouteCollectionCloudSyncCoordinator.progressDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleICloudSyncSettingDidChange),
            name: RouteCollectionCloudSyncSettings.didChangeNotification,
            object: nil
        )
    }

    @objc private func handleLanguageDidChange() {
        updateLocalizedText()
    }

    @objc private func handleRouteCollectionDidChange() {
        reloadRoutes(importsPendingSharedRoutes: false)
    }

    @objc private func handlePendingSharedRoutesDidChange() {
        reloadRoutes(importsPendingSharedRoutes: true)
    }

    @objc private func handleICloudSyncProgressDidChange() {
        updateICloudSyncSubtitle()
    }

    @objc private func handleICloudSyncSettingDidChange() {
        updateICloudSyncSubtitle()
    }

    private func updateLocalizedText() {
        let routeCollectionTitle = AppLocalization.text(.routeCollectionMenuTitle)
        title = routeCollectionTitle
        navigationTitleLabel.text = routeCollectionTitle
        emptyLabel.text = AppLocalization.text(.routeCollectionEmptyMessage)
        rebuildRouteSections()
        updateICloudSyncSubtitle()
        collectionView?.reloadData()
    }

    private func updateICloudSyncSubtitle() {
        let progress = RouteCollectionCloudSyncCoordinator.shared.currentProgress
        guard progress.isEnabled else {
            navigationSubtitleLabel.text = nil
            navigationSubtitleLabel.isHidden = true
            setICloudSyncFooter(configuration: nil)
            navigationTitleStackView.sizeToFit()
            return
        }

        navigationSubtitleLabel.isHidden = false
        navigationSubtitleLabel.text = AppLocalization.text(.iCloudRouteSyncAlreadyEnabled)
        navigationSubtitleLabel.textColor = AppColors.movinnGreen

        let remainingCount = max(progress.totalCount - progress.completedCount, 0)
        let footerConfiguration: RouteCollectionICloudSyncFooterConfiguration
        if progress.errorDescription != nil {
            footerConfiguration = RouteCollectionICloudSyncFooterConfiguration(
                text: String(
                    format: AppLocalization.text(.routeCollectionICloudSyncFooterErrorFormat),
                    remainingCount,
                    progress.totalCount
                ),
                state: .error
            )
        } else if progress.isSynchronizing || remainingCount > 0 {
            let footerText: String
            if progress.totalCount == 0 {
                footerText = AppLocalization.text(.routeCollectionICloudSyncFooterPreparing)
            } else {
                footerText = String(
                    format: AppLocalization.text(.routeCollectionICloudSyncFooterPendingFormat),
                    remainingCount,
                    progress.totalCount
                )
            }
            footerConfiguration = RouteCollectionICloudSyncFooterConfiguration(
                text: footerText,
                state: .syncing
            )
        } else {
            footerConfiguration = RouteCollectionICloudSyncFooterConfiguration(
                text: String(
                    format: AppLocalization.text(.routeCollectionICloudSyncFooterCompleteFormat),
                    progress.totalCount
                ),
                state: .complete
            )
        }

        setICloudSyncFooter(configuration: footerConfiguration)
        navigationTitleStackView.sizeToFit()
    }

    private func setICloudSyncFooter(configuration: RouteCollectionICloudSyncFooterConfiguration?) {
        isICloudSyncFooterVisible = configuration != nil
        iCloudSyncFooterView.configure(with: configuration)
        updateICloudSyncFooterHeight()
    }

    private func updateICloudSyncFooterHeight() {
        let height = isICloudSyncFooterVisible
            ? iCloudSyncFooterContentHeight + view.safeAreaInsets.bottom
            : 0
        iCloudSyncFooterHeightConstraint?.update(offset: height)
    }

    private func reloadRoutes(importsPendingSharedRoutes: Bool) {
        if importsPendingSharedRoutes {
            let importedRoutes = SharedRouteImportInbox.importPendingRoutes(store: store)
            if !importedRoutes.isEmpty {
                SharedRouteImportInbox.markRoutePromptSeen()
            }
        }
        routes = store.load()
        rebuildRouteSections()
        collectionView?.reloadData()
        updateEmptyState()
        updateICloudSyncSubtitle()
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !routeSections.isEmpty
    }

    private func rebuildRouteSections() {
        let importedRoutes = routes.filter { !$0.isMergedRouteCollectionSource }
        let mergedRoutes = routes.filter(\.isMergedRouteCollectionSource)
        var sections: [RouteCollectionSection] = []

        if !loadingIDs.isEmpty || !importedRoutes.isEmpty {
            sections.append(RouteCollectionSection(
                kind: .imported,
                title: AppLocalization.text(.routeCollectionImportSectionTitle),
                routes: importedRoutes
            ))
        }

        if !mergedRoutes.isEmpty {
            sections.append(RouteCollectionSection(
                kind: .merged,
                title: AppLocalization.text(.routeCollectionMergeSectionTitle),
                routes: mergedRoutes
            ))
        }

        routeSections = sections
    }

    private func numberOfItems(in section: Int) -> Int {
        guard section >= 0, section < routeSections.count else {
            return 0
        }

        switch routeSections[section].kind {
        case .imported:
            return loadingIDs.count + routeSections[section].routes.count
        case .merged:
            return routeSections[section].routes.count
        }
    }

    private func gridItem(at indexPath: IndexPath) -> WorkoutRouteGridItem? {
        guard indexPath.section >= 0,
              indexPath.section < routeSections.count,
              indexPath.item >= 0 else {
            return nil
        }

        let section = routeSections[indexPath.section]
        if section.kind == .imported, indexPath.item < loadingIDs.count {
            return WorkoutRouteGridItem.loading(
                id: loadingIDs[indexPath.item],
                title: AppLocalization.text(.routeCollectionImporting)
            )
        }

        let routeIndex = section.kind == .imported ? indexPath.item - loadingIDs.count : indexPath.item
        guard routeIndex >= 0, routeIndex < section.routes.count else {
            return nil
        }

        let route = section.routes[routeIndex]
        return WorkoutRouteGridItem.route(
            route,
            showsMap: false,
            showsNewBadge: SharedRouteImportInbox.hasNewRouteBadge(for: route)
        )
    }

    private func showRouteDetail(_ workout: TrackedWorkout) {
        if SharedRouteImportInbox.hasNewRouteBadge(for: workout) {
            SharedRouteImportInbox.clearNewRouteBadge(for: workout)
        }

        let detailViewController = WorkoutRouteDetailViewController(
            workout: workout,
            presentationMode: workout.isMergedRouteCollectionSource ? .workout : .routeCollection,
            mergeSourceWorkouts: routes
        )
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    private func makeRouteContextMenuConfiguration(for workout: TrackedWorkout) -> UIContextMenuConfiguration {
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
                self?.startRouteBookMode(with: workout)
            }

            let deleteAction = UIAction(
                title: AppLocalization.text(.delete),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.presentDeleteConfirmation(for: workout)
            }

            return UIMenu(children: [
                openStartAction,
                openEndAction,
                routeBookAction,
                deleteAction
            ])
        }
    }

    private func openEndpointInMaps(for workout: TrackedWorkout, kind: RouteEndpointKind) {
        guard let coordinate = endpointCoordinate(for: workout, kind: kind) else {
            presentSimpleAlert(title: AppLocalization.text(kind == .start ? .startNotFound : .endNotFound))
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
            presentSimpleAlert(title: AppLocalization.text(.systemMapsNotFound))
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

    private func startRouteBookMode(with workout: TrackedWorkout) {
        navigationController?.popToRootViewController(animated: true)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: RouteBookMode.didSelectWorkoutNotification,
                object: self,
                userInfo: [RouteBookMode.workoutUserInfoKey: workout]
            )
        }
    }

    private func presentDeleteConfirmation(for workout: TrackedWorkout) {
        let alertController = UIAlertController(
            title: AppLocalization.text(.deleteRoute),
            message: AppLocalization.text(.deleteRouteMessage),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.cancel), style: .cancel))
        alertController.addAction(UIAlertAction(
            title: AppLocalization.text(.delete),
            style: .destructive
        ) { [weak self] _ in
            self?.deleteRoute(workout)
        })
        present(alertController, animated: true)
    }

    private func deleteRoute(_ workout: TrackedWorkout) {
        SharedRouteImportInbox.clearNewRouteBadge(for: workout)
        routes = store.delete(workout)
        rebuildRouteSections()
        collectionView.reloadData()
        updateEmptyState()
    }

    private func presentSimpleAlert(title: String) {
        let alertController = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: AppLocalization.text(.ok), style: .default))
        present(alertController, animated: true)
    }

    @objc private func presentGPXPicker() {
        let gpxType = UTType(filenameExtension: "gpx") ?? UTType(importedAs: "com.topografix.gpx")
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [gpxType])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        present(documentPicker, animated: true)
    }

    private func importGPXFiles(at urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        let loadingID = UUID()
        loadingIDs.insert(loadingID, at: 0)
        rebuildRouteSections()
        collectionView.reloadData()
        updateEmptyState()

        Task { @MainActor in
            var importedRoutes: [TrackedWorkout] = []
            var lastError: Error?

            for url in urls {
                let shouldStopAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if shouldStopAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    importedRoutes.append(try SharedRouteImportInbox.makeRoute(fromGPXAt: url))
                } catch {
                    lastError = error
                }
            }

            if !importedRoutes.isEmpty {
                store.append(importedRoutes)
                routes = store.load()
                rebuildRouteSections()
            }

            removeLoadingCell(id: loadingID)
            updateEmptyState()

            if !importedRoutes.isEmpty {
                Toast.show(AppLocalization.text(.routeCollectionImportSuccess), in: view)
            } else if let lastError {
                Toast.show(lastError.localizedDescription, in: view)
            }
        }
    }

    private func removeLoadingCell(id: UUID) {
        guard let index = loadingIDs.firstIndex(of: id) else {
            return
        }

        loadingIDs.remove(at: index)
        rebuildRouteSections()
        collectionView.reloadData()
    }
}

extension RouteCollectionViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importGPXFiles(at: urls.filter { $0.pathExtension.lowercased() == "gpx" })
    }
}

private final class RouteCollectionICloudSyncFooterView: UIView {
    private let stackView = UIStackView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let imageView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    func configure(with configuration: RouteCollectionICloudSyncFooterConfiguration?) {
        guard let configuration else {
            isHidden = true
            activityIndicator.stopAnimating()
            imageView.image = nil
            titleLabel.text = nil
            return
        }

        isHidden = false
        titleLabel.text = configuration.text

        switch configuration.state {
        case .syncing:
            imageView.isHidden = true
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
        case .complete:
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true
            imageView.isHidden = false
            imageView.image = UIImage(systemName: "checkmark.icloud")
            imageView.tintColor = AppColors.movinnGreen
        case .error:
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true
            imageView.isHidden = false
            imageView.image = UIImage(systemName: "exclamationmark.icloud")
            imageView.tintColor = .systemOrange
        }
    }

    private func configureViews() {
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 7

        imageView.contentMode = .scaleAspectFit
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.isHidden = true

        activityIndicator.hidesWhenStopped = true
        activityIndicator.transform = CGAffineTransform(scaleX: 0.76, y: 0.76)
        activityIndicator.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.textColor = .secondaryLabel
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        stackView.addArrangedSubview(activityIndicator)
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(titleLabel)

        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).inset(8)
            make.leading.greaterThanOrEqualToSuperview().offset(24)
            make.trailing.lessThanOrEqualToSuperview().inset(24)
        }
    }
}
